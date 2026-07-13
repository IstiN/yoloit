package main

// Group endpoints, mirroring YoloitdServer._handleGroups. Groups live in
// board.metadata['groups'] and are mutated without a history event (no
// revision bump). Panel membership changes arrive in the request body
// (POST/DELETE .../panels with a `panels` argument) — yoloitd has no
// DELETE .../groups/:g/panels/:p path variant.

import (
	"net/http"
	"strings"
)

// handleGroups serves /api/boards/{id}/groups[/{group}[/{panels|move}]].
func (s *server) handleGroups(w http.ResponseWriter, r *http.Request, board *RemoteBoard, sub []string) {
	groups := boardGroups(board)

	if len(sub) == 0 {
		switch r.Method {
		case http.MethodGet:
			writeJSON(w, http.StatusOK, map[string]any{"ok": true, "groups": groups})
		case http.MethodPost:
			s.handleGroupCreate(w, r, board, groups)
		default:
			notFound(w)
		}
		return
	}

	groupID := sub[0]
	index := -1
	for i, group := range groups {
		if id, _ := group["id"].(string); id == groupID {
			index = i
			break
		}
	}
	if index < 0 {
		writeJSON(w, http.StatusNotFound, map[string]any{
			"ok":    false,
			"error": "group not found",
		})
		return
	}

	switch {
	case len(sub) == 1 && r.Method == http.MethodDelete:
		groups = append(groups[:index], groups[index+1:]...)
		s.saveGroups(w, board, groups, map[string]any{"ok": true, "message": "Group deleted"})
	case len(sub) == 1 && r.Method == http.MethodPut:
		s.handleGroupUpdate(w, r, board, groups, index)
	case len(sub) == 2 && sub[1] == "panels" && r.Method == http.MethodPost:
		s.handleGroupPanelsAdd(w, r, board, groups, index)
	case len(sub) == 2 && sub[1] == "panels" && r.Method == http.MethodDelete:
		s.handleGroupPanelsRemove(w, r, board, groups, index)
	case len(sub) == 2 && sub[1] == "move" && r.Method == http.MethodPost:
		s.handleGroupMove(w, r, board, groups, index)
	default:
		notFound(w)
	}
}

func (s *server) handleGroupCreate(w http.ResponseWriter, r *http.Request, board *RemoteBoard, groups []map[string]any) {
	body, err := readJSONBody(r)
	if err != nil {
		fail(w, err)
		return
	}
	name := trimString(body["name"])
	if name == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"ok":    false,
			"error": "name required",
		})
		return
	}
	group := map[string]any{
		"id":       nextID("g"),
		"name":     name,
		"panelIds": parsePanelIDs(board, body["panels"]),
	}
	if color := body["color"]; color != nil && color != "clear" {
		group["color"] = color
	}
	groups = append(groups, group)
	s.saveGroups(w, board, groups, map[string]any{"ok": true, "group": group})
}

// handleGroupUpdate mirrors the PUT branch: name (string), color (null or
// 'clear' removes it), collapsed (bool).
func (s *server) handleGroupUpdate(w http.ResponseWriter, r *http.Request, board *RemoteBoard, groups []map[string]any, index int) {
	body, err := readJSONBody(r)
	if err != nil {
		fail(w, err)
		return
	}
	group := copyMap(groups[index])
	if name, ok := body["name"].(string); ok {
		group["name"] = name
	}
	if color, present := body["color"]; present {
		if color == nil || color == "clear" {
			delete(group, "color")
		} else {
			group["color"] = color
		}
	}
	if collapsed, ok := body["collapsed"].(bool); ok {
		group["collapsed"] = collapsed
	}
	groups[index] = group
	s.saveGroups(w, board, groups, map[string]any{"ok": true, "group": group})
}

// handleGroupPanelsAdd mirrors POST .../panels: union of existing and new
// panel ids, preserving insertion order.
func (s *server) handleGroupPanelsAdd(w http.ResponseWriter, r *http.Request, board *RemoteBoard, groups []map[string]any, index int) {
	body, err := readJSONBody(r)
	if err != nil {
		fail(w, err)
		return
	}
	ids := parsePanelIDs(board, body["panels"])
	group := copyMap(groups[index])
	panelIDs := stringList(group["panelIds"])
	for _, id := range ids {
		if !stringContains(panelIDs, id) {
			panelIDs = append(panelIDs, id)
		}
	}
	group["panelIds"] = panelIDs
	groups[index] = group
	s.saveGroups(w, board, groups, map[string]any{"ok": true, "message": "Panels added to group"})
}

// handleGroupPanelsRemove mirrors DELETE .../panels (ids in the body).
func (s *server) handleGroupPanelsRemove(w http.ResponseWriter, r *http.Request, board *RemoteBoard, groups []map[string]any, index int) {
	body, err := readJSONBody(r)
	if err != nil {
		fail(w, err)
		return
	}
	ids := parsePanelIDs(board, body["panels"])
	group := copyMap(groups[index])
	kept := make([]string, 0)
	for _, id := range stringList(group["panelIds"]) {
		if !stringContains(ids, id) {
			kept = append(kept, id)
		}
	}
	group["panelIds"] = kept
	groups[index] = group
	s.saveGroups(w, board, groups, map[string]any{"ok": true, "message": "Panels removed from group"})
}

// handleGroupMove mirrors POST .../move: shift the bounds of every panel in
// the group by (dx, dy).
func (s *server) handleGroupMove(w http.ResponseWriter, r *http.Request, board *RemoteBoard, groups []map[string]any, index int) {
	body, err := readJSONBody(r)
	if err != nil {
		fail(w, err)
		return
	}
	dx := numberOr(body["dx"], 0.0)
	dy := numberOr(body["dy"], 0.0)
	panelIDs := map[string]bool{}
	for _, id := range stringList(groups[index]["panelIds"]) {
		panelIDs[id] = true
	}
	_, _, err = s.store.UpdateBoard(board.ID, func(current *RemoteBoard) {
		for i := range current.Panels {
			if !panelIDs[current.Panels[i].ID] {
				continue
			}
			bounds := current.Panels[i].Bounds
			bounds.X = dartFloat(float64(bounds.X) + dx)
			bounds.Y = dartFloat(float64(bounds.Y) + dy)
			current.Panels[i].Bounds = bounds
		}
	}, nil)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": "Group moved"})
}

// saveGroups persists the groups list into board metadata (no history event,
// like Dart) and writes the given response body.
func (s *server) saveGroups(w http.ResponseWriter, board *RemoteBoard, groups []map[string]any, response map[string]any) {
	_, _, err := s.store.UpdateBoard(board.ID, func(current *RemoteBoard) {
		current.Metadata["groups"] = groups
	}, nil)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, response)
}

// boardGroups mirrors _boardGroups: a fresh list of fresh maps from
// metadata['groups'].
func boardGroups(board *RemoteBoard) []map[string]any {
	raw, ok := board.Metadata["groups"].([]any)
	if !ok {
		return []map[string]any{}
	}
	out := make([]map[string]any, 0, len(raw))
	for _, entry := range raw {
		if m, ok := entry.(map[string]any); ok {
			out = append(out, copyMap(m))
		}
	}
	return out
}

// parsePanelIDs mirrors _parsePanelIds: comma-separated string or list of
// ids, each resolved through findPanel (id or title) when possible.
func parsePanelIDs(board *RemoteBoard, value any) []string {
	raw := stringList(value)
	out := make([]string, 0, len(raw))
	for _, id := range raw {
		if panel := findPanel(board, id); panel != nil {
			out = append(out, panel.ID)
		} else {
			out = append(out, id)
		}
	}
	return out
}

// stringList mirrors _stringList: list entries stringified and trimmed, or a
// comma-separated string split and trimmed; empties dropped.
func stringList(value any) []string {
	out := []string{}
	appendTrimmed := func(text string) {
		if trimmed := strings.TrimSpace(text); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	if list, ok := value.([]any); ok {
		for _, entry := range list {
			appendTrimmed(dartToString(entry))
		}
		return out
	}
	if text, ok := value.(string); ok {
		for _, part := range strings.Split(text, ",") {
			appendTrimmed(part)
		}
	}
	return out
}
