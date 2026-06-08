package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

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
