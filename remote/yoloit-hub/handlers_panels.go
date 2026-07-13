package main

// Panel endpoints, mirroring YoloitdServer._handlePanels.

import (
	"encoding/json"
	"math"
	"net/http"
	"strconv"
	"strings"
)

// handlePanels serves /api/boards/{id}/panels[/{panel}[/action]] routes.
// Unknown method/route combos fall through to 404 "not found", like Dart.
func (s *server) handlePanels(w http.ResponseWriter, r *http.Request, board *RemoteBoard, sub []string) {
	if len(sub) == 0 {
		s.handlePanelsRoot(w, r, board)
		return
	}

	panel := findPanel(board, sub[0])
	if panel == nil {
		writeJSON(w, http.StatusNotFound, map[string]any{
			"ok":    false,
			"error": "panel not found",
		})
		return
	}

	switch {
	case len(sub) == 1 && r.Method == http.MethodGet:
		writeJSON(w, http.StatusOK, enrichedPanel(panel))
	case len(sub) == 1 && r.Method == http.MethodDelete:
		ok, err := s.store.RemovePanel(board.ID, panel.ID, true)
		if err != nil {
			fail(w, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": ok})
	case len(sub) == 1 && r.Method == http.MethodPut:
		s.handlePutPanel(w, r, board, panel)
	case len(sub) == 2 && sub[1] == "action" && r.Method == http.MethodPost:
		s.handlePanelAction(w, r, board, panel)
	default:
		notFound(w)
	}
}

// handlePanelsRoot serves GET/POST on the panels collection and 405s other
// methods, mirroring the sub.isEmpty branches of _handlePanels.
func (s *server) handlePanelsRoot(w http.ResponseWriter, r *http.Request, board *RemoteBoard) {
	switch r.Method {
	case http.MethodGet:
		summaries := make([]map[string]any, 0, len(board.Panels))
		for i := range board.Panels {
			summaries = append(summaries, panelSummary(&board.Panels[i]))
		}
		writeJSON(w, http.StatusOK, map[string]any{"panels": summaries})
	case http.MethodPost:
		s.handleCreatePanel(w, r, board)
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"ok":    false,
			"error": "method not allowed",
		})
	}
}

// handleCreatePanel mirrors the POST branch of _handlePanels: id/type/title/
// x/y/width/height/state from the body with Dart defaults; params, color,
// zIndex etc. come from RemotePanel's own defaults and addPanel's zIndex
// assignment.
func (s *server) handleCreatePanel(w http.ResponseWriter, r *http.Request, board *RemoteBoard) {
	body, err := readJSONBody(r)
	if err != nil {
		fail(w, err)
		return
	}
	panel := RemotePanel{
		ID:     nextID("p"),
		Type:   "board.note.markdown",
		Title:  "Panel",
		State:  map[string]any{},
		Params: map[string]any{},
	}
	if id, ok := body["id"].(string); ok {
		panel.ID = id
	}
	if panelType, ok := body["type"].(string); ok {
		panel.Type = panelType
	}
	if title, ok := body["title"].(string); ok {
		panel.Title = title
	}
	panel.Bounds = RemotePanelBounds{
		X:      dartFloat(numberOr(body["x"], 120.0)),
		Y:      dartFloat(numberOr(body["y"], 120.0)),
		Width:  dartFloat(numberOr(body["width"], 360.0)),
		Height: dartFloat(numberOr(body["height"], 240.0)),
	}
	if state, ok := body["state"].(map[string]any); ok {
		panel.State = state
	}
	created, err := s.store.AddPanel(board.ID, panel)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":    true,
		"panel": created,
		"id":    created.ID,
	})
}

// handlePutPanel mirrors the PUT branch of _handlePanels: per-field copyWith
// semantics. Note the mirrored Dart quirk: `color` is ALWAYS overwritten from
// _parseColorValue(body['color']), so omitting the key clears the color.
func (s *server) handlePutPanel(w http.ResponseWriter, r *http.Request, board *RemoteBoard, panel *RemotePanel) {
	body, err := readJSONBody(r)
	if err != nil {
		fail(w, err)
		return
	}
	updated, err := s.store.UpdatePanel(board.ID, panel.ID, func(current RemotePanel) RemotePanel {
		if title, ok := body["title"].(string); ok {
			current.Title = title
		}
		bounds := current.Bounds
		if value, ok := body["x"]; ok && isNumber(value) {
			bounds.X = dartFloat(toFloat64(value, float64(bounds.X)))
		}
		if value, ok := body["y"]; ok && isNumber(value) {
			bounds.Y = dartFloat(toFloat64(value, float64(bounds.Y)))
		}
		if value, ok := body["width"]; ok && isNumber(value) {
			bounds.Width = dartFloat(toFloat64(value, float64(bounds.Width)))
		}
		if value, ok := body["height"]; ok && isNumber(value) {
			bounds.Height = dartFloat(toFloat64(value, float64(bounds.Height)))
		}
		current.Bounds = bounds
		if hidden, ok := body["hidden"].(bool); ok {
			current.Hidden = hidden
		}
		if locked, ok := body["locked"].(bool); ok {
			current.Locked = locked
		}
		if pinned, ok := body["pinned"].(bool); ok {
			current.Pinned = pinned
		}
		if value, ok := body["zIndex"]; ok && isNumber(value) {
			current.ZIndex = toInt64(value)
		}
		current.Color = parseColorValue(body["color"])
		if state, ok := body["state"].(map[string]any); ok {
			current.State = state
		}
		return current
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":    updated != nil,
		"panel": updated,
	})
}

// handlePanelAction mirrors the POST .../action branch of _handlePanels:
// dispatch through handleRemotePanelAction; failed results are 400 with the
// result envelope, data-only results add a `content` key, and state updates
// are merged into the panel state via updatePanel.
func (s *server) handlePanelAction(w http.ResponseWriter, r *http.Request, board *RemoteBoard, panel *RemotePanel) {
	body, err := readJSONBody(r)
	if err != nil {
		fail(w, err)
		return
	}
	action := "get"
	if value, ok := body["action"].(string); ok {
		action = value
	}
	result := handleRemotePanelAction(panel, action, body)
	if !result.ok {
		writeJSON(w, http.StatusBadRequest, result.toJSON(nil))
		return
	}
	if len(result.stateUpdate) == 0 {
		response := result.toJSON(nil)
		if len(result.data) == 0 {
			response["content"] = panel.State
		} else {
			response["content"] = result.data
		}
		writeJSON(w, http.StatusOK, response)
		return
	}
	nextState := make(map[string]any, len(panel.State)+len(result.stateUpdate))
	for key, value := range panel.State {
		nextState[key] = value
	}
	for key, value := range result.stateUpdate {
		nextState[key] = value
	}
	updated, err := s.store.UpdatePanel(board.ID, panel.ID, func(current RemotePanel) RemotePanel {
		current.State = nextState
		return current
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, result.toJSON(updated))
}

// findPanel mirrors YoloitdServer._findPanel: exact id, then
// case-insensitive title.
func findPanel(board *RemoteBoard, idOrTitle string) *RemotePanel {
	for i := range board.Panels {
		if board.Panels[i].ID == idOrTitle {
			return &board.Panels[i]
		}
	}
	lower := strings.ToLower(idOrTitle)
	for i := range board.Panels {
		if strings.ToLower(board.Panels[i].Title) == lower {
			return &board.Panels[i]
		}
	}
	return nil
}

// panelSummary mirrors YoloitdServer._panelSummary: the full panel JSON plus
// typeName and content (the raw state).
func panelSummary(panel *RemotePanel) map[string]any {
	var m map[string]any
	if err := decodeUseNumber(mustMarshal(panel), &m); err != nil {
		m = map[string]any{}
	}
	m["typeName"] = panel.Type
	m["content"] = panel.State
	return m
}

// enrichedPanel mirrors the GET-single branch of _handlePanels: panelSummary
// plus supportedActions and actionHelp from the catalog.
func enrichedPanel(panel *RemotePanel) map[string]any {
	m := panelSummary(panel)
	m["supportedActions"] = supportedActions(panel.Type)
	m["actionHelp"] = remotePanelActionHelp(panel)
	return m
}

// supportedActions mirrors `descriptor?.actions ?? const ['get', 'set']`.
func supportedActions(panelType string) []string {
	if d := panelDescriptorFor(panelType); d != nil {
		return d.Actions
	}
	return []string{"get", "set"}
}

// remotePanelActionHelp mirrors remotePanelActionHelp in
// yoloitd_panel_actions.dart.
func remotePanelActionHelp(panel *RemotePanel) map[string]any {
	help := map[string]any{"actions": supportedActions(panel.Type)}
	if d := panelDescriptorFor(panel.Type); d != nil {
		help["capabilities"] = capabilitiesMap(d)
	}
	return help
}

// parseColorValue mirrors YoloitdServer._parseColorValue: null/'clear' →
// nil, ints pass through, '#hex' strings parse as base-16, anything else
// becomes nil.
func parseColorValue(value any) *int64 {
	if value == nil {
		return nil
	}
	if number, ok := value.(json.Number); ok {
		if parsed, err := number.Int64(); err == nil {
			return &parsed
		}
		return nil
	}
	if f, ok := value.(float64); ok {
		if f == math.Trunc(f) {
			parsed := int64(f)
			return &parsed
		}
		return nil
	}
	text, ok := value.(string)
	if !ok {
		return nil
	}
	if text == "clear" {
		return nil
	}
	text = strings.TrimSpace(text)
	if text == "" || text == "clear" {
		return nil
	}
	if strings.HasPrefix(text, "#") {
		if parsed, err := strconv.ParseInt(text[1:], 16, 64); err == nil {
			return &parsed
		}
	}
	return nil
}

func isNumber(value any) bool {
	switch value.(type) {
	case json.Number, float64:
		return true
	}
	return false
}

// numberOr mirrors `(body[k] as num?)?.toDouble() ?? fallback`.
func numberOr(value any, fallback float64) float64 {
	if !isNumber(value) {
		return fallback
	}
	return toFloat64(value, fallback)
}
