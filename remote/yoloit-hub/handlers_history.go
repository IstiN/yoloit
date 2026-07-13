package main

// History, undo and redo endpoints, mirroring _handleHistory and the
// undo/redo branches of YoloitdServer._handleBoards.

import "net/http"

// handleHistory serves GET /api/boards/{id}/history: the full event log for
// the board, sorted by (revision, opId), with no `ok` wrapper — exactly like
// the Dart server.
func (s *server) handleHistory(w http.ResponseWriter, board *RemoteBoard) {
	events, err := s.store.HistoryForBoard(board.ID)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"events": events})
}

// handleUndo serves POST /api/boards/{id}/undo.
func (s *server) handleUndo(w http.ResponseWriter, board *RemoteBoard) {
	undone, err := s.store.UndoLatestPanelHistory(board.ID)
	if err != nil {
		fail(w, err)
		return
	}
	updated, err := s.store.FindBoard(board.ID)
	if err != nil {
		fail(w, err)
		return
	}
	message := "No restorable panel history yet"
	if undone {
		message = "Undid latest panel change"
	}
	response := map[string]any{
		"ok":        undone,
		"undone":    undone,
		"redoDepth": s.store.RedoDepthForBoard(board.ID),
		"message":   message,
	}
	if updated != nil {
		response["board"] = updated.Summary(true)
	}
	writeJSON(w, http.StatusOK, response)
}

// handleRedo serves POST /api/boards/{id}/redo.
func (s *server) handleRedo(w http.ResponseWriter, board *RemoteBoard) {
	redone, err := s.store.RedoLatestPanelHistory(board.ID)
	if err != nil {
		fail(w, err)
		return
	}
	updated, err := s.store.FindBoard(board.ID)
	if err != nil {
		fail(w, err)
		return
	}
	message := "No redoable panel history yet"
	if redone {
		message = "Redid latest undone panel change"
	}
	response := map[string]any{
		"ok":        redone,
		"redone":    redone,
		"redoDepth": s.store.RedoDepthForBoard(board.ID),
		"message":   message,
	}
	if updated != nil {
		response["board"] = updated.Summary(true)
	}
	writeJSON(w, http.StatusOK, response)
}
