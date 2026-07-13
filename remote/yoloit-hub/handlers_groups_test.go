package main

import (
	"net/http"
	"strings"
	"testing"
)

func TestGroupsCRUDMembershipAndMove(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")
	a := createPanel(t, srv.URL, "", boardID, map[string]any{"title": "A", "x": 10.0, "y": 20.0})
	b := createPanel(t, srv.URL, "", boardID, map[string]any{"title": "B", "x": 30.0, "y": 40.0})

	// Create with initial membership (titles resolve to panel ids).
	resp, body, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/groups", "", map[string]any{
		"name": "Cluster", "panels": "A", "color": "#93C5FD",
	})
	if resp.StatusCode != http.StatusOK || body["ok"] != true {
		t.Fatalf("create group: %d %v", resp.StatusCode, body)
	}
	group, _ := body["group"].(map[string]any)
	groupID, _ := group["id"].(string)
	if !strings.HasPrefix(groupID, "g-") {
		t.Fatalf("group id %q", groupID)
	}
	panelIDs, _ := group["panelIds"].([]any)
	if len(panelIDs) != 1 || panelIDs[0] != a["id"] {
		t.Fatalf("group panelIds: %v", group)
	}
	if group["color"] != "#93C5FD" {
		t.Fatalf("group color: %v", group)
	}

	// List.
	_, list, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID+"/groups", "", nil)
	groups, _ := list["groups"].([]any)
	if list["ok"] != true || len(groups) != 1 {
		t.Fatalf("list groups: %v", list)
	}

	// Update: rename, collapse, clear color.
	resp, upd, _ := do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID+"/groups/"+groupID, "", map[string]any{
		"name": "Renamed", "collapsed": true, "color": "clear",
	})
	if resp.StatusCode != http.StatusOK || upd["ok"] != true {
		t.Fatalf("update group: %d %v", resp.StatusCode, upd)
	}
	updated, _ := upd["group"].(map[string]any)
	if updated["name"] != "Renamed" || updated["collapsed"] != true {
		t.Fatalf("updated group: %v", updated)
	}
	if _, hasColor := updated["color"]; hasColor {
		t.Fatalf("color should be removed: %v", updated)
	}

	// Add a second panel to the group.
	resp, add, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/groups/"+groupID+"/panels", "", map[string]any{
		"panels": []any{b["id"]},
	})
	if resp.StatusCode != http.StatusOK || add["message"] != "Panels added to group" {
		t.Fatalf("add panels: %d %v", resp.StatusCode, add)
	}
	_, list, _ = do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID+"/groups", "", nil)
	groups, _ = list["groups"].([]any)
	listed, _ := groups[0].(map[string]any)
	if ids, _ := listed["panelIds"].([]any); len(ids) != 2 {
		t.Fatalf("panelIds after add: %v", listed)
	}

	// Move shifts every member panel's bounds.
	resp, move, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/groups/"+groupID+"/move", "", map[string]any{
		"dx": 5.0, "dy": -5.0,
	})
	if resp.StatusCode != http.StatusOK || move["message"] != "Group moved" {
		t.Fatalf("move: %d %v", resp.StatusCode, move)
	}
	panels := getBoardPanels(t, srv.URL, "", boardID)
	positions := map[string]map[string]any{}
	for _, entry := range panels {
		p, _ := entry.(map[string]any)
		positions[p["id"].(string)], _ = p["bounds"].(map[string]any)
	}
	if positions[a["id"].(string)]["x"] != 15.0 || positions[a["id"].(string)]["y"] != 15.0 {
		t.Fatalf("panel A moved: %v", positions[a["id"].(string)])
	}
	if positions[b["id"].(string)]["x"] != 35.0 || positions[b["id"].(string)]["y"] != 35.0 {
		t.Fatalf("panel B moved: %v", positions[b["id"].(string)])
	}

	// Remove a member (ids in the body, like Dart).
	resp, rem, _ := do(t, http.MethodDelete, srv.URL+"/api/boards/"+boardID+"/groups/"+groupID+"/panels", "", map[string]any{
		"panels": []any{b["id"]},
	})
	if resp.StatusCode != http.StatusOK || rem["message"] != "Panels removed from group" {
		t.Fatalf("remove panels: %d %v", resp.StatusCode, rem)
	}
	_, list, _ = do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID+"/groups", "", nil)
	groups, _ = list["groups"].([]any)
	listed, _ = groups[0].(map[string]any)
	if ids, _ := listed["panelIds"].([]any); len(ids) != 1 || ids[0] != a["id"] {
		t.Fatalf("panelIds after remove: %v", listed)
	}

	// Group mutations are not eventful: revision only reflects the 2 panel
	// creates (group move does not bump it either, matching Dart).
	_, full, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID, "", nil)
	metadata, _ := full["metadata"].(map[string]any)
	if metadata["historyRevision"] != 2.0 {
		t.Fatalf("group mutations must not bump revision: %v", metadata)
	}

	// Delete.
	resp, del, _ := do(t, http.MethodDelete, srv.URL+"/api/boards/"+boardID+"/groups/"+groupID, "", nil)
	if resp.StatusCode != http.StatusOK || del["ok"] != true || del["message"] != "Group deleted" {
		t.Fatalf("delete group: %d %v", resp.StatusCode, del)
	}
	_, list, _ = do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID+"/groups", "", nil)
	if groups, _ := list["groups"].([]any); len(groups) != 0 {
		t.Fatalf("groups after delete: %v", list)
	}
}

func TestGroupValidation(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")

	// Name required.
	resp, body, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/groups", "", map[string]any{"name": "  "})
	if resp.StatusCode != http.StatusBadRequest || body["error"] != "name required" {
		t.Fatalf("missing name: %d %v", resp.StatusCode, body)
	}

	// Unknown group → 404.
	resp, body, _ = do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID+"/groups/g-ghost", "", map[string]any{"name": "X"})
	if resp.StatusCode != http.StatusNotFound || body["error"] != "group not found" {
		t.Fatalf("unknown group: %d %v", resp.StatusCode, body)
	}
}
