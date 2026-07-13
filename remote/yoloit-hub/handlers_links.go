package main

// Link endpoints, mirroring the links branches of YoloitdServer._handleBoards.
// Links live in the board's `links` list and are mutated without a history
// event (no revision bump), exactly like yoloitd. Note: yoloitd has no
// GET /api/boards/:id/links/:link route — only list, create, update, delete.

import (
	"net/http"
	"strings"
)

// handleLinksList serves GET /api/boards/{id}/links: the raw links list with
// no `ok` wrapper.
func (s *server) handleLinksList(w http.ResponseWriter, board *RemoteBoard) {
	writeJSON(w, http.StatusOK, map[string]any{"links": board.Links})
}

// handleLinkCreate serves POST /api/boards/{id}/links.
func (s *server) handleLinkCreate(w http.ResponseWriter, r *http.Request, board *RemoteBoard) {
	body, err := readJSONBody(r)
	if err != nil {
		fail(w, err)
		return
	}
	fromID := trimString(body["from"])
	toID := trimString(body["to"])
	if fromID == "" || toID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"ok":    false,
			"error": "from and to required",
		})
		return
	}
	fromPanel := findPanel(board, fromID)
	toPanel := findPanel(board, toID)
	if fromPanel == nil || toPanel == nil {
		writeJSON(w, http.StatusNotFound, map[string]any{
			"ok":    false,
			"error": "panel not found",
		})
		return
	}
	link := map[string]any{
		"id":          nextID("link"),
		"fromPanelId": fromPanel.ID,
		"toPanelId":   toPanel.ID,
		"from":        fromPanel.ID,
		"to":          toPanel.ID,
	}
	if body["color"] != nil {
		link["color"] = body["color"]
	}
	if body["style"] != nil {
		link["style"] = body["style"]
	}
	_, after, err := s.store.UpdateBoard(board.ID, func(current *RemoteBoard) {
		links := make([]map[string]any, 0, len(current.Links)+1)
		links = append(links, current.Links...)
		links = append(links, link)
		current.Links = links
	}, nil)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":   after != nil,
		"link": link,
	})
}

// handleLinkDelete serves DELETE /api/boards/{id}/links/{link}.
func (s *server) handleLinkDelete(w http.ResponseWriter, board *RemoteBoard, linkID string) {
	_, after, err := s.store.UpdateBoard(board.ID, func(current *RemoteBoard) {
		links := make([]map[string]any, 0, len(current.Links))
		for _, link := range current.Links {
			if linkIDMatches(link, linkID) {
				continue
			}
			links = append(links, link)
		}
		current.Links = links
	}, nil)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":      after != nil,
		"message": "Link deleted",
	})
}

// handleLinkUpdate serves PUT /api/boards/{id}/links/{link}: color/style
// updates on the matching link.
func (s *server) handleLinkUpdate(w http.ResponseWriter, r *http.Request, board *RemoteBoard, linkID string) {
	body, err := readJSONBody(r)
	if err != nil {
		fail(w, err)
		return
	}
	_, after, err := s.store.UpdateBoard(board.ID, func(current *RemoteBoard) {
		links := make([]map[string]any, 0, len(current.Links))
		for _, link := range current.Links {
			if !linkIDMatches(link, linkID) {
				links = append(links, link)
				continue
			}
			next := make(map[string]any, len(link)+2)
			for key, value := range link {
				next[key] = value
			}
			if body["color"] != nil {
				next["color"] = body["color"]
			}
			if body["style"] != nil {
				next["style"] = body["style"]
			}
			links = append(links, next)
		}
		current.Links = links
	}, nil)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": after != nil})
}

// linkIDMatches mirrors Dart's `link['id'] == linkId` for string ids.
func linkIDMatches(link map[string]any, linkID string) bool {
	id, ok := link["id"].(string)
	return ok && id == linkID
}

// trimString mirrors `(body[k] as String? ?? ”).trim()`.
func trimString(value any) string {
	text, _ := value.(string)
	return strings.TrimSpace(text)
}
