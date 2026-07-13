package main

// Board endpoints: Phase 1-core of the yoloitd REST contract
// (lib/core/remote/yoloitd_server.dart::_handleBoards).

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
)

// handleBoardsRoot serves GET/POST /api/boards and 405s other methods,
// mirroring the sub.isEmpty branch of _handleBoards.
func (s *server) handleBoardsRoot(w http.ResponseWriter, r *http.Request) {
	s.handleBoardsList(w, r, r.Method)
}

// handleBoardsSubtree serves /api/boards/{id}[/action] routes. Like the Dart
// server, routing is segment-based and unknown method/route combos fall
// through to 404 "not found".
func (s *server) handleBoardsSubtree(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/api/boards/")
	sub := splitSegments(rest)
	if len(sub) == 0 {
		s.handleBoardsList(w, r, r.Method)
		return
	}

	board, err := s.store.FindBoard(sub[0])
	if err != nil {
		fail(w, err)
		return
	}
	if board == nil {
		writeJSON(w, http.StatusNotFound, map[string]any{
			"ok":    false,
			"error": "board not found",
		})
		return
	}

	switch {
	case len(sub) == 1 && r.Method == http.MethodGet:
		writeJSON(w, http.StatusOK, board)
	case len(sub) == 1 && r.Method == http.MethodDelete:
		s.handleDeleteBoard(w, board)
	case len(sub) == 1 && r.Method == http.MethodPut:
		s.handlePutBoard(w, r, board)
	case len(sub) == 2 && sub[1] == "archive" && r.Method == http.MethodPost:
		s.handleArchive(w, board, true)
	case len(sub) == 2 && sub[1] == "unarchive" && r.Method == http.MethodPost:
		s.handleArchive(w, board, false)
	case len(sub) == 2 && sub[1] == "panel-types" && r.Method == http.MethodGet:
		writeJSON(w, http.StatusOK, map[string]any{"types": panelTypes()})
	case len(sub) == 2 && sub[1] == "snapshot" && r.Method == http.MethodGet:
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = w.Write([]byte(boardSnapshot(board)))
	case len(sub) == 2 && sub[1] == "history" && r.Method == http.MethodGet:
		s.handleHistory(w, board)
	case len(sub) == 2 && sub[1] == "undo" && r.Method == http.MethodPost:
		s.handleUndo(w, board)
	case len(sub) == 2 && sub[1] == "redo" && r.Method == http.MethodPost:
		s.handleRedo(w, board)
	case len(sub) >= 2 && sub[1] == "panels":
		s.handlePanels(w, r, board, sub[2:])
	case len(sub) == 2 && sub[1] == "links" && r.Method == http.MethodGet:
		s.handleLinksList(w, board)
	case len(sub) == 2 && sub[1] == "links" && r.Method == http.MethodPost:
		s.handleLinkCreate(w, r, board)
	case len(sub) == 3 && sub[1] == "links" && r.Method == http.MethodDelete:
		s.handleLinkDelete(w, board, sub[2])
	case len(sub) == 3 && sub[1] == "links" && r.Method == http.MethodPut:
		s.handleLinkUpdate(w, r, board, sub[2])
	case len(sub) >= 2 && sub[1] == "groups":
		s.handleGroups(w, r, board, sub[2:])
	default:
		notFound(w)
	}
}

func splitSegments(rest string) []string {
	parts := strings.Split(rest, "/")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}

func (s *server) handleBoardsList(w http.ResponseWriter, r *http.Request, method string) {
	switch method {
	case http.MethodGet:
		boards, err := s.store.LoadBoards()
		if err != nil {
			fail(w, err)
			return
		}
		activeID, err := s.store.ActiveBoardID()
		if err != nil {
			fail(w, err)
			return
		}
		includeArchived := strings.ToLower(r.URL.Query().Get("includeArchived")) == "true"
		summaries := make([]map[string]any, 0, len(boards))
		for i := range boards {
			if !includeArchived && boards[i].Archived() {
				continue
			}
			summaries = append(summaries, boards[i].Summary(boards[i].ID == activeID))
		}
		writeJSON(w, http.StatusOK, map[string]any{"boards": summaries})
	case http.MethodPost:
		body, err := readJSONBody(r)
		if err != nil {
			fail(w, err)
			return
		}
		name, _ := body["name"].(string)
		name = strings.TrimSpace(name)
		if name == "" {
			name = "Remote Board"
		}
		board, err := s.store.CreateBoard(name)
		if err != nil {
			fail(w, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":    true,
			"board": board.Summary(true),
		})
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"ok":    false,
			"error": "method not allowed",
		})
	}
}

func (s *server) handleDeleteBoard(w http.ResponseWriter, board *RemoteBoard) {
	if err := s.store.DeleteBoard(board.ID); err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":      true,
		"message": "Deleted board " + board.Name,
	})
}

func (s *server) handleArchive(w http.ResponseWriter, board *RemoteBoard, archived bool) {
	verb := "Archived"
	if !archived {
		verb = "Unarchived"
	}
	_, after, err := s.store.UpdateBoard(board.ID, func(current *RemoteBoard) {
		current.Metadata["archived"] = archived
	}, nil)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":      after != nil,
		"message": verb + " board " + board.Name,
	})
}

func (s *server) handlePutBoard(w http.ResponseWriter, r *http.Request, board *RemoteBoard) {
	body, err := readJSONBody(r)
	if err != nil {
		fail(w, err)
		return
	}
	expectedRevision, hasExpected := expectedRevisionFrom(body)
	if isSnapshotUpdate(body) && hasExpected && expectedRevision != board.HistoryRevision() {
		writeJSON(w, http.StatusConflict, map[string]any{
			"ok":               false,
			"error":            "board revision conflict",
			"expectedRevision": expectedRevision,
			"currentRevision":  board.HistoryRevision(),
			"board":            board,
		})
		return
	}

	var updateErr error
	_, after, err := s.store.UpdateBoard(board.ID, func(current *RemoteBoard) {
		if updateErr != nil {
			return
		}
		updateErr = applySnapshotBody(current, body)
	}, func(before, after *RemoteBoard, revision int64) *RemoteHistoryEvent {
		return s.snapshotPanelHistoryEvent(before, after, revision)
	})
	if err != nil {
		fail(w, err)
		return
	}
	if updateErr != nil {
		fail(w, updateErr)
		return
	}
	if after == nil {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "board": nil})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "board": after})
}

// isSnapshotUpdate mirrors _isSnapshotUpdate: revision checks apply only when
// the body carries panels, links, or drawings.
func isSnapshotUpdate(body map[string]any) bool {
	for _, key := range []string{"panels", "links", "drawings"} {
		if _, ok := body[key]; ok {
			return true
		}
	}
	return false
}

// expectedRevisionFrom mirrors _expectedRevision: explicit expectedRevision
// wins, then metadata.historyRevision.
func expectedRevisionFrom(body map[string]any) (int64, bool) {
	if explicit, ok := body["expectedRevision"]; ok && explicit != nil {
		return toInt64(explicit), true
	}
	if metadata, ok := body["metadata"].(map[string]any); ok {
		if revision, ok := metadata["historyRevision"]; ok && revision != nil {
			return toInt64(revision), true
		}
	}
	return 0, false
}

// applySnapshotBody mirrors _updatedBoardFromBody: name/metadata/defaultFolder
// merge, panels/links/drawings replaced only when present as lists, viewport
// always kept from the current board.
func applySnapshotBody(current *RemoteBoard, body map[string]any) error {
	if name, ok := body["name"].(string); ok {
		current.Name = name
	}
	if metadata, ok := body["metadata"].(map[string]any); ok {
		current.Metadata = metadata
	}
	if folder, present := body["defaultFolder"]; present {
		folderStr, _ := folder.(string)
		current.Metadata["defaultFolder"] = folderStr
	}
	if panels, ok := body["panels"].([]any); ok {
		next := make([]RemotePanel, 0, len(panels))
		for _, entry := range panels {
			panelMap, ok := entry.(map[string]any)
			if !ok {
				continue
			}
			panel, err := panelFromMap(panelMap)
			if err != nil {
				return err
			}
			next = append(next, panel)
		}
		current.Panels = next
	}
	if links, ok := body["links"].([]any); ok {
		current.Links = mapList(links)
	}
	if drawings, ok := body["drawings"].([]any); ok {
		current.Drawings = mapList(drawings)
	}
	return nil
}

func mapList(list []any) []map[string]any {
	out := make([]map[string]any, 0, len(list))
	for _, entry := range list {
		if m, ok := entry.(map[string]any); ok {
			out = append(out, m)
		}
	}
	return out
}

// snapshotPanelHistoryEvent mirrors _snapshotPanelHistoryEvent: one event per
// snapshot, preferring panel.created / panel.updated / panel.deleted and
// falling back to board.updated.
func (s *server) snapshotPanelHistoryEvent(before, after *RemoteBoard, revision int64) *RemoteHistoryEvent {
	beforeByID := make(map[string]*RemotePanel, len(before.Panels))
	for i := range before.Panels {
		beforeByID[before.Panels[i].ID] = &before.Panels[i]
	}
	afterByID := make(map[string]*RemotePanel, len(after.Panels))
	for i := range after.Panels {
		afterByID[after.Panels[i].ID] = &after.Panels[i]
	}

	for id, afterPanel := range afterByID {
		beforePanel := beforeByID[id]
		if beforePanel == nil {
			return s.historyEvent(after.ID, "panel.created", "panel", id, revision, nil, afterPanel)
		}
		if !panelsEqual(beforePanel, afterPanel) {
			return s.historyEvent(after.ID, "panel.updated", "panel", id, revision, beforePanel, afterPanel)
		}
	}
	for id, beforePanel := range beforeByID {
		if _, ok := afterByID[id]; ok {
			continue
		}
		return s.historyEvent(after.ID, "panel.deleted", "panel", id, revision, beforePanel, nil)
	}
	return s.historyEvent(after.ID, "board.updated", "board", after.ID, revision, nil, nil)
}

func panelsEqual(a, b *RemotePanel) bool {
	aj, err := marshalCompact(a)
	if err != nil {
		return false
	}
	bj, err := marshalCompact(b)
	if err != nil {
		return false
	}
	return string(aj) == string(bj)
}

// historyEvent mirrors _historyEvent in yoloitd_server.dart: op-<micros> id,
// store actor id, UTC timestamp, empty patch, no restoresOpId.
func (s *server) historyEvent(
	boardID, eventType, entityType, entityID string,
	revision int64,
	beforePanel, afterPanel *RemotePanel,
) *RemoteHistoryEvent {
	event := &RemoteHistoryEvent{
		OpID:       nextID("op"),
		BoardID:    boardID,
		Type:       eventType,
		EntityType: entityType,
		EntityID:   entityID,
		ActorID:    s.store.ActorID,
		Timestamp:  dartTimeNow(),
		Revision:   revision,
		Patch:      json.RawMessage(`{}`),
	}
	if beforePanel != nil {
		event.Before = mustMarshal(beforePanel)
	}
	if afterPanel != nil {
		event.After = mustMarshal(afterPanel)
	}
	return event
}

func mustMarshal(v any) json.RawMessage {
	data, err := marshalCompact(v)
	if err != nil {
		panic(errors.New("unreachable: panel marshal failed: " + err.Error()))
	}
	return data
}
