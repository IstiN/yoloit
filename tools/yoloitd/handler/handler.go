package handler

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strings"

	"yoloitd/server"
	"yoloitd/session"
)

// Handler implements the HTTP API.
type Handler struct {
	server *server.Server
}

// New creates a handler backed by the given server.
func New(s *server.Server) *Handler {
	return &Handler{server: s}
}

// ServeHTTP routes incoming requests.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := strings.Trim(r.URL.Path, "/")
	parts := strings.Split(path, "/")

	switch r.Method {
	case http.MethodGet:
		if path == "health" {
			h.health(w, r)
			return
		}
		if path == "sessions" {
			h.listSessions(w, r)
			return
		}
		if len(parts) == 3 && parts[0] == "sessions" && parts[2] == "stream" {
			h.streamSession(w, r, parts[1])
			return
		}
	case http.MethodPost:
		if path == "sessions" {
			h.createSession(w, r)
			return
		}
		if len(parts) == 3 && parts[0] == "sessions" {
			id := parts[1]
			switch parts[2] {
			case "input":
				h.inputSession(w, r, id)
				return
			case "resize":
				h.resizeSession(w, r, id)
				return
			case "kill":
				h.killSession(w, r, id)
				return
			}
		}
	}

	h.json(w, map[string]any{"ok": false, "error": "not found"}, http.StatusNotFound)
}

func (h *Handler) health(w http.ResponseWriter, r *http.Request) {
	h.json(w, map[string]any{
		"ok":              true,
		"protocolVersion": 1,
		"pid":             0,
	}, http.StatusOK)
}

func (h *Handler) listSessions(w http.ResponseWriter, r *http.Request) {
	sessions := h.server.All()
	data := make([]map[string]any, 0, len(sessions))
	for _, s := range sessions {
		data = append(data, sessionToJSON(s))
	}
	h.json(w, map[string]any{"ok": true, "sessions": data}, http.StatusOK)
}

func (h *Handler) createSession(w http.ResponseWriter, r *http.Request) {
	var req session.CreateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.json(w, map[string]any{"ok": false, "error": err.Error()}, http.StatusBadRequest)
		return
	}

	sess, existing, err := h.server.Create(&req)
	if err != nil {
		h.json(w, map[string]any{"ok": false, "error": err.Error()}, http.StatusBadRequest)
		return
	}

	h.json(w, map[string]any{
		"ok":       true,
		"session":  sessionToJSON(sess),
		"existing": existing,
	}, http.StatusOK)
}

func (h *Handler) streamSession(w http.ResponseWriter, r *http.Request, id string) {
	sess, ok := h.server.Get(id)
	if !ok {
		h.json(w, map[string]any{"ok": false, "error": "session not found"}, http.StatusNotFound)
		return
	}

	replay := r.URL.Query().Get("replay") != "0"

	w.Header().Set("Content-Type", "application/x-ndjson")
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(http.StatusOK)

	flusher, ok := w.(http.Flusher)
	if !ok {
		return
	}

	if replay {
		for _, data := range sess.Ring() {
			writeEvent(w, session.Event{Type: "output", SessionID: id, Data: data})
		}
		flusher.Flush()
	}

	ch := sess.Subscribe()
	defer sess.Unsubscribe(ch)

	ctx := r.Context()
	for {
		select {
		case ev, ok := <-ch:
			if !ok {
				return
			}
			writeEvent(w, ev)
			flusher.Flush()
			if ev.Type == "exit" {
				return
			}
		case <-ctx.Done():
			return
		}
	}
}

func (h *Handler) inputSession(w http.ResponseWriter, r *http.Request, id string) {
	sess, ok := h.server.Get(id)
	if !ok {
		h.json(w, map[string]any{"ok": false, "error": "session not found"}, http.StatusNotFound)
		return
	}

	var payload struct {
		Data string `json:"data"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		h.json(w, map[string]any{"ok": false, "error": err.Error()}, http.StatusBadRequest)
		return
	}

	decoded, err := base64.StdEncoding.DecodeString(payload.Data)
	if err != nil {
		h.json(w, map[string]any{"ok": false, "error": err.Error()}, http.StatusBadRequest)
		return
	}

	if err := sess.Write(string(decoded)); err != nil {
		h.json(w, map[string]any{"ok": false, "error": err.Error()}, http.StatusInternalServerError)
		return
	}

	h.json(w, map[string]any{"ok": true}, http.StatusOK)
}

func (h *Handler) resizeSession(w http.ResponseWriter, r *http.Request, id string) {
	sess, ok := h.server.Get(id)
	if !ok {
		h.json(w, map[string]any{"ok": false, "error": "session not found"}, http.StatusNotFound)
		return
	}

	var payload struct {
		Cols int `json:"cols"`
		Rows int `json:"rows"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		h.json(w, map[string]any{"ok": false, "error": err.Error()}, http.StatusBadRequest)
		return
	}

	if err := sess.Resize(payload.Cols, payload.Rows); err != nil {
		h.json(w, map[string]any{"ok": false, "error": err.Error()}, http.StatusInternalServerError)
		return
	}

	h.json(w, map[string]any{"ok": true}, http.StatusOK)
}

func (h *Handler) killSession(w http.ResponseWriter, r *http.Request, id string) {
	sess, ok := h.server.Get(id)
	if !ok {
		h.json(w, map[string]any{"ok": false, "error": "session not found"}, http.StatusNotFound)
		return
	}

	sess.Kill()
	h.json(w, map[string]any{"ok": true}, http.StatusOK)
}

func (h *Handler) json(w http.ResponseWriter, data any, status int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}

func writeEvent(w http.ResponseWriter, ev session.Event) {
	_ = json.NewEncoder(w).Encode(ev)
	_, _ = w.Write([]byte("\n"))
}

func sessionToJSON(s *session.Session) map[string]any {
	return map[string]any{
		"id":        s.ID(),
		"cwd":       s.Cwd(),
		"command":   s.Command(),
		"createdAt": s.CreatedAt().Format("2006-01-02T15:04:05Z"),
		"alive":     s.Alive(),
		"pid":       s.PID(),
	}
}
