package session

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unicode/utf8"

	"github.com/creack/pty"
)

var debugEnabled = atomic.Bool{}

func init() {
	debugEnabled.Store(os.Getenv("YOLOITD_DEBUG") == "1")
}

func debugLog(format string, v ...any) {
	if debugEnabled.Load() {
		log.Printf(format, v...)
	}
}

// Event represents a terminal event sent to subscribers.
type Event struct {
	Type      string `json:"type"`
	SessionID string `json:"sessionId"`
	Data      string `json:"data,omitempty"`
	ExitCode  int    `json:"exitCode,omitempty"`
}

// CreateRequest holds parameters for starting a new session.
type CreateRequest struct {
	ID      string            `json:"id"`
	Cwd     string            `json:"cwd"`
	Command string            `json:"command"`
	Cols    int               `json:"cols"`
	Rows    int               `json:"rows"`
	Env     map[string]string `json:"env"`
}

// Session wraps a PTY and its subprocess.
type Session struct {
	id           string
	cwd          string
	command      string
	createdAt    time.Time
	ptmx         *os.File
	cmd          *exec.Cmd
	subscribers  []chan Event
	ring         []string
	ringBytes    int
	maxRingBytes int
	alive        bool
	exitCode     int
	mu           sync.RWMutex
}

// New starts a new PTY session.
func New(req *CreateRequest) (*Session, error) {
	if req.Cwd == "" {
		req.Cwd, _ = os.Getwd()
	}
	if req.Command == "" {
		req.Command = os.Getenv("SHELL")
		if req.Command == "" {
			req.Command = "/bin/sh"
		}
	}
	if req.Cols == 0 {
		req.Cols = 120
	}
	if req.Rows == 0 {
		req.Rows = 30
	}

	var cmd *exec.Cmd
	if strings.Contains(req.Command, " ") {
		cmd = exec.Command("sh", "-c", req.Command)
	} else {
		// Plain interactive shell — login shells (-l) can re-source profile files
		// and drop env vars injected by YoLoIT env groups.
		cmd = exec.Command(req.Command)
	}
	cmd.Dir = req.Cwd

	// Build environment map to deduplicate and ensure required vars.
	envMap := make(map[string]string)
	for _, e := range os.Environ() {
		if i := strings.Index(e, "="); i >= 0 {
			envMap[e[:i]] = e[i+1:]
		}
	}
	for k, v := range req.Env {
		envMap[k] = v
	}
	envMap["TERM"] = "xterm-256color"
	envMap["COLORTERM"] = "truecolor"
	if envMap["LANG"] == "" {
		envMap["LANG"] = "en_US.UTF-8"
	}

	env := make([]string, 0, len(envMap))
	for k, v := range envMap {
		env = append(env, fmt.Sprintf("%s=%s", k, v))
	}
	cmd.Env = env

	debugLog("[session] starting command=%s cwd=%s cols=%d rows=%d env_keys=%d", req.Command, req.Cwd, req.Cols, req.Rows, len(envMap))

	ptmx, err := pty.StartWithSize(cmd, &pty.Winsize{
		Cols: uint16(req.Cols),
		Rows: uint16(req.Rows),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to start pty: %w", err)
	}

	s := &Session{
		id:           req.ID,
		cwd:          req.Cwd,
		command:      req.Command,
		createdAt:    time.Now(),
		ptmx:         ptmx,
		cmd:          cmd,
		subscribers:  make([]chan Event, 0),
		ring:         make([]string, 0),
		maxRingBytes: 512 * 1024,
		alive:        true,
	}

	log.Printf("[session] created id=%s command=%s cwd=%s cols=%d rows=%d pid=%d", s.id, s.command, s.cwd, req.Cols, req.Rows, s.PID())

	go s.readLoop()
	go s.waitLoop()

	return s, nil
}

const (
	// PTY read buffer. 32KB keeps syscall and publish rates low under floods
	// while staying small enough that interactive writes are unaffected.
	readChunkBytes = 32 * 1024

	// maxBatchBytes bounds how much output one published event may carry.
	maxBatchBytes = 128 * 1024

	// coalesceWindow bounds how long the publisher waits to accumulate more
	// output before emitting an event. Well under one display frame, so
	// interactive echo is not perceptibly delayed, while bursts collapse
	// into few large events instead of one event per PTY read.
	coalesceWindow = 10 * time.Millisecond
)

func (s *Session) readLoop() {
	// A dedicated goroutine does the blocking PTY reads; the publisher below
	// batches whatever arrives within the coalesce window so floods produce
	// few large events instead of one event per (often tiny) PTY read.
	// (SetReadDeadline is not supported on creack/pty master fds, so a
	// deadline-based drain is not an option.)
	chunks := make(chan []byte, 64)
	go func() {
		defer close(chunks)
		buf := make([]byte, readChunkBytes)
		for {
			n, err := s.ptmx.Read(buf)
			if n > 0 {
				debugLog("[session] read id=%s bytes=%d", s.id, n)
				chunks <- append([]byte(nil), buf[:n]...)
			}
			if err != nil {
				debugLog("[session] read err id=%s err=%v", s.id, err)
				return
			}
		}
	}()

	var carry []byte
	publish := func(batch []byte) {
		combined := append(carry, batch...)
		validLen := validUTF8Prefix(combined)
		if validLen > 0 {
			data := string(combined[:validLen])
			debugLog("[session] publish id=%s dataLen=%d", s.id, len(data))
			s.appendRing(data)
			s.publish(Event{Type: "output", SessionID: s.id, Data: data})
			carry = append([]byte(nil), combined[validLen:]...)
		} else {
			carry = append([]byte(nil), combined...)
		}
	}

	for batch := range chunks {
		timer := time.NewTimer(coalesceWindow)
		drain := true
		for drain && len(batch) < maxBatchBytes {
			select {
			case c, ok := <-chunks:
				if !ok {
					drain = false
				} else {
					batch = append(batch, c...)
				}
			case <-timer.C:
				drain = false
			}
		}
		timer.Stop()
		publish(batch)
	}

	// PTY closed: flush any trailing incomplete UTF-8 bytes verbatim.
	debugLog("[session] read loop done id=%s carry=%d", s.id, len(carry))
	if len(carry) > 0 {
		data := string(carry)
		s.appendRing(data)
		s.publish(Event{Type: "output", SessionID: s.id, Data: data})
	}
}

// validUTF8Prefix returns the length of the longest valid UTF-8 prefix,
// keeping up to 3 trailing bytes as potentially incomplete.
func validUTF8Prefix(p []byte) int {
	if utf8.Valid(p) {
		return len(p)
	}
	for i := 1; i <= 3 && i < len(p); i++ {
		if utf8.Valid(p[:len(p)-i]) {
			return len(p) - i
		}
	}
	return 0
}

func (s *Session) waitLoop() {
	_ = s.cmd.Wait()
	s.mu.Lock()
	s.alive = false
	if s.cmd.ProcessState != nil {
		s.exitCode = s.cmd.ProcessState.ExitCode()
	}
	s.mu.Unlock()

	log.Printf("[session] exited id=%s exitCode=%d", s.id, s.exitCode)

	s.publish(Event{Type: "exit", SessionID: s.id, ExitCode: s.exitCode})
	_ = s.ptmx.Close()
}

func (s *Session) appendRing(data string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.ring = append(s.ring, data)
	s.ringBytes += len(data)
	for s.ringBytes > s.maxRingBytes && len(s.ring) > 0 {
		removed := s.ring[0]
		s.ring = s.ring[1:]
		s.ringBytes -= len(removed)
	}
}

func (s *Session) publish(ev Event) {
	s.mu.RLock()
	subs := make([]chan Event, len(s.subscribers))
	copy(subs, s.subscribers)
	s.mu.RUnlock()

	for _, ch := range subs {
		select {
		case ch <- ev:
		default:
			log.Printf("[session] dropped event id=%s type=%s (subscriber channel full)", s.id, ev.Type)
		}
	}
}

// Subscribe registers a new event channel.
func (s *Session) Subscribe() chan Event {
	ch := make(chan Event, 1000)
	s.mu.Lock()
	s.subscribers = append(s.subscribers, ch)
	s.mu.Unlock()
	return ch
}

// Unsubscribe removes a channel and closes it.
func (s *Session) Unsubscribe(ch chan Event) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, sub := range s.subscribers {
		if sub == ch {
			s.subscribers = append(s.subscribers[:i], s.subscribers[i+1:]...)
			break
		}
	}
	close(ch)
}

// Write sends input to the PTY.
func (s *Session) Write(data string) error {
	debugLog("[session] write id=%s dataLen=%d", s.id, len(data))
	_, err := s.ptmx.WriteString(data)
	return err
}

// Resize changes the terminal dimensions.
func (s *Session) Resize(cols, rows int) error {
	log.Printf("[session] resize id=%s cols=%d rows=%d", s.id, cols, rows)
	return pty.Setsize(s.ptmx, &pty.Winsize{
		Cols: uint16(cols),
		Rows: uint16(rows),
	})
}

// Kill terminates the session gracefully (SIGTERM then SIGKILL).
func (s *Session) Kill() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.alive {
		return
	}
	log.Printf("[session] kill id=%s pid=%d", s.id, s.PID())
	if s.cmd.Process != nil {
		_ = s.cmd.Process.Signal(syscall.SIGTERM)
		go func(pid int) {
			time.Sleep(2 * time.Second)
			_ = syscall.Kill(pid, syscall.SIGKILL)
		}(s.cmd.Process.Pid)
	}
	s.alive = false
}

// Alive reports whether the session is still running.
func (s *Session) Alive() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.alive
}

// ID returns the session identifier.
func (s *Session) ID() string { return s.id }

// Cwd returns the working directory.
func (s *Session) Cwd() string { return s.cwd }

// Command returns the shell command.
func (s *Session) Command() string { return s.command }

// CreatedAt returns the creation timestamp.
func (s *Session) CreatedAt() time.Time { return s.createdAt }

// PID returns the OS process id.
func (s *Session) PID() int {
	if s.cmd.Process != nil {
		return s.cmd.Process.Pid
	}
	return 0
}

// Ring returns a copy of the replay buffer.
func (s *Session) Ring() []string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	r := make([]string, len(s.ring))
	copy(r, s.ring)
	return r
}

// ExitCode returns the process exit code.
func (s *Session) ExitCode() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.exitCode
}
