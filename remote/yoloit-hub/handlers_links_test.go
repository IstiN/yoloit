package main

import (
	"net/http"
	"strings"
	"testing"
)

func TestLinksCRUD(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")
	a := createPanel(t, srv.URL, "", boardID, map[string]any{"title": "A"})
	b := createPanel(t, srv.URL, "", boardID, map[string]any{"title": "B"})

	// Create (titles resolve to panel ids, like Dart's _findPanel).
	resp, body, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/links", "", map[string]any{
		"from": "a", "to": "B", "color": "#93C5FD", "style": "dashed",
	})
	if resp.StatusCode != http.StatusOK || body["ok"] != true {
		t.Fatalf("create link: %d %v", resp.StatusCode, body)
	}
	link, _ := body["link"].(map[string]any)
	linkID, _ := link["id"].(string)
	if !strings.HasPrefix(linkID, "link-") {
		t.Fatalf("link id %q", linkID)
	}
	if link["fromPanelId"] != a["id"] || link["toPanelId"] != b["id"] || link["from"] != a["id"] || link["to"] != b["id"] {
		t.Fatalf("link endpoints: %v", link)
	}
	if link["color"] != "#93C5FD" || link["style"] != "dashed" {
		t.Fatalf("link color/style: %v", link)
	}

	// List: raw links, no ok wrapper.
	resp, list, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID+"/links", "", nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("list links: %d", resp.StatusCode)
	}
	links, _ := list["links"].([]any)
	if len(links) != 1 {
		t.Fatalf("links: %v", list)
	}

	// Update color/style.
	resp, upd, _ := do(t, http.MethodPut, srv.URL+"/api/boards/"+boardID+"/links/"+linkID, "", map[string]any{
		"color": "#FF0000",
	})
	if resp.StatusCode != http.StatusOK || upd["ok"] != true {
		t.Fatalf("update link: %d %v", resp.StatusCode, upd)
	}
	_, list, _ = do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID+"/links", "", nil)
	links, _ = list["links"].([]any)
	updated, _ := links[0].(map[string]any)
	if updated["color"] != "#FF0000" || updated["style"] != "dashed" {
		t.Fatalf("link after update: %v", updated)
	}

	// Link mutations are not eventful: no revision bump.
	_, full, _ := do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID, "", nil)
	metadata, _ := full["metadata"].(map[string]any)
	if metadata["historyRevision"] != 2.0 {
		t.Fatalf("link mutations must not bump revision (2 panel creates): %v", metadata)
	}

	// Delete.
	resp, del, _ := do(t, http.MethodDelete, srv.URL+"/api/boards/"+boardID+"/links/"+linkID, "", nil)
	if resp.StatusCode != http.StatusOK || del["ok"] != true || del["message"] != "Link deleted" {
		t.Fatalf("delete link: %d %v", resp.StatusCode, del)
	}
	_, list, _ = do(t, http.MethodGet, srv.URL+"/api/boards/"+boardID+"/links", "", nil)
	if links, _ := list["links"].([]any); len(links) != 0 {
		t.Fatalf("links after delete: %v", list)
	}
}

func TestLinkCreateValidation(t *testing.T) {
	srv, _, _ := newTestServer(t, "")
	boardID := defaultBoardID(t, srv, "")
	a := createPanel(t, srv.URL, "", boardID, map[string]any{"title": "A"})

	// Missing endpoints → 400.
	resp, body, _ := do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/links", "", map[string]any{"from": a["id"]})
	if resp.StatusCode != http.StatusBadRequest || body["error"] != "from and to required" {
		t.Fatalf("missing to: %d %v", resp.StatusCode, body)
	}

	// Unknown panel → 404.
	resp, body, _ = do(t, http.MethodPost, srv.URL+"/api/boards/"+boardID+"/links", "", map[string]any{
		"from": a["id"], "to": "ghost",
	})
	if resp.StatusCode != http.StatusNotFound || body["error"] != "panel not found" {
		t.Fatalf("unknown panel: %d %v", resp.StatusCode, body)
	}
}
