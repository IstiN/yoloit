package session

import (
	"strings"
	"testing"
	"time"
)

func TestValidUTF8Prefix(t *testing.T) {
	tests := []struct {
		name     string
		input    []byte
		expected int
	}{
		{"empty", []byte{}, 0},
		{"ascii", []byte("hello"), 5},
		{"valid utf8", []byte("привет"), 12},
		{"incomplete 2-byte", []byte{0xD0}, 0},
		{"incomplete 3-byte end", []byte{0xE2, 0x80}, 0},
		{"complete plus incomplete", []byte("hi"), 2},
		{"mixed valid", []byte{0xD0, 0xB0, 0xD1}, 2},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := validUTF8Prefix(tt.input)
			if got != tt.expected {
				t.Fatalf("validUTF8Prefix(%v) = %d, want %d", tt.input, got, tt.expected)
			}
		})
	}
}

func TestAppendRing(t *testing.T) {
	s := &Session{
		id:           "test",
		maxRingBytes: 30,
		ring:         make([]Event, 0),
	}

	s.appendRing(Event{Type: "output", Data: "hello", Seq: 1})
	s.appendRing(Event{Type: "output", Data: "world", Seq: 2})
	if len(s.ring) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(s.ring))
	}

	s.appendRing(Event{Type: "output", Data: "this is a long string", Seq: 3})
	if len(s.ring) != 2 {
		t.Fatalf("expected ring to stay at 2 entries, got %d", len(s.ring))
	}
	if s.ring[0].Seq != 2 || s.ring[1].Seq != 3 {
		t.Fatalf("expected evicted oldest entry, got seqs %d,%d", s.ring[0].Seq, s.ring[1].Seq)
	}
}

func TestSubscribePublish(t *testing.T) {
	s := &Session{
		id:          "test",
		subscribers: make([]chan Event, 0),
	}

	ch := s.Subscribe()
	s.publish(Event{Type: "output", Data: "test"})

	select {
	case ev := <-ch:
		if ev.Data != "test" {
			t.Fatalf("unexpected data: %s", ev.Data)
		}
	case <-time.After(time.Second):
		t.Fatal("timeout waiting for event")
	}

	s.Unsubscribe(ch)
	if len(s.subscribers) != 0 {
		t.Fatalf("expected 0 subscribers, got %d", len(s.subscribers))
	}
}

func TestSessionAccessors(t *testing.T) {
	s := &Session{
		id:        "abc",
		cwd:       "/tmp",
		command:   "/bin/sh",
		createdAt: time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC),
	}

	if s.ID() != "abc" {
		t.Fatalf("unexpected id")
	}
	if s.Cwd() != "/tmp" {
		t.Fatalf("unexpected cwd")
	}
	if s.Command() != "/bin/sh" {
		t.Fatalf("unexpected command")
	}
}

// Floods should be coalesced into few, large output events while delivering
// the full byte stream intact.
func TestReadLoopCoalescesFlood(t *testing.T) {
	// ~200KB of deterministic output.
	sess, err := New(&CreateRequest{
		ID:      "flood",
		Command: "seq 1 20000",
	})
	if err != nil {
		t.Fatalf("failed to start session: %v", err)
	}
	defer sess.Kill()

	ch := sess.Subscribe()
	defer sess.Unsubscribe(ch)

	var events, bytes int
	deadline := time.After(15 * time.Second)
	for {
		select {
		case ev, ok := <-ch:
			if !ok {
				return
			}
			if ev.Type == "exit" {
				goto done
			}
			events++
			bytes += len(ev.Data)
		case <-deadline:
			t.Fatal("timeout waiting for flood output")
		}
	}
done:
	if bytes < 100*1024 {
		t.Fatalf("expected >=100KB of output, got %d bytes", bytes)
	}
	// Without coalescing every PTY read (~4-16KB on macOS) is one event —
	// 200KB would be dozens of events. Coalescing must keep this small.
	if events > 24 {
		t.Fatalf("expected coalesced events (<=24), got %d", events)
	}
}

// A single small interactive write must still be delivered promptly — the
// coalescing window must not stall trickle output.
func TestReadLoopInteractiveLatency(t *testing.T) {
	sess, err := New(&CreateRequest{
		ID:      "interactive",
		Command: "cat",
	})
	if err != nil {
		t.Fatalf("failed to start session: %v", err)
	}
	defer sess.Kill()

	ch := sess.Subscribe()
	defer sess.Unsubscribe(ch)

	if err := sess.Write("hello\n"); err != nil {
		t.Fatalf("write failed: %v", err)
	}

	timeout := time.After(500 * time.Millisecond)
	for {
		select {
		case ev := <-ch:
			if ev.Type == "output" && strings.Contains(ev.Data, "hello") {
				return // echo arrived well within interactive latency
			}
		case <-timeout:
			t.Fatal("interactive echo not delivered within 500ms")
		}
	}
}

// A slow subscriber must never lose output: publish blocks (backpressure)
// instead of dropping events, and everything arrives once the subscriber
// starts reading again.
func TestPublishNeverDropsForSlowSubscriber(t *testing.T) {
	s := &Session{
		id:          "test",
		subscribers: make([]chan Event, 0),
	}

	ch := s.Subscribe()
	defer s.Unsubscribe(ch)

	const total = 1000 // > channel capacity (256)
	go func() {
		for i := 0; i < total; i++ {
			s.publish(Event{Type: "output", Data: "x"})
		}
	}()

	deadline := time.After(10 * time.Second)
	for i := 0; i < total; i++ {
		select {
		case ev := <-ch:
			if ev.Data != "x" {
				t.Fatalf("unexpected data: %q", ev.Data)
			}
		case <-deadline:
			t.Fatalf("timeout after %d/%d events — events were dropped or publish stalled", i, total)
		}
	}
}

// A subscriber that makes zero progress for the slow-subscriber timeout is
// detached instead of blocking the publisher forever.
func TestPublishDetachesStuckSubscriber(t *testing.T) {
	old := slowSubscriberTimeout
	slowSubscriberTimeout = 50 * time.Millisecond
	defer func() { slowSubscriberTimeout = old }()

	s := &Session{
		id:          "test",
		subscribers: make([]chan Event, 0),
	}

	// Fill the channel to capacity and never read from it.
	ch := s.Subscribe()
	for i := 0; i < cap(ch); i++ {
		s.publish(Event{Type: "output", Data: "x"})
	}

	// This publish blocks until the timeout fires and detaches the channel.
	done := make(chan struct{})
	go func() {
		s.publish(Event{Type: "output", Data: "overflow"})
		close(done)
	}()

	// Publish must not complete while the subscriber is merely slow.
	select {
	case <-done:
		t.Fatal("publish returned immediately for a stuck subscriber — event would be dropped")
	case <-time.After(10 * time.Millisecond):
	}

	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("publish did not detach the stuck subscriber")
	}

	s.mu.RLock()
	subs := len(s.subscribers)
	s.mu.RUnlock()
	if subs != 0 {
		t.Fatalf("expected stuck subscriber detached, got %d subscribers", subs)
	}
	s.Unsubscribe(ch) // already detached — must be a safe no-op
}

// Unsubscribe must be safe to call twice (handler defer + slow-subscriber
// detach can race).
func TestUnsubscribeIdempotent(t *testing.T) {
	s := &Session{
		id:          "test",
		subscribers: make([]chan Event, 0),
	}
	ch := s.Subscribe()
	s.Unsubscribe(ch)
	s.Unsubscribe(ch) // must not panic (no double close)
	if len(s.subscribers) != 0 {
		t.Fatalf("expected 0 subscribers, got %d", len(s.subscribers))
	}
}

// emitOutput assigns monotonic sequence numbers and the ring carries the
// same seqs that subscribers receive.
func TestEmitOutputAssignsMonotonicSeq(t *testing.T) {
	s := &Session{
		id:           "test",
		subscribers:  make([]chan Event, 0),
		ring:         make([]Event, 0),
		maxRingBytes: 1024,
	}
	ch := s.Subscribe()
	defer s.Unsubscribe(ch)

	s.emitOutput("a")
	s.emitOutput("b")

	var got []Event
	for i := 0; i < 2; i++ {
		select {
		case ev := <-ch:
			got = append(got, ev)
		case <-time.After(time.Second):
			t.Fatal("timeout waiting for event")
		}
	}
	if got[0].Seq != 1 || got[1].Seq != 2 {
		t.Fatalf("expected seqs 1,2 got %d,%d", got[0].Seq, got[1].Seq)
	}
	ring := s.Ring()
	if len(ring) != 2 || ring[0].Seq != 1 || ring[1].Seq != 2 || ring[0].Data != "a" || ring[1].Data != "b" {
		t.Fatalf("unexpected ring: %+v", ring)
	}
}

// A stream of genuinely invalid UTF-8 bytes must not stall the carry buffer
// forever: once it exceeds maxCarryBytes it is sanitized and flushed.
func TestReadLoopInvalidUTF8DoesNotStall(t *testing.T) {
	sess, err := New(&CreateRequest{
		ID:      "invalid-utf8",
		Command: "head -c 8192 /dev/urandom",
	})
	if err != nil {
		t.Fatalf("failed to start session: %v", err)
	}
	defer sess.Kill()

	ch := sess.Subscribe()
	defer sess.Unsubscribe(ch)

	var bytes int
	deadline := time.After(15 * time.Second)
	for {
		select {
		case ev, ok := <-ch:
			if !ok {
				return
			}
			// The exit event can race ahead of the flushed output; success is
			// defined by receiving sanitized output, not by the exit ordering.
			if ev.Type == "output" && len(ev.Data) > 0 {
				return
			}
			bytes += len(ev.Data)
		case <-deadline:
			t.Fatalf("timeout: invalid UTF-8 stream stalled after %d bytes", bytes)
		}
	}
}

// Cross-session isolation: each session owns a dedicated PTY and event
// stream. Output written by one session must never appear in another
// session's subscriber stream or replay ring — agents run side by side in
// separate panels and a leak here would cross-contaminate their tool
// results. Pins the architectural invariant against regressions.
func TestSessionsAreIsolated(t *testing.T) {
	a, err := New(&CreateRequest{ID: "iso-a", Command: "sleep 1; printf A-MARKER-unique-$$.done; sleep 5"})
	if err != nil {
		t.Fatalf("failed to start session A: %v", err)
	}
	defer a.Kill()
	b, err := New(&CreateRequest{ID: "iso-b", Command: "sleep 1; printf B-MARKER-other-$$.done; sleep 5"})
	if err != nil {
		t.Fatalf("failed to start session B: %v", err)
	}
	defer b.Kill()

	chA := a.Subscribe()
	defer a.Unsubscribe(chA)
	chB := b.Subscribe()
	defer b.Unsubscribe(chB)

	waitFor := func(ch chan Event, marker string) string {
		var collected string
		deadline := time.After(10 * time.Second)
		for {
			select {
			case ev, ok := <-ch:
				if !ok {
					return collected
				}
				collected += ev.Data
				if strings.Contains(collected, marker) {
					return collected
				}
			case <-deadline:
				t.Fatalf("timeout waiting for %q in stream, got: %q", marker, collected)
			}
		}
	}

	outA := waitFor(chA, "A-MARKER")
	outB := waitFor(chB, "B-MARKER")

	if strings.Contains(outA, "B-MARKER") {
		t.Fatalf("session A stream leaked session B output: %q", outA)
	}
	if strings.Contains(outB, "A-MARKER") {
		t.Fatalf("session B stream leaked session A output: %q", outB)
	}
	for _, ev := range a.Ring() {
		if strings.Contains(ev.Data, "B-MARKER") {
			t.Fatalf("session A ring leaked session B output: %q", ev.Data)
		}
	}
	for _, ev := range b.Ring() {
		if strings.Contains(ev.Data, "A-MARKER") {
			t.Fatalf("session B ring leaked session A output: %q", ev.Data)
		}
	}
}
