package session

import (
	"strings"
	"testing"
	"time"
)

// A fresh Flutter emulator attaches to an existing alt-buffer TUI with only
// the recent differential output ring. Its first viewport resize commonly has
// the same dimensions the PTY already has, so the OS does not emit SIGWINCH.
// Without an explicit redraw request the TUI never repaints its full screen:
// the replay tail stays interleaved with old frames until a real resize.
func TestSameSizeResizeRequestsAltBufferRedraw(t *testing.T) {
	sess, err := New(&CreateRequest{
		ID:   "same-size-alt-redraw",
		Cols: 80,
		Rows: 24,
		Command: `trap 'printf "WINCH\n"' WINCH; ` +
			`printf '\033[?1049hREADY\n'; while :; do sleep 1; done`,
	})
	if err != nil {
		t.Fatalf("failed to start session: %v", err)
	}
	defer sess.Kill()

	ch := sess.Subscribe()
	defer sess.Unsubscribe(ch)

	waitForOutput := func(want string, timeout time.Duration) {
		t.Helper()
		deadline := time.After(timeout)
		for {
			select {
			case ev := <-ch:
				if ev.Type == "output" && strings.Contains(ev.Data, want) {
					return
				}
			case <-deadline:
				t.Fatalf("timed out waiting for %q", want)
			}
		}
	}

	waitForOutput("READY", 3*time.Second)
	if err := sess.Resize(80, 24); err != nil {
		t.Fatalf("same-size resize failed: %v", err)
	}
	waitForOutput("WINCH", 3*time.Second)
}
