package main

import (
	"net/http"
	"strings"
	"testing"
)

// createPanel is a small helper for the panel tests.
func createPanel(t *testing.T, srvURL, token, boardID string, body map[string]any) map[string]any {
	t.Helper()
	resp, parsed, raw := do(t, http.MethodPost, srvURL+"/api/boards/"+boardID+"/panels", token, body)
	if resp.StatusCode != http.StatusOK || parsed["ok"] != true {
		t.Fatalf("create panel: %d %s", resp.StatusCode, raw)
	}
	panel, _ := parsed["panel"].(map[string]any)
	if panel == nil {
		t.Fatalf("create panel response missing panel: %v", parsed)
	}
	return panel
}

func getBoardPanels(t *testing.T, srvURL, token, boardID string) []any {
	t.Helper()
	_, full, _ := do(t, http.MethodGet, srvURL+"/api/boards/"+boardID, token, nil)
	panels, _ := full["panels"].([]any)
	return panels
}

func TestPanelCreateAndList(t *testing.T) {
	srv, _, _ := newTestServer(t, "tok")
	boardID := defaultBoardID(t, srv, "tok")

	panel := createPanel(t, srv.URL, "tok", boardID, map[string]any{
		"type":  "board.note.markdown",
		"title": "Notes",
		"state": map[string]any{"markdown": "# hi"},
	})
	id, _ := panel["id"].(string)
	if !strings.HasPrefix(id, "p-") {
		t.Fatalf("panel id %q, want p- prefix", id)
	}
	if panel["zIndex"] != 1.0 {
		t.Fatalf("first panel zIndex: %v, want 1", panel["zIndex"])
	}
	bounds, _ := panel["bounds"].(map[string]any)
	if bounds["x"] != 120.0 || bounds["width"] != 360.0 {
		t.Fatalf("default bounds: %v", bounds)
	}

	// Second panel gets zIndex 2 (addPanel's maxZ+1 rule).
	second := createPanel(t, srv.URL, "tok", boardID, map[string]any{"title": "Second"})
	if second["zIndex"] != 2.0 {
		t.Fatalf("second panel zIndex: %v, want 2", second["zIndex"])
	}

	// List endpoint: summaries carry typeName and content (raw state).
	resp, list, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID+"/panels", "tok", nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("list panels: %d", resp.StatusCode)
	}
	panels, _ := list["panels"].([]any)
	if len(panels) != 2 {
		t.Fatalf("panels: %d, want 2", len(panels))
	}
	first, _ := panels[0].(map[string]any)
	if first["typeName"] != "board.note.markdown" {
		t.Fatalf("typeName: %v", first)
	}
	content, _ := first["content"].(map[string]any)
	if content["markdown"] != "# hi" {
		t.Fatalf("content: %v", content)
	}
}

func TestPanelGetEnrichment(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")
	panel := createPanel(t, srv.URL, "", boardID, map[string]any{"type": "board.checklist", "title": "Todo"})
	id := panel["id"].(string)

	resp, body, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID+"/panels/"+id, "", nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("get panel: %d", resp.StatusCode)
	}
	actions, _ := body["supportedActions"].([]any)
	want := []string{"items", "add", "check", "uncheck", "remove", "rename"}
	if len(actions) != len(want) {
		t.Fatalf("supportedActions: %v", actions)
	}
	for i, w := range want {
		if actions[i] != w {
			t.Fatalf("supportedActions[%d]: %v, want %q", i, actions[i], w)
		}
	}
	help, _ := body["actionHelp"].(map[string]any)
	if help == nil {
		t.Fatalf("actionHelp missing: %v", body)
	}
	caps, _ := help["capabilities"].(map[string]any)
	if caps["requiresNativeHost"] != false || caps["supportsHeadlessPreview"] != true {
		t.Fatalf("capabilities: %v", caps)
	}
	if body["typeName"] != "board.checklist" {
		t.Fatalf("typeName: %v", body["typeName"])
	}

	// Unknown panel type falls back to ['get', 'set'] and no capabilities.
	unknown := createPanel(t, srv.URL, "", boardID, map[string]any{"type": "board.custom.thing", "title": "X"})
	_, body2, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID+"/panels/"+unknown["id"].(string), "", nil)
	actions2, _ := body2["supportedActions"].([]any)
	if len(actions2) != 2 || actions2[0] != "get" || actions2[1] != "set" {
		t.Fatalf("fallback supportedActions: %v", actions2)
	}
	help2, _ := body2["actionHelp"].(map[string]any)
	if _, hasCaps := help2["capabilities"]; hasCaps {
		t.Fatalf("unknown type should have no capabilities: %v", help2)
	}
}

func TestPanelGetNotFound(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")
	resp, body, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID+"/panels/nope", "", nil)
	if resp.StatusCode != http.StatusNotFound || body["error"] != "panel not found" {
		t.Fatalf("missing panel: %d %v", resp.StatusCode, body)
	}
}

func TestPanelUpdateAndNoOpRevision(t *testing.T) {
	srv, _, _ := newTestServer(t, "tok")
	boardID := defaultBoardID(t, srv, "tok")
	panel := createPanel(t, srv.URL, "tok", boardID, map[string]any{"title": "Before", "state": map[string]any{"markdown": "a"}})
	id := panel["id"].(string)

	resp, body, _ := do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID+"/panels/"+id, "tok", map[string]any{
		"title":  "After",
		"x":      200.0,
		"hidden": true,
		"state":  map[string]any{"markdown": "b"},
	})
	if resp.StatusCode != http.StatusOK || body["ok"] != true {
		t.Fatalf("put panel: %d %v", resp.StatusCode, body)
	}
	updated, _ := body["panel"].(map[string]any)
	if updated["title"] != "After" || updated["hidden"] != true {
		t.Fatalf("updated panel: %v", updated)
	}
	bounds, _ := updated["bounds"].(map[string]any)
	if bounds["x"] != 200.0 || bounds["y"] != 120.0 {
		t.Fatalf("bounds copyWith: %v", bounds)
	}
	state, _ := updated["state"].(map[string]any)
	if state["markdown"] != "b" {
		t.Fatalf("state replaced: %v", state)
	}

	// The update bumped the board revision to 2 (create = 1).
	_, full, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID, "tok", nil)
	metadata, _ := full["metadata"].(map[string]any)
	if metadata["historyRevision"] != 2.0 {
		t.Fatalf("historyRevision after update: %v", metadata)
	}

	// A no-op PUT (same JSON) must not bump the revision.
	_, _, _ = do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID+"/panels/"+id, "tok", map[string]any{
		"title":  "After",
		"x":      200.0,
		"hidden": true,
		"state":  map[string]any{"markdown": "b"},
	})
	_, full, _ = do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID, "tok", nil)
	metadata, _ = full["metadata"].(map[string]any)
	if metadata["historyRevision"] != 2.0 {
		t.Fatalf("no-op PUT bumped revision: %v", metadata)
	}
}

func TestPanelColorQuirk(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")
	panel := createPanel(t, srv.URL, "", boardID, map[string]any{"title": "Colorful"})
	id := panel["id"].(string)

	// '#hex' colors parse as base-16 ints.
	_, body, _ := do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID+"/panels/"+id, "", map[string]any{"color": "#FF0000"})
	updated, _ := body["panel"].(map[string]any)
	if updated["color"] != 16711680.0 {
		t.Fatalf("parsed color: %v", updated["color"])
	}

	// Mirrored Dart quirk: a PUT without the color key CLEARS the color
	// (copyWith(color: _parseColorValue(nil)) → null).
	_, body, _ = do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID+"/panels/"+id, "", map[string]any{"title": "Still Colorful"})
	updated, _ = body["panel"].(map[string]any)
	if color, present := updated["color"]; !present || color != nil {
		t.Fatalf("color should be cleared to null: %v", updated)
	}
}

func TestPanelDeleteRemovesLinks(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")
	a := createPanel(t, srv.URL, "", boardID, map[string]any{"title": "A"})
	b := createPanel(t, srv.URL, "", boardID, map[string]any{"title": "B"})
	_, _, _ = do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/links", "", map[string]any{
		"from": a["id"], "to": b["id"],
	})

	resp, body, _ := do(t, http.MethodDelete, srv.URL+"/api/boards/"+boardID+"/panels/"+a["id"].(string), "", nil)
	if resp.StatusCode != http.StatusOK || body["ok"] != true {
		t.Fatalf("delete panel: %d %v", resp.StatusCode, body)
	}
	if panels := getBoardPanels(t, srv.URL, "", boardID); len(panels) != 1 {
		t.Fatalf("panels after delete: %d", len(panels))
	}
	_, full, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID, "", nil)
	if links, _ := full["links"].([]any); len(links) != 0 {
		t.Fatalf("link referencing deleted panel survived: %v", links)
	}

	// Deleting a missing panel reports ok:false (Dart shape).
	resp, body, _ = do(t, http.MethodDelete, srv.URL+"/api/boards/"+boardID+"/panels/"+a["id"].(string), "", nil)
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("delete gone panel: %d %v (Dart 404s at lookup)", resp.StatusCode, body)
	}
}

func TestPanelActionChecklistStateOnly(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")
	panel := createPanel(t, srv.URL, "", boardID, map[string]any{"type": "board.checklist", "title": "Todo"})
	id := panel["id"].(string)

	// add → stateUpdate + updated panel in the response.
	resp, body, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/panels/"+id+"/action", "", map[string]any{
		"action": "add", "text": "write tests",
	})
	if resp.StatusCode != http.StatusOK || body["ok"] != true {
		t.Fatalf("add: %d %v", resp.StatusCode, body)
	}
	stateUpdate, _ := body["stateUpdate"].(map[string]any)
	items, _ := stateUpdate["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("items: %v", stateUpdate)
	}
	item, _ := items[0].(map[string]any)
	if item["text"] != "write tests" || item["done"] != false {
		t.Fatalf("item: %v", item)
	}
	updated, _ := body["panel"].(map[string]any)
	if updated == nil {
		t.Fatalf("state-mutating action must return the panel: %v", body)
	}

	// check by index → done:true.
	resp, body, _ = do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/panels/"+id+"/action", "", map[string]any{
		"action": "check", "index": 0,
	})
	if resp.StatusCode != http.StatusOK || body["ok"] != true {
		t.Fatalf("check: %d %v", resp.StatusCode, body)
	}
	stateUpdate, _ = body["stateUpdate"].(map[string]any)
	items, _ = stateUpdate["items"].([]any)
	item, _ = items[0].(map[string]any)
	if item["done"] != true {
		t.Fatalf("item not checked: %v", item)
	}

	// 'items' is data-only: response carries data + content, no stateUpdate.
	resp, body, _ = do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/panels/"+id+"/action", "", map[string]any{
		"action": "items",
	})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("items: %d", resp.StatusCode)
	}
	if _, hasUpdate := body["stateUpdate"]; hasUpdate {
		t.Fatalf("data-only action must not carry stateUpdate: %v", body)
	}
	data, _ := body["data"].(map[string]any)
	if dataItems, _ := data["items"].([]any); len(dataItems) != 1 {
		t.Fatalf("data.items: %v", data)
	}
	if body["content"] == nil {
		t.Fatalf("content key missing: %v", body)
	}
}

func TestPanelActionGetContent(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")
	panel := createPanel(t, srv.URL, "", boardID, map[string]any{
		"type":  "board.note.markdown",
		"title": "Notes",
		"state": map[string]any{"markdown": "# hello"},
	})
	id := panel["id"].(string)

	resp, body, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/panels/"+id+"/action", "", map[string]any{
		"action": "get",
	})
	if resp.StatusCode != http.StatusOK || body["ok"] != true {
		t.Fatalf("get: %d %v", resp.StatusCode, body)
	}
	data, _ := body["data"].(map[string]any)
	if data["markdown"] != "# hello" || data["autoHeight"] != false {
		t.Fatalf("note content view: %v", data)
	}
	content, _ := body["content"].(map[string]any)
	if content["markdown"] != "# hello" {
		t.Fatalf("content mirrors data for get: %v", content)
	}
}

func TestPanelActionErrors(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")
	note := createPanel(t, srv.URL, "", boardID, map[string]any{"type": "board.note.markdown", "title": "N"})

	// Missing argument → 400 with Dart's _missing shape.
	resp, body, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/panels/"+note["id"].(string)+"/action", "", map[string]any{
		"action": "set",
	})
	if resp.StatusCode != http.StatusBadRequest || body["ok"] != false {
		t.Fatalf("missing arg: %d %v", resp.StatusCode, body)
	}
	if body["message"] != "Missing \"text or markdown\"" {
		t.Fatalf("missing message: %v", body)
	}

	// Unknown action → 400 with Dart's _unknown shape.
	resp, body, _ = do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/panels/"+note["id"].(string)+"/action", "", map[string]any{
		"action": "explode",
	})
	if resp.StatusCode != http.StatusBadRequest || body["message"] != "Unknown action: explode" {
		t.Fatalf("unknown action: %d %v", resp.StatusCode, body)
	}

	// board.ui actions are unsupported in yoloit-hub (need UiViewBindings) —
	// same envelope Dart uses for unsupported actions.
	ui := createPanel(t, srv.URL, "", boardID, map[string]any{"type": "board.ui", "title": "UI"})
	resp, body, _ = do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/panels/"+ui["id"].(string)+"/action", "", map[string]any{
		"action": "render", "tree": map[string]any{},
	})
	if resp.StatusCode != http.StatusBadRequest || body["message"] != "Unknown action: render" {
		t.Fatalf("board.ui action: %d %v", resp.StatusCode, body)
	}
}

func TestPanelActionTimerTransitions(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")
	panel := createPanel(t, srv.URL, "", boardID, map[string]any{"type": "board.timer", "title": "T"})
	id := panel["id"].(string)

	// set with a duration → remaining mirrors duration, flags cleared.
	_, body, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/panels/"+id+"/action", "", map[string]any{
		"action": "set", "duration": 60,
	})
	stateUpdate, _ := body["stateUpdate"].(map[string]any)
	if stateUpdate["duration"] != 60.0 || stateUpdate["remaining"] != 60.0 || stateUpdate["isRunning"] != false {
		t.Fatalf("timer set: %v", stateUpdate)
	}

	// start → running with lastTick.
	_, body, _ = do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/panels/"+id+"/action", "", map[string]any{
		"action": "start",
	})
	stateUpdate, _ = body["stateUpdate"].(map[string]any)
	if stateUpdate["isRunning"] != true || stateUpdate["lastTick"] == nil {
		t.Fatalf("timer start: %v", stateUpdate)
	}

	// pause → not running, paused.
	_, body, _ = do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/panels/"+id+"/action", "", map[string]any{
		"action": "pause",
	})
	stateUpdate, _ = body["stateUpdate"].(map[string]any)
	if stateUpdate["isRunning"] != false || stateUpdate["isPaused"] != true {
		t.Fatalf("timer pause: %v", stateUpdate)
	}

	// status is data-only and reflects the persisted state.
	_, body, _ = do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/panels/"+id+"/action", "", map[string]any{
		"action": "status",
	})
	data, _ := body["data"].(map[string]any)
	if data["duration"] != 60.0 || data["isPaused"] != true {
		t.Fatalf("timer status: %v", data)
	}
}

func TestPanelsRootMethodNotAllowed(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")
	resp, body, _ := do(t, http.MethodPatch, srv.URL+"/api/boards/"+boardID+"/panels", "", nil)
	if resp.StatusCode != http.StatusMethodNotAllowed || body["error"] != "method not allowed" {
		t.Fatalf("PATCH panels: %d %v", resp.StatusCode, body)
	}
}
