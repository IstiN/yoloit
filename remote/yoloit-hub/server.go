package main

// HTTP server: mux setup, auth middleware mirroring isAuthorized() from
// lib/core/remote/server_process_utils.dart, and CORS middleware.

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"strings"
)

type server struct {
	store       *Store
	token       string
	corsOrigins []string
	mux         *http.ServeMux
}

func newServer(store *Store, token, corsOrigins string) *server {
	s := &server{store: store, token: strings.TrimSpace(token)}
	s.corsOrigins = parseOrigins(corsOrigins)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api", s.handleAPIRoot)
	mux.HandleFunc("GET /api/health", s.handleHealth)
	mux.HandleFunc("/api/boards", s.handleBoardsRoot)
	mux.HandleFunc("/api/boards/", s.handleBoardsSubtree)
	mux.HandleFunc("/", s.handleRoot)
	s.mux = mux
	return s
}

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.cors(s.auth(s.mux)).ServeHTTP(w, r)
}

// cors adds permissive cross-origin headers (the Dart yoloitd has none; this
// is additive and required for browser-based clients) and answers preflight
// OPTIONS before auth so browsers can negotiate without a token.
func (s *server) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		allowed := "*"
		if !s.allowsAllOrigins() {
			allowed = ""
			for _, candidate := range s.corsOrigins {
				if candidate == origin {
					allowed = origin
					break
				}
			}
		}
		if allowed != "" {
			w.Header().Set("Access-Control-Allow-Origin", allowed)
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *server) allowsAllOrigins() bool {
	for _, o := range s.corsOrigins {
		if o == "*" {
			return true
		}
	}
	return false
}

func parseOrigins(raw string) []string {
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	if len(out) == 0 {
		return []string{"*"}
	}
	return out
}

// auth mirrors isAuthorized(request, token): no token configured means open
// access; otherwise require `Authorization: Bearer <token>` or `?token=`.
func (s *server) auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !s.authorized(r) {
			writeJSON(w, http.StatusUnauthorized, map[string]any{
				"ok":    false,
				"error": "unauthorized",
			})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *server) authorized(r *http.Request) bool {
	if s.token == "" {
		return true
	}
	if r.Header.Get("Authorization") == "Bearer "+s.token {
		return true
	}
	return r.URL.Query().Get("token") == s.token
}

func (s *server) handleAPIRoot(w http.ResponseWriter, _ *http.Request) {
	// The Dart yoloitd returns {"service": "yoloitd"} here. No Flutter client
	// or CLI command asserts that exact string (verified in
	// yoloit_remote_client.dart, board_cubit.dart and tools/yoloit: the CLI
	// only checks /health returns valid JSON), so yoloit-hub reports its own
	// identity while keeping the envelope shape identical.
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "service": "yoloit-hub"})
}

func (s *server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":      true,
		"service": "yoloit-hub",
		"dataDir": s.store.RootDir,
		"watch":   false, // WebSocket watch capability lands in a later phase
	})
}

func (s *server) handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		writeJSON(w, http.StatusNotFound, map[string]any{"ok": false, "error": "not found"})
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = io.WriteString(w, s.dashboardHTML())
}

// --- shared response helpers (mirror jsonResponse/readJsonBody) ---

// writeJSON mirrors jsonResponse: compact JSON, no HTML escaping,
// content-type application/json; charset=utf-8.
func writeJSON(w http.ResponseWriter, status int, body any) {
	data, err := marshalCompact(body)
	if err != nil {
		data = []byte(`{"ok":false,"error":"failed to encode response"}`)
		status = http.StatusInternalServerError
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_, _ = w.Write(data)
}

func marshalCompact(v any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return nil, err
	}
	return bytes.TrimRight(buf.Bytes(), "\n"), nil
}

// readJSONBody mirrors readJsonBody: empty or non-object bodies become {}.
func readJSONBody(r *http.Request) (map[string]any, error) {
	data, err := io.ReadAll(io.LimitReader(r.Body, 32<<20))
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(string(data)) == "" {
		return map[string]any{}, nil
	}
	var body map[string]any
	if err := decodeUseNumber(data, &body); err != nil {
		return nil, err
	}
	if body == nil {
		body = map[string]any{}
	}
	return body, nil
}

// fail mirrors the top-level catch in YoloitdServer._handle: 500 with the
// error text in the envelope.
func fail(w http.ResponseWriter, err error) {
	writeJSON(w, http.StatusInternalServerError, map[string]any{
		"ok":    false,
		"error": err.Error(),
	})
}

func notFound(w http.ResponseWriter) {
	writeJSON(w, http.StatusNotFound, map[string]any{"ok": false, "error": "not found"})
}

func trimSpace(s string) string { return strings.TrimSpace(s) }

func (s *server) dashboardHTML() string {
	tokenQuery := ""
	if s.token != "" {
		tokenQuery = "?token=" + s.token
	}
	return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>YoLoIT Remote</title>
  <style>
    body{font-family:system-ui,-apple-system,sans-serif;background:#111827;color:#e5e7eb;margin:0;padding:24px}
    button,input{font:inherit}
    .card{border:1px solid #334155;border-radius:8px;padding:16px;margin:12px 0;background:#1f2937}
    a{color:#93c5fd}
  </style>
</head>
<body>
  <h1>YoLoIT Remote</h1>
  <p>yoloit-hub daemon is running. Use <code>tools/yoloit remote:connect</code> or the REST API.</p>
  <div id="boards"></div>
  <script>
    fetch('/api/boards` + tokenQuery + `').then(r=>r.json()).then(data=>{
      document.getElementById('boards').innerHTML=(data.boards||[]).map(b=>
        '<div class="card"><b>'+b.name+'</b><br>'+b.id+'<br>'+b.panelCount+' panels</div>'
      ).join('');
    });
  </script>
</body>
</html>
`
}
