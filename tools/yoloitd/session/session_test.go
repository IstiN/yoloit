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
		ring:         make([]string, 0),
	}

	s.appendRing("hello")
	s.appendRing("world")
	if len(s.ring) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(s.ring))
	}

	s.appendRing("this is a long string")
	if len(s.ring) != 2 {
		t.Fatalf("expected ring to stay at 2 entries, got %d", len(s.ring))
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
