package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// newTestServer returns a started server backed by a fresh temp data dir.
// The store is initialized, mirroring server startup (a default board exists).
func newTestServer(t *testing.T, token string) (*httptest.Server, *Store, string) {
	t.Helper()
	dataDir := t.TempDir()
	store := NewStore(dataDir, "test-actor")
	if err := store.Init(); err != nil {
		t.Fatalf("store init: %v", err)
	}
	srv := httptest.NewServer(newServer(store, token, "*", newRelayHub(t.TempDir())))
	t.Cleanup(srv.Close)
	return srv, store, dataDir
}

func do(t *testing.T, method, url, token string, body any) (*http.Response, map[string]any, string) {
	t.Helper()
	var reader *strings.Reader
	if body == nil {
		reader = strings.NewReader("")
	} else {
		data, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal request body: %v", err)
		}
		reader = strings.NewReader(string(data))
	}
	req, err := http.NewRequest(method, url, reader)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("request %s %s: %v", method, url, err)
	}
	defer resp.Body.Close()
	raw := readAll(t, resp)
	var parsed map[string]any
	if len(strings.TrimSpace(raw)) > 0 && strings.HasPrefix(strings.TrimSpace(raw), "{") {
		if err := json.Unmarshal([]byte(raw), &parsed); err != nil {
			t.Fatalf("response is not a JSON object: %q", raw)
		}
	}
	return resp, parsed, raw
}

func readAll(t *testing.T, resp *http.Response) string {
	t.Helper()
	buf := make([]byte, 0, 512)
	tmp := make([]byte, 512)
	for {
		n, err := resp.Body.Read(tmp)
		buf = append(buf, tmp[:n]...)
		if err != nil {
			break
		}
	}
	return string(buf)
}

// defaultBoardID fetches the id of the seeded default board.
func defaultBoardID(t *testing.T, srv *httptest.Server, token string) string {
	t.Helper()
	_, body, _ := do(t, http.MethodGet, srv.URL+"/api/boards", token, nil)
	boards, _ := body["boards"].([]any)
	if len(boards) == 0 {
		t.Fatal("expected at least the seeded default board")
	}
	first, _ := boards[0].(map[string]any)
	id, _ := first["id"].(string)
	if id == "" {
		t.Fatalf("board summary missing id: %v", first)
	}
	return id
}

func TestAuthOpenWhenNoToken(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	resp, body, _ := do(t, http.MethodGet, srv.URL+"/api/health", "", nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("health without token: status %d", resp.StatusCode)
	}
	if body["ok"] != true {
		t.Fatalf("health body: %v", body)
	}
}

func TestAuthRejectsWrongToken(t *testing.T) {
	srv, _, _ := newTestServer(t, "secret")
	resp, body, _ := do(t, http.MethodGet, srv.URL+"/api/health", "wrong", nil)
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("wrong token: status %d, want 401", resp.StatusCode)
	}
	if body["ok"] != false || body["error"] != "unauthorized" {
		t.Fatalf("401 body: %v", body)
	}
}

func TestAuthAcceptsBearerAndQueryToken(t *testing.T) {
	srv, _, _ := newTestServer(t, "secret")

	resp, _, _ := do(t, http.MethodGet, srv.URL+"/api/health", "secret", nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("bearer token: status %d", resp.StatusCode)
	}

	resp, _, _ = do(t, http.MethodGet, srv.URL+"/api/health?token=secret", "", nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("query token: status %d", resp.StatusCode)
	}
}

func TestCORSPreflight(t *testing.T) {
	srv, _, _ := newTestServer(t, "secret")
	req, _ := http.NewRequest(http.MethodOptions, srv.URL+"/api/boards", nil)
	req.Header.Set("Origin", "http://localhost:3000")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("preflight: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("preflight status %d, want 204", resp.StatusCode)
	}
	if got := resp.Header.Get("Access-Control-Allow-Origin"); got != "*" {
		t.Fatalf("allow-origin %q, want *", got)
	}
	if got := resp.Header.Get("Access-Control-Allow-Headers"); !strings.Contains(got, "Authorization") {
		t.Fatalf("allow-headers %q missing Authorization", got)
	}
}

func TestAPIRootAndHealth(t *testing.T) {
	srv, _, dataDir := newTestServer(t, "tok")

	_, body, _ := do(t, http.MethodGet, srv.URL+"/api", "tok", nil)
	if body["ok"] != true || body["service"] != "yoloit-hub" {
		t.Fatalf("/api body: %v", body)
	}

	_, health, _ := do(t, http.MethodGet, srv.URL+"/api/health", "tok", nil)
	if health["ok"] != true || health["dataDir"] != dataDir {
		t.Fatalf("/api/health body: %v", health)
	}
	if watch, ok := health["watch"]; !ok || watch != false {
		t.Fatalf("/api/health missing watch=false: %v", health)
	}
}

func TestBoardCRUDHappyPath(t *testing.T) {
	srv, _, _ := newTestServer(t, "tok")

	// Create.
	resp, body, _ := do(t, http.MethodPost, srv.URL+"/api/boards", "tok", map[string]any{"name": "  My Board  "})
	if resp.StatusCode != http.StatusOK || body["ok"] != true {
		t.Fatalf("create: %d %v", resp.StatusCode, body)
	}
	created, _ := body["board"].(map[string]any)
	if created["name"] != "My Board" {
		t.Fatalf("name not trimmed: %v", created)
	}
	if created["active"] != true {
		t.Fatalf("created board should be active: %v", created)
	}
	id, _ := created["id"].(string)
	if !strings.HasPrefix(id, "board-") {
		t.Fatalf("unexpected board id %q", id)
	}

	// Get full board: Dart-compatible top-level shape (no ok wrapper).
	resp, full, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+id, "tok", nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("get board: %d", resp.StatusCode)
	}
	for _, key := range []string{"id", "name", "viewport", "panels", "links", "drawings", "metadata"} {
		if _, ok := full[key]; !ok {
			t.Fatalf("board json missing %q: %v", key, full)
		}
	}
	viewport, _ := full["viewport"].(map[string]any)
	if viewport["scale"] != 1.0 {
		t.Fatalf("default viewport: %v", viewport)
	}

	// List shows both the seeded default and the new board.
	_, list, _ := do(t, http.MethodGet, srv.URL+"/api/boards", "tok", nil)
	boards, _ := list["boards"].([]any)
	if len(boards) != 2 {
		t.Fatalf("list: %d boards, want 2", len(boards))
	}

	// Delete.
	resp, del, _ := do(t, http.MethodDelete, srv.URL+"/api/boards/"+id, "tok", nil)
	if resp.StatusCode != http.StatusOK || del["ok"] != true {
		t.Fatalf("delete: %d %v", resp.StatusCode, del)
	}
	if del["message"] != "Deleted board My Board" {
		t.Fatalf("delete message: %v", del)
	}
	resp, gone, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+id, "tok", nil)
	if resp.StatusCode != http.StatusNotFound || gone["error"] != "board not found" {
		t.Fatalf("get deleted: %d %v", resp.StatusCode, gone)
	}
}

func TestBoardsRootMethodNotAllowed(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	resp, body, _ := do(t, http.MethodPatch, srv.URL+"/api/boards", "", nil)
	if resp.StatusCode != http.StatusMethodNotAllowed || body["error"] != "method not allowed" {
		t.Fatalf("PATCH /api/boards: %d %v", resp.StatusCode, body)
	}
}

func TestPutBoardRevisionIncrementAndHistory(t *testing.T) {
	srv, _, dataDir := newTestServer(t, "tok")
	boardID := defaultBoardID(t, srv, "tok")

	putBody := map[string]any{
		"expectedRevision": 0,
		"panels": []any{
			map[string]any{
				"id":    "p-1",
				"type":  "board.note.markdown",
				"title": "Hello",
				"bounds": map[string]any{
					"x": 10.0, "y": 20.0, "width": 300.0, "height": 200.0,
				},
				"state": map[string]any{"markdown": "# hi"},
			},
		},
	}
	resp, body, raw := do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID, "tok", putBody)
	if resp.StatusCode != http.StatusOK || body["ok"] != true {
		t.Fatalf("put: %d %s", resp.StatusCode, raw)
	}
	updated, _ := body["board"].(map[string]any)
	metadata, _ := updated["metadata"].(map[string]any)
	if metadata["historyRevision"] != 1.0 {
		t.Fatalf("historyRevision: %v, want 1", metadata)
	}
	panels, _ := updated["panels"].([]any)
	if len(panels) != 1 {
		t.Fatalf("panels: %v", panels)
	}

	// History event file at boards_history/<id>/events/YYYY/MM/<op>_<actor>.json.
	now := time.Now().UTC()
	pattern := filepath.Join(
		dataDir, "boards_history", boardID, "events",
		fmt.Sprintf("%04d", now.Year()), fmt.Sprintf("%02d", int(now.Month())),
		"op-*_test-actor.json",
	)
	matches, err := filepath.Glob(pattern)
	if err != nil || len(matches) != 1 {
		t.Fatalf("history files matching %s: %v (err %v)", pattern, matches, err)
	}
	eventData, err := os.ReadFile(matches[0])
	if err != nil {
		t.Fatalf("read event: %v", err)
	}
	var event map[string]any
	if err := json.Unmarshal(eventData, &event); err != nil {
		t.Fatalf("parse event: %v", err)
	}
	if event["type"] != "panel.created" || event["entityType"] != "panel" || event["entityId"] != "p-1" {
		t.Fatalf("event identity: %v", event)
	}
	if event["actorId"] != "test-actor" || event["revision"] != 1.0 {
		t.Fatalf("event actor/revision: %v", event)
	}
	if event["after"] == nil || event["before"] != nil {
		t.Fatalf("panel.created event before/after: %v", event)
	}
	if _, ok := event["patch"]; !ok {
		t.Fatalf("event missing patch key: %v", event)
	}
}

func TestPutBoardStaleRevisionConflict(t *testing.T) {
	srv, _, _ := newTestServer(t, "tok")
	boardID := defaultBoardID(t, srv, "tok")

	// First write bumps the revision to 1 (an empty-panels PUT is a no-op and
	// would not increment the revision — same in yoloitd).
	_, _, _ = do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID, "tok", map[string]any{
		"panels": []any{
			map[string]any{"id": "p-0", "bounds": map[string]any{}},
		},
	})

	// Stale writer replays expectedRevision 0.
	resp, body, _ := do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID, "tok", map[string]any{
		"expectedRevision": 0,
		"panels": []any{
			map[string]any{"id": "p-x", "bounds": map[string]any{}},
		},
	})
	if resp.StatusCode != http.StatusConflict {
		t.Fatalf("stale put: %d, want 409", resp.StatusCode)
	}
	if body["ok"] != false || body["error"] != "board revision conflict" {
		t.Fatalf("409 envelope: %v", body)
	}
	if body["expectedRevision"] != 0.0 || body["currentRevision"] != 1.0 {
		t.Fatalf("409 revisions: %v", body)
	}
	conflictBoard, ok := body["board"].(map[string]any)
	if !ok || conflictBoard["id"] != boardID {
		t.Fatalf("409 must carry the authoritative board: %v", body)
	}
}

func TestPutBoardMetadataRevisionFallback(t *testing.T) {
	srv, _, _ := newTestServer(t, "tok")
	boardID := defaultBoardID(t, srv, "tok")

	// expectedRevision may also arrive as metadata.historyRevision.
	resp, body, _ := do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID, "tok", map[string]any{
		"metadata": map[string]any{"historyRevision": 5},
		"panels":   []any{},
	})
	if resp.StatusCode != http.StatusConflict {
		t.Fatalf("metadata revision conflict: %d %v", resp.StatusCode, body)
	}
}

func TestArchiveUnarchive(t *testing.T) {
	srv, _, _ := newTestServer(t, "tok")
	boardID := defaultBoardID(t, srv, "tok")

	resp, body, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/archive", "tok", nil)
	if resp.StatusCode != http.StatusOK || body["ok"] != true {
		t.Fatalf("archive: %d %v", resp.StatusCode, body)
	}
	if body["message"] != "Archived board Remote Board" {
		t.Fatalf("archive message: %v", body)
	}

	// Archived boards disappear from the default listing.
	_, list, _ := do(t, http.MethodGet, srv.URL+"/api/boards", "tok", nil)
	if boards, _ := list["boards"].([]any); len(boards) != 0 {
		t.Fatalf("archived board still listed: %v", list)
	}
	_, listAll, _ := do(t, http.MethodGet, srv.URL+"/api/boards?includeArchived=true", "tok", nil)
	if boards, _ := listAll["boards"].([]any); len(boards) != 1 {
		t.Fatalf("includeArchived: %v", listAll)
	}

	// Archiving is not an eventful mutation: no revision bump.
	_, full, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID, "tok", nil)
	metadata, _ := full["metadata"].(map[string]any)
	if metadata["archived"] != true {
		t.Fatalf("board not archived: %v", metadata)
	}
	if rev := metadata["historyRevision"]; rev != nil {
		t.Fatalf("archive should not bump historyRevision, got %v", rev)
	}

	resp, body, _ = do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/unarchive", "tok", nil)
	if resp.StatusCode != http.StatusOK || body["ok"] != true {
		t.Fatalf("unarchive: %d %v", resp.StatusCode, body)
	}
	_, list, _ = do(t, http.MethodGet, srv.URL+"/api/boards", "tok", nil)
	if boards, _ := list["boards"].([]any); len(boards) != 1 {
		t.Fatalf("unarchived board not listed: %v", list)
	}
}

func TestPanelTypes(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")

	resp, body, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID+"/panel-types", "", nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("panel-types: %d", resp.StatusCode)
	}
	types, _ := body["types"].([]any)
	if len(types) != len(panelTypeDescriptors) {
		t.Fatalf("types: %d, want %d", len(types), len(panelTypeDescriptors))
	}
	var terminal map[string]any
	for _, entry := range types {
		m, _ := entry.(map[string]any)
		if m["type"] == "board.terminal" {
			terminal = m
		}
	}
	if terminal == nil {
		t.Fatal("board.terminal descriptor missing")
	}
	caps, _ := terminal["capabilities"].(map[string]any)
	if caps["requiresNativeHost"] != true || caps["supportsHeadlessPreview"] != false {
		t.Fatalf("terminal capabilities: %v", caps)
	}
	local, _ := caps["localPlatforms"].([]any)
	if len(local) != 3 || local[0] != "macos" {
		t.Fatalf("terminal localPlatforms: %v", local)
	}
}

func TestBoardSnapshot(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")

	_, _, _ = do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID, "", map[string]any{
		"panels": []any{
			map[string]any{
				"id":     "p-1",
				"type":   "board.note.markdown",
				"title":  "Notes",
				"bounds": map[string]any{"x": 120.0, "y": 40.5, "width": 360.0, "height": 240.0},
			},
		},
	})

	resp, _, raw := do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID+"/snapshot", "", nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("snapshot: %d", resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); !strings.HasPrefix(ct, "text/plain") {
		t.Fatalf("snapshot content-type: %q", ct)
	}
	want := "# Remote Board\n\n" +
		"| Panel | Type | Position | Size |\n" +
		"|-------|------|----------|------|\n" +
		"| Notes | board.note.markdown | 120.0,40.5 | 360.0x240.0 |\n"
	if raw != want {
		t.Fatalf("snapshot body:\n%q\nwant:\n%q", raw, want)
	}
}

func TestCORSRestrictedOrigins(t *testing.T) {
	store := NewStore(t.TempDir(), "test-actor")
	if err := store.Init(); err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(newServer(store, "", "https://app.example.com", newRelayHub(t.TempDir())))
	defer srv.Close()

	req, _ := http.NewRequest(http.MethodGet, srv.URL+"/api/health", nil)
	req.Header.Set("Origin", "https://evil.example.com")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if got := resp.Header.Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("disallowed origin got %q", got)
	}

	req, _ = http.NewRequest(http.MethodGet, srv.URL+"/api/health", nil)
	req.Header.Set("Origin", "https://app.example.com")
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if got := resp.Header.Get("Access-Control-Allow-Origin"); got != "https://app.example.com" {
		t.Fatalf("allowed origin echoed %q", got)
	}
}
