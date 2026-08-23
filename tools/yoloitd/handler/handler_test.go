package handler

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"yoloitd/server"
	"yoloitd/session"
)

func TestHealth(t *testing.T) {
	h := New(server.New())
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()

	h.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
	if resp["ok"] != true {
		t.Fatalf("expected ok=true")
	}
}

func TestCreateSession(t *testing.T) {
	h := New(server.New())
	body, _ := json.Marshal(session.CreateRequest{
		ID:      "s1",
		Command: "echo hello",
		Cols:    80,
		Rows:    24,
	})
	req := httptest.NewRequest(http.MethodPost, "/sessions", bytes.NewReader(body))
	w := httptest.NewRecorder()

	h.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
	if resp["ok"] != true {
		t.Fatalf("expected ok=true")
	}
}

func TestNotFound(t *testing.T) {
	h := New(server.New())
	req := httptest.NewRequest(http.MethodGet, "/unknown", nil)
	w := httptest.NewRecorder()

	h.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

func TestGetMissingSession(t *testing.T) {
	h := New(server.New())
	req := httptest.NewRequest(http.MethodPost, "/sessions/missing/resize", bytes.NewReader([]byte(`{"cols":80,"rows":24}`)))
	w := httptest.NewRecorder()

	h.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

// A stream reconnect with ?since=N must replay only events newer than N —
// a full replay would duplicate already-rendered output and corrupt the
// client terminal screen.
func TestStreamSinceReplaysOnlyNewerEvents(t *testing.T) {
	srv := server.New()
	h := New(srv)
	ts := httptest.NewServer(h)
	defer ts.Close()

	// Start a session that emits one line then stays alive.
	body, _ := json.Marshal(session.CreateRequest{
		ID:      "s1",
		Command: "echo hello-from-ring; sleep 30",
		Cols:    80,
		Rows:    24,
	})
	resp, err := http.Post(ts.URL+"/sessions", "application/json", bytes.NewReader(body))
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	resp.Body.Close()
	defer func() {
		resp, err := http.Post(ts.URL+"/sessions/s1/kill", "application/json", nil)
		if err == nil {
			resp.Body.Close()
		}
	}()

	// Wait until the echo output has landed in the ring.
	sess, _ := srv.Get("s1")
	var lastSeq int64
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		ring := sess.Ring()
		if len(ring) > 0 && strings.Contains(ring[len(ring)-1].Data, "hello-from-ring") {
			lastSeq = ring[len(ring)-1].Seq
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if lastSeq == 0 {
		t.Fatal("echo output never reached the ring")
	}

	// Full replay (no since): must contain the echoed line.
	if !streamContains(ts.URL+"/sessions/s1/stream", "hello-from-ring", 3*time.Second) {
		t.Fatal("full replay did not deliver the ring content")
	}

	// Incremental replay at the tail: must NOT contain the echoed line again.
	if streamContains(ts.URL+"/sessions/s1/stream?since="+strconv.FormatInt(lastSeq, 10), "hello-from-ring", 1500*time.Millisecond) {
		t.Fatal("since-replay duplicated already-delivered output")
	}
}

// streamContains reads the NDJSON stream until it finds an event containing
// want or the timeout expires.
func streamContains(url, want string, timeout time.Duration) bool {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return false
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	scanner := bufio.NewScanner(resp.Body)
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024)
	for scanner.Scan() {
		if strings.Contains(scanner.Text(), want) {
			return true
		}
	}
	return false
}
