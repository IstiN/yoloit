package main

import (
	"net/http"
	"testing"
)

func getHistory(t *testing.T, srvURL, token, boardID string) []any {
	t.Helper()
	resp, body, _ := do(t, http.MethodGet, srvURL+"/api/boards/"+boardID+"/history", token, nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("history: %d", resp.StatusCode)
	}
	events, _ := body["events"].([]any)
	return events
}

func TestHistoryShapeAndOrdering(t *testing.T) {
	srv, _, _ := newTestServer(t, "tok")
	boardID := defaultBoardID(t, srv, "tok")
	panel := createPanel(t, srv.URL, "tok", boardID, map[string]any{"title": "First"})
	id := panel["id"].(string)
	_, _, _ = do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID+"/panels/"+id, "tok", map[string]any{"title": "Second"})

	events := getHistory(t, srv.URL, "tok", boardID)
	if len(events) != 2 {
		t.Fatalf("events: %d, want 2", len(events))
	}
	created, _ := events[0].(map[string]any)
	updated, _ := events[1].(map[string]any)
	if created["type"] != "panel.created" || updated["type"] != "panel.updated" {
		t.Fatalf("event types: %v / %v", created["type"], updated["type"])
	}
	// Sorted by (revision, opId).
	if created["revision"] != 1.0 || updated["revision"] != 2.0 {
		t.Fatalf("revisions: %v / %v", created["revision"], updated["revision"])
	}
	// Full RemoteHistoryEvent key set, nulls included (Dart toJson shape).
	for _, key := range []string{"opId", "boardId", "type", "entityType", "entityId", "actorId", "timestamp", "revision", "before", "after", "patch", "restoresOpId"} {
		if _, ok := created[key]; !ok {
			t.Fatalf("event missing key %q: %v", key, created)
		}
	}
	if created["actorId"] != "test-actor" || created["entityType"] != "panel" || created["entityId"] != id {
		t.Fatalf("event identity: %v", created)
	}
	if created["before"] != nil || created["after"] == nil || created["restoresOpId"] != nil {
		t.Fatalf("panel.created before/after/restoresOpId: %v", created)
	}
	// panel.updated carries a field-level patch.
	patch, _ := updated["patch"].(map[string]any)
	titlePatch, _ := patch["title"].(map[string]any)
	if titlePatch["before"] != "First" || titlePatch["after"] != "Second" {
		t.Fatalf("patch.title: %v", patch)
	}
}

func TestUndoRedoRoundTrip(t *testing.T) {
	srv, _, _ := newTestServer(t, "tok")
	boardID := defaultBoardID(t, srv, "tok")
	panel := createPanel(t, srv.URL, "tok", boardID, map[string]any{"title": "Original"})
	id := panel["id"].(string)
	_, _, _ = do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID+"/panels/"+id, "tok", map[string]any{"title": "Edited"})

	// Undo reverts the panel.updated event to its before snapshot.
	resp, body, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/undo", "tok", nil)
	if resp.StatusCode != http.StatusOK || body["ok"] != true || body["undone"] != true {
		t.Fatalf("undo: %d %v", resp.StatusCode, body)
	}
	if body["redoDepth"] != 1.0 || body["message"] != "Undid latest panel change" {
		t.Fatalf("undo envelope: %v", body)
	}
	if summary, _ := body["board"].(map[string]any); summary["id"] != boardID {
		t.Fatalf("undo board summary: %v", body)
	}
	panels := getBoardPanels(t, srv.URL, "tok", boardID)
	restored, _ := panels[0].(map[string]any)
	if restored["title"] != "Original" {
		t.Fatalf("title after undo: %v", restored["title"])
	}

	// The undo recorded a panel.restored event pointing at the undone op.
	events := getHistory(t, srv.URL, "tok", boardID)
	last, _ := events[len(events)-1].(map[string]any)
	if last["type"] != "panel.restored" || last["restoresOpId"] == nil {
		t.Fatalf("restore event: %v", last)
	}
	undone, _ := events[len(events)-2].(map[string]any)
	if last["restoresOpId"] != undone["opId"] {
		t.Fatalf("restoresOpId %v, want %v", last["restoresOpId"], undone["opId"])
	}

	// Redo replays the edit.
	resp, body, _ = do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/redo", "tok", nil)
	if resp.StatusCode != http.StatusOK || body["ok"] != true || body["redone"] != true {
		t.Fatalf("redo: %d %v", resp.StatusCode, body)
	}
	if body["redoDepth"] != 0.0 || body["message"] != "Redid latest undone panel change" {
		t.Fatalf("redo envelope: %v", body)
	}
	panels = getBoardPanels(t, srv.URL, "tok", boardID)
	redone, _ := panels[0].(map[string]any)
	if redone["title"] != "Edited" {
		t.Fatalf("title after redo: %v", redone["title"])
	}

	// Nothing left to redo.
	_, body, _ = do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/redo", "tok", nil)
	if body["ok"] != false || body["message"] != "No redoable panel history yet" {
		t.Fatalf("empty redo: %v", body)
	}
}

func TestRedoStackClearedOnNewMutation(t *testing.T) {
	srv, _, _ := newTestServer(t, "tok")
	boardID := defaultBoardID(t, srv, "tok")
	panel := createPanel(t, srv.URL, "tok", boardID, map[string]any{"title": "A"})
	id := panel["id"].(string)
	_, _, _ = do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID+"/panels/"+id, "tok", map[string]any{"title": "B"})

	_, body, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/undo", "tok", nil)
	if body["redoDepth"] != 1.0 {
		t.Fatalf("redoDepth after undo: %v", body)
	}

	// A fresh eventful mutation clears the redo stack (Dart's appendHistory).
	_, _, _ = do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID+"/panels/"+id, "tok", map[string]any{"title": "C"})

	_, body, _ = do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/redo", "tok", nil)
	if body["ok"] != false || body["redone"] != false || body["redoDepth"] != 0.0 {
		t.Fatalf("redo after new edit: %v", body)
	}
}

func TestUndoOfCreateRemovesPanel(t *testing.T) {
	srv, _, _ := newTestServer(t, "tok")
	boardID := defaultBoardID(t, srv, "tok")
	panel := createPanel(t, srv.URL, "tok", boardID, map[string]any{"title": "Temp"})
	id := panel["id"].(string)

	_, body, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/undo", "tok", nil)
	if body["undone"] != true {
		t.Fatalf("undo create: %v", body)
	}
	if panels := getBoardPanels(t, srv.URL, "tok", boardID); len(panels) != 0 {
		t.Fatalf("panel survived create-undo: %v", panels)
	}
	// Create-undo is silent: no new history event, no revision bump.
	if events := getHistory(t, srv.URL, "tok", boardID); len(events) != 1 {
		t.Fatalf("events after silent undo: %d", len(events))
	}
	_, full, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID, "tok", nil)
	metadata, _ := full["metadata"].(map[string]any)
	if metadata["historyRevision"] != 1.0 {
		t.Fatalf("silent undo bumped revision: %v", metadata)
	}

	// Redo recreates the panel with its snapshot.
	_, body, _ = do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/redo", "tok", nil)
	if body["redone"] != true {
		t.Fatalf("redo create: %v", body)
	}
	panels := getBoardPanels(t, srv.URL, "tok", boardID)
	if len(panels) != 1 {
		t.Fatalf("panels after redo: %d", len(panels))
	}
	restored, _ := panels[0].(map[string]any)
	if restored["id"] != id || restored["title"] != "Temp" {
		t.Fatalf("recreated panel: %v", restored)
	}
}

func TestUndoWithNoHistory(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")
	resp, body, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/undo", "", nil)
	if resp.StatusCode != http.StatusOK || body["ok"] != false || body["undone"] != false {
		t.Fatalf("undo empty: %d %v", resp.StatusCode, body)
	}
	if body["message"] != "No restorable panel history yet" || body["redoDepth"] != 0.0 {
		t.Fatalf("undo empty envelope: %v", body)
	}
}
