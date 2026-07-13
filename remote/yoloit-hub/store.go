package main

// Persistence layer mirroring lib/core/remote/yoloitd_store.dart. The on-disk
// layout is identical to yoloitd so data directories are interchangeable:
//
//	<dataDir>/boards.json     JSON array of all boards (atomic rewrite)
//	<dataDir>/active_board    plain-text active board id
//	<dataDir>/boards_history/<board-id>/events/YYYY/MM/<op-id>_<actor-id>.json

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

var unsafeSegmentChars = regexp.MustCompile(`[^a-zA-Z0-9._-]`)

// safeSegment mirrors HistoryStoreHelpers.safeSegment.
func safeSegment(value string) string {
	return unsafeSegmentChars.ReplaceAllString(value, "_")
}

var (
	idMu   sync.Mutex
	lastID int64
)

// nextID mirrors Dart's '$prefix-${DateTime.now().microsecondsSinceEpoch}'
// with a monotonic guard against same-microsecond collisions.
func nextID(prefix string) string {
	idMu.Lock()
	defer idMu.Unlock()
	micros := time.Now().UnixMicro()
	if micros <= lastID {
		micros = lastID + 1
	}
	lastID = micros
	return fmt.Sprintf("%s-%d", prefix, micros)
}

// redoKind mirrors _RemoteRedoKind in yoloitd_store.dart.
type redoKind int

const (
	redoRecreatePanel redoKind = iota
	redoRestorePanel
	redoDeletePanel
)

// redoEntry mirrors _RemoteRedoEntry: recreate/restore carry a panel
// snapshot, delete carries only the panel id.
type redoEntry struct {
	kind    redoKind
	panel   *RemotePanel
	panelID string
}

// Store is the yoloit-hub equivalent of YoloitdStore.
type Store struct {
	RootDir string
	ActorID string

	mu sync.Mutex
	// redoStacks holds per-board in-memory redo entries, lost on restart
	// (same as Dart's _redoStacks). replaying suppresses redo-stack clearing
	// while an undo/redo replays history (Dart's _replayingHistory).
	redoStacks map[string][]redoEntry
	replaying  bool
}

func NewStore(rootDir, actorID string) *Store {
	if strings.TrimSpace(actorID) == "" {
		actorID = "yoloit-hub"
	}
	return &Store{RootDir: rootDir, ActorID: actorID, redoStacks: map[string][]redoEntry{}}
}

func (s *Store) boardsFile() string { return filepath.Join(s.RootDir, "boards.json") }
func (s *Store) activeFile() string { return filepath.Join(s.RootDir, "active_board") }

// Init mirrors YoloitdStore.init: create the data dir and seed a default
// board when none exists yet.
func (s *Store) Init() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	boards, err := s.loadBoardsLocked()
	if err != nil {
		return err
	}
	if len(boards) == 0 {
		board := defaultBoard("Remote Board")
		return s.saveBoardsLocked([]RemoteBoard{board}, strPtr(board.ID))
	}
	return nil
}

func defaultBoard(name string) RemoteBoard {
	return RemoteBoard{
		ID:       nextID("board"),
		Name:     name,
		Viewport: defaultViewport(),
		Panels:   []RemotePanel{},
		Links:    []map[string]any{},
		Drawings: []map[string]any{},
		Metadata: map[string]any{},
	}
}

func (s *Store) LoadBoards() ([]RemoteBoard, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.loadBoardsLocked()
}

func (s *Store) loadBoardsLocked() ([]RemoteBoard, error) {
	data, err := os.ReadFile(s.boardsFile())
	if os.IsNotExist(err) {
		return []RemoteBoard{}, nil
	}
	if err != nil {
		return nil, err
	}
	var boards []RemoteBoard
	if err := decodeUseNumber(data, &boards); err != nil {
		return nil, err
	}
	if boards == nil {
		boards = []RemoteBoard{}
	}
	return boards, nil
}

func (s *Store) ActiveBoardID() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.activeBoardIDLocked()
}

func (s *Store) activeBoardIDLocked() (string, error) {
	data, err := os.ReadFile(s.activeFile())
	if os.IsNotExist(err) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}

// saveBoardsLocked mirrors YoloitdStore.saveBoards: atomic rewrite of
// boards.json plus active_board update (delete when nil).
func (s *Store) saveBoardsLocked(boards []RemoteBoard, activeBoardID *string) error {
	if err := os.MkdirAll(s.RootDir, 0o755); err != nil {
		return err
	}
	if err := writeJSONAtomic(s.boardsFile(), boards, true); err != nil {
		return err
	}
	if activeBoardID == nil {
		if err := os.Remove(s.activeFile()); err != nil && !os.IsNotExist(err) {
			return err
		}
		return nil
	}
	return os.WriteFile(s.activeFile(), []byte(*activeBoardID), 0o644)
}

// writeJSONAtomic mirrors HistoryStoreHelpers.writeJsonAtomic: write to a
// temp file in the same directory, delete the target, then rename.
func writeJSONAtomic(path string, value any, indent bool) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if indent {
		enc.SetIndent("", "  ")
	}
	if err := enc.Encode(value); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, buf.Bytes(), 0o644); err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	return os.Rename(tmp, path)
}

func (s *Store) CreateBoard(name string) (RemoteBoard, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	boards, err := s.loadBoardsLocked()
	if err != nil {
		return RemoteBoard{}, err
	}
	board := defaultBoard(name)
	boards = append(boards, board)
	if err := s.saveBoardsLocked(boards, strPtr(board.ID)); err != nil {
		return RemoteBoard{}, err
	}
	return board, nil
}

// FindBoard mirrors YoloitdStore.findBoard: exact id, then case-insensitive
// name, then id prefix.
func (s *Store) FindBoard(idOrName string) (*RemoteBoard, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.findBoardLocked(idOrName)
}

func (s *Store) findBoardLocked(idOrName string) (*RemoteBoard, error) {
	boards, err := s.loadBoardsLocked()
	if err != nil {
		return nil, err
	}
	for i := range boards {
		if boards[i].ID == idOrName {
			return &boards[i], nil
		}
	}
	lower := strings.ToLower(idOrName)
	for i := range boards {
		if strings.ToLower(boards[i].Name) == lower {
			return &boards[i], nil
		}
	}
	for i := range boards {
		if strings.HasPrefix(boards[i].ID, idOrName) {
			return &boards[i], nil
		}
	}
	return nil, nil
}

// UpdateBoard mirrors YoloitdStore.updateBoard. mutate transforms the board
// in place; when makeEvent is non-nil and the board JSON actually changed,
// metadata.historyRevision is incremented and a history event is appended.
func (s *Store) UpdateBoard(
	boardID string,
	mutate func(b *RemoteBoard),
	makeEvent func(before, after *RemoteBoard, revision int64) *RemoteHistoryEvent,
) (*RemoteBoard, *RemoteBoard, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.updateBoardLocked(boardID, mutate, makeEvent)
}

func (s *Store) updateBoardLocked(
	boardID string,
	mutate func(b *RemoteBoard),
	makeEvent func(before, after *RemoteBoard, revision int64) *RemoteHistoryEvent,
) (*RemoteBoard, *RemoteBoard, error) {
	boards, err := s.loadBoardsLocked()
	if err != nil {
		return nil, nil, err
	}
	activeID, err := s.activeBoardIDLocked()
	if err != nil {
		return nil, nil, err
	}
	index := -1
	for i := range boards {
		if boards[i].ID == boardID {
			index = i
			break
		}
	}
	if index == -1 {
		return nil, nil, nil
	}
	before := boards[index]
	beforeJSON, err := marshalCompact(&before)
	if err != nil {
		return nil, nil, err
	}

	// Shallow-copy the board and its metadata map so mutations never alias
	// the pre-update state (Dart's copyWith spreads metadata into a new map).
	after := before
	after.Metadata = make(map[string]any, len(before.Metadata)+1)
	for k, v := range before.Metadata {
		after.Metadata[k] = v
	}
	mutate(&after)

	var event *RemoteHistoryEvent
	afterJSON, err := marshalCompact(&after)
	if err != nil {
		return nil, nil, err
	}
	if makeEvent != nil && !bytes.Equal(beforeJSON, afterJSON) {
		revision := before.HistoryRevision() + 1
		after.Metadata["historyRevision"] = revision
		event = makeEvent(&before, &after, revision)
	}

	boards[index] = after
	if activeID == "" {
		activeID = boardID
	}
	if err := s.saveBoardsLocked(boards, strPtr(activeID)); err != nil {
		return nil, nil, err
	}
	if event != nil {
		if err := s.appendHistoryLocked(event); err != nil {
			return nil, nil, err
		}
	}
	return &before, &after, nil
}

// DeleteBoard mirrors YoloitdStore.deleteBoard.
func (s *Store) DeleteBoard(boardID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	boards, err := s.loadBoardsLocked()
	if err != nil {
		return err
	}
	activeID, err := s.activeBoardIDLocked()
	if err != nil {
		return err
	}
	next := make([]RemoteBoard, 0, len(boards))
	for _, b := range boards {
		if b.ID != boardID {
			next = append(next, b)
		}
	}
	var nextActive *string
	if activeID == boardID {
		if len(next) > 0 {
			nextActive = strPtr(next[0].ID)
		}
	} else {
		nextActive = strPtr(activeID)
	}
	return s.saveBoardsLocked(next, nextActive)
}

// appendHistoryLocked mirrors HistoryStoreHelpers.appendEvent: the event
// lands at boards_history/<board-id>/events/YYYY/MM/<op-id>_<actor-id>.json.
// Like YoloitdStore.appendHistory, any eventful mutation outside a replay
// clears the board's redo stack.
func (s *Store) appendHistoryLocked(event *RemoteHistoryEvent) error {
	if !s.replaying {
		delete(s.redoStacks, event.BoardID)
	}
	t := time.Time(event.Timestamp).UTC()
	dir := filepath.Join(
		s.RootDir,
		"boards_history",
		safeSegment(event.BoardID),
		"events",
		fmt.Sprintf("%04d", t.Year()),
		fmt.Sprintf("%02d", int(t.Month())),
	)
	file := filepath.Join(dir, safeSegment(event.OpID)+"_"+safeSegment(event.ActorID)+".json")
	return writeJSONAtomic(file, event, true)
}

// --- Panel operations (mirror YoloitdStore.addPanel/updatePanel/...) ---

// panelHistoryEvent mirrors YoloitdStore._event: entityType is always
// 'panel'; patch defaults to {} and restoresOpId is nullable.
func (s *Store) panelHistoryEvent(
	boardID, eventType, entityID string,
	revision int64,
	beforePanel, afterPanel *RemotePanel,
	patch map[string]any,
	restoresOpID *string,
) *RemoteHistoryEvent {
	event := &RemoteHistoryEvent{
		OpID:         nextID("op"),
		BoardID:      boardID,
		Type:         eventType,
		EntityType:   "panel",
		EntityID:     entityID,
		ActorID:      s.ActorID,
		Timestamp:    dartTimeNow(),
		Revision:     revision,
		Patch:        json.RawMessage(`{}`),
		RestoresOpID: restoresOpID,
	}
	if beforePanel != nil {
		event.Before = mustMarshal(beforePanel)
	}
	if afterPanel != nil {
		event.After = mustMarshal(afterPanel)
	}
	if patch != nil {
		event.Patch = mustMarshal(patch)
	}
	return event
}

// AddPanel mirrors YoloitdStore.addPanel: zIndex 0 becomes maxZIndex+1 and a
// panel.created event is recorded.
func (s *Store) AddPanel(boardID string, panel RemotePanel) (RemotePanel, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.addPanelLocked(boardID, panel)
}

func (s *Store) addPanelLocked(boardID string, panel RemotePanel) (RemotePanel, error) {
	var created RemotePanel
	_, _, err := s.updateBoardLocked(boardID, func(b *RemoteBoard) {
		zIndex := int64(0)
		for _, p := range b.Panels {
			if p.ZIndex > zIndex {
				zIndex = p.ZIndex
			}
		}
		zIndex++
		created = panel
		if created.ZIndex == 0 {
			created.ZIndex = zIndex
		}
		b.Panels = append(b.Panels, created)
	}, func(before, after *RemoteBoard, revision int64) *RemoteHistoryEvent {
		return s.panelHistoryEvent(boardID, "panel.created", created.ID, revision, nil, &created, nil, nil)
	})
	return created, err
}

// UpdatePanel mirrors YoloitdStore.updatePanel: update transforms the panel;
// a panel.updated event with a field-level patch is recorded. Returns the
// updated panel, or nil when no panel with panelID exists.
func (s *Store) UpdatePanel(
	boardID, panelID string,
	update func(current RemotePanel) RemotePanel,
) (*RemotePanel, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.updatePanelLocked(boardID, panelID, update)
}

func (s *Store) updatePanelLocked(
	boardID, panelID string,
	update func(current RemotePanel) RemotePanel,
) (*RemotePanel, error) {
	var beforePanel, afterPanel *RemotePanel
	_, _, err := s.updateBoardLocked(boardID, func(b *RemoteBoard) {
		panels := make([]RemotePanel, 0, len(b.Panels))
		for _, p := range b.Panels {
			if p.ID == panelID {
				before := p
				after := update(p)
				beforePanel = &before
				afterPanel = &after
				panels = append(panels, after)
			} else {
				panels = append(panels, p)
			}
		}
		b.Panels = panels
	}, func(before, after *RemoteBoard, revision int64) *RemoteHistoryEvent {
		patch := map[string]any{}
		if beforePanel != nil && afterPanel != nil {
			patch = panelPatch(beforePanel, afterPanel)
		}
		return s.panelHistoryEvent(boardID, "panel.updated", panelID, revision, beforePanel, afterPanel, patch, nil)
	})
	if err != nil {
		return nil, err
	}
	return afterPanel, nil
}

// RemovePanel mirrors YoloitdStore.removePanel: links referencing the panel
// are dropped too, and a panel.deleted event is recorded unless recordHistory
// is false (undo of a panel.created).
func (s *Store) RemovePanel(boardID, panelID string, recordHistory bool) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.removePanelLocked(boardID, panelID, recordHistory)
}

func (s *Store) removePanelLocked(boardID, panelID string, recordHistory bool) (bool, error) {
	var removed *RemotePanel
	var makeEvent func(before, after *RemoteBoard, revision int64) *RemoteHistoryEvent
	if recordHistory {
		makeEvent = func(before, after *RemoteBoard, revision int64) *RemoteHistoryEvent {
			return s.panelHistoryEvent(boardID, "panel.deleted", panelID, revision, removed, nil, nil, nil)
		}
	}
	_, _, err := s.updateBoardLocked(boardID, func(b *RemoteBoard) {
		panels := make([]RemotePanel, 0, len(b.Panels))
		for _, p := range b.Panels {
			if p.ID == panelID {
				removedPanel := p
				removed = &removedPanel
			} else {
				panels = append(panels, p)
			}
		}
		links := make([]map[string]any, 0, len(b.Links))
		for _, link := range b.Links {
			if linkReferencesPanel(link, panelID) {
				continue
			}
			links = append(links, link)
		}
		b.Panels = panels
		b.Links = links
	}, makeEvent)
	return removed != nil, err
}

// linkReferencesPanel mirrors the link filter in YoloitdStore.removePanel.
func linkReferencesPanel(link map[string]any, panelID string) bool {
	for _, key := range []string{"fromPanelId", "toPanelId", "from", "to"} {
		if value, ok := link[key].(string); ok && value == panelID {
			return true
		}
	}
	return false
}

// RestorePanel mirrors YoloitdStore.restorePanel: replace the panel in place
// (or append it when missing) and record a panel.restored event carrying the
// restoresOpId of the undone event.
func (s *Store) restorePanelLocked(boardID string, panel RemotePanel, restoresOpID string) error {
	_, _, err := s.updateBoardLocked(boardID, func(b *RemoteBoard) {
		panels := make([]RemotePanel, 0, len(b.Panels)+1)
		replaced := false
		for _, p := range b.Panels {
			if p.ID == panel.ID {
				panels = append(panels, panel)
				replaced = true
			} else {
				panels = append(panels, p)
			}
		}
		if !replaced {
			panels = append(panels, panel)
		}
		b.Panels = panels
	}, func(before, after *RemoteBoard, revision int64) *RemoteHistoryEvent {
		return s.panelHistoryEvent(boardID, "panel.restored", panel.ID, revision, nil, &panel, nil, &restoresOpID)
	})
	return err
}

// panelPatch mirrors YoloitdStore._panelPatch: per-field before/after entries
// for every changed top-level panel field, compared by JSON encoding.
func panelPatch(before, after *RemotePanel) map[string]any {
	patch := map[string]any{}
	addIfChanged := func(key string, beforeValue, afterValue any) {
		if !jsonEqual(beforeValue, afterValue) {
			patch[key] = map[string]any{"before": beforeValue, "after": afterValue}
		}
	}
	addIfChanged("title", before.Title, after.Title)
	addIfChanged("bounds", before.Bounds, after.Bounds)
	addIfChanged("color", before.Color, after.Color)
	addIfChanged("params", before.Params, after.Params)
	addIfChanged("zIndex", before.ZIndex, after.ZIndex)
	addIfChanged("hidden", before.Hidden, after.Hidden)
	addIfChanged("locked", before.Locked, after.Locked)
	addIfChanged("pinned", before.Pinned, after.Pinned)
	addIfChanged("state", before.State, after.State)
	return patch
}

// jsonEqual mirrors Dart's jsonEncode(a) == jsonEncode(b) comparison.
func jsonEqual(a, b any) bool {
	aj, err := marshalCompact(a)
	if err != nil {
		return false
	}
	bj, err := marshalCompact(b)
	if err != nil {
		return false
	}
	return bytes.Equal(aj, bj)
}

// --- History loading & undo/redo (mirror YoloitdStore) ---

// HistoryForBoard mirrors YoloitdStore.historyForBoard: all events under the
// board's events dir, sorted by (revision, opId).
func (s *Store) HistoryForBoard(boardID string) ([]RemoteHistoryEvent, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.historyForBoardLocked(boardID)
}

func (s *Store) historyForBoardLocked(boardID string) ([]RemoteHistoryEvent, error) {
	root := filepath.Join(s.RootDir, "boards_history", safeSegment(boardID), "events")
	events := []RemoteHistoryEvent{}
	if _, err := os.Stat(root); os.IsNotExist(err) {
		return events, nil
	}
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(path, ".json") {
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		var probe any
		if err := decodeUseNumber(data, &probe); err != nil {
			return nil // not valid JSON: skip, like a corrupt trailing write
		}
		if _, ok := probe.(map[string]any); !ok {
			return nil // Dart: `if (decoded is Map)`
		}
		var event RemoteHistoryEvent
		if err := decodeUseNumber(data, &event); err != nil {
			return err
		}
		events = append(events, event)
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.SliceStable(events, func(i, j int) bool {
		if events[i].Revision != events[j].Revision {
			return events[i].Revision < events[j].Revision
		}
		return events[i].OpID < events[j].OpID
	})
	return events, nil
}

// RedoDepthForBoard mirrors YoloitdStore.redoDepthForBoard.
func (s *Store) RedoDepthForBoard(boardID string) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.redoStacks[boardID])
}

func (s *Store) pushRedoLocked(boardID string, entry redoEntry) {
	if s.redoStacks == nil {
		s.redoStacks = map[string][]redoEntry{}
	}
	s.redoStacks[boardID] = append(s.redoStacks[boardID], entry)
}

// runHistoryReplayLocked mirrors YoloitdStore._runHistoryReplay: events
// appended while replaying must not clear the redo stack.
func (s *Store) runHistoryReplayLocked(action func() (bool, error)) (bool, error) {
	s.replaying = true
	defer func() { s.replaying = false }()
	return action()
}

// UndoLatestPanelHistory mirrors YoloitdStore.undoLatestPanelHistory: scan
// the event log newest-first for the latest restorable panel event and
// revert it, pushing the inverse onto the redo stack.
func (s *Store) UndoLatestPanelHistory(boardID string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.runHistoryReplayLocked(func() (bool, error) {
		board, err := s.findBoardLocked(boardID)
		if err != nil || board == nil {
			return false, err
		}
		events, err := s.historyForBoardLocked(board.ID)
		if err != nil {
			return false, err
		}

		for index := len(events) - 1; index >= 0; index-- {
			event := events[index]
			if event.EntityType != "panel" {
				continue
			}
			if event.RestoresOpID != nil || event.Type == "panel.restored" {
				continue
			}
			var current *RemotePanel
			for i := range board.Panels {
				if board.Panels[i].ID == event.EntityID {
					current = &board.Panels[i]
					break
				}
			}
			before, err := panelFromEventRaw(event.Before)
			if err != nil {
				return false, err
			}
			after, err := panelFromEventRaw(event.After)
			if err != nil {
				return false, err
			}

			// Undo of a panel.created: silently remove the recreated panel.
			if after != nil && before == nil && current != nil && matchesCreateUndo(current, after) {
				s.pushRedoLocked(board.ID, redoEntry{kind: redoRecreatePanel, panel: after})
				if _, err := s.removePanelLocked(board.ID, after.ID, false); err != nil {
					return false, err
				}
				return true, nil
			}
			// Undo of an update: restore the (coalesced) before snapshot.
			if before != nil && current != nil && !panelsEqual(current, before) {
				start := coalescedPanelUpdateStart(events, index)
				snapshot := before
				if !rawIsNull(start.Before) {
					parsed, err := panelFromRaw(start.Before)
					if err != nil {
						return false, err
					}
					snapshot = &parsed
				}
				if after != nil {
					s.pushRedoLocked(board.ID, redoEntry{kind: redoRestorePanel, panel: after})
				}
				if err := s.restorePanelLocked(board.ID, *snapshot, event.OpID); err != nil {
					return false, err
				}
				return true, nil
			}
			// Undo of a panel.deleted: bring the deleted panel back.
			if before != nil && current == nil && event.Type == "panel.deleted" {
				s.pushRedoLocked(board.ID, redoEntry{kind: redoDeletePanel, panelID: event.EntityID})
				if err := s.restorePanelLocked(board.ID, *before, event.OpID); err != nil {
					return false, err
				}
				return true, nil
			}
		}
		return false, nil
	})
}

// RedoLatestPanelHistory mirrors YoloitdStore.redoLatestPanelHistory: pop the
// latest redo entry and replay it (recording history like a fresh edit).
func (s *Store) RedoLatestPanelHistory(boardID string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	stack := s.redoStacks[boardID]
	if len(stack) == 0 {
		return false, nil
	}
	board, err := s.findBoardLocked(boardID)
	if err != nil || board == nil {
		return false, err
	}

	entry := stack[len(stack)-1]
	stack = stack[:len(stack)-1]
	if len(stack) == 0 {
		delete(s.redoStacks, boardID)
	} else {
		s.redoStacks[boardID] = stack
	}

	return s.runHistoryReplayLocked(func() (bool, error) {
		switch entry.kind {
		case redoRecreatePanel:
			if entry.panel == nil {
				return false, nil
			}
			if _, err := s.addPanelLocked(board.ID, *entry.panel); err != nil {
				return false, err
			}
			return true, nil
		case redoRestorePanel:
			if entry.panel == nil {
				return false, nil
			}
			return s.applyPanelSnapshotLocked(board.ID, *entry.panel)
		case redoDeletePanel:
			if entry.panelID == "" {
				return false, nil
			}
			return s.removePanelLocked(board.ID, entry.panelID, true)
		}
		return false, nil
	})
}

// applyPanelSnapshotLocked mirrors YoloitdStore._applyPanelSnapshot.
func (s *Store) applyPanelSnapshotLocked(boardID string, panel RemotePanel) (bool, error) {
	board, err := s.findBoardLocked(boardID)
	if err != nil || board == nil {
		return false, err
	}
	var current *RemotePanel
	for i := range board.Panels {
		if board.Panels[i].ID == panel.ID {
			current = &board.Panels[i]
			break
		}
	}
	if current != nil && panelsEqual(current, &panel) {
		return false, nil
	}
	if current != nil {
		if _, err := s.updatePanelLocked(boardID, panel.ID, func(RemotePanel) RemotePanel { return panel }); err != nil {
			return false, err
		}
		return true, nil
	}
	if _, err := s.addPanelLocked(boardID, panel); err != nil {
		return false, err
	}
	return true, nil
}

// panelFromEventRaw parses a before/after payload, nil when absent or null.
func panelFromEventRaw(raw json.RawMessage) (*RemotePanel, error) {
	if rawIsNull(raw) {
		return nil, nil
	}
	panel, err := panelFromRaw(raw)
	if err != nil {
		return nil, err
	}
	return &panel, nil
}

// matchesCreateUndo mirrors YoloitdStore._matchesCreateUndo: panels equal
// except for the zIndex assigned at creation time.
func matchesCreateUndo(current, after *RemotePanel) bool {
	return string(panelJSONWithoutZIndex(current)) == string(panelJSONWithoutZIndex(after))
}

func panelJSONWithoutZIndex(panel *RemotePanel) []byte {
	var m map[string]any
	if err := decodeUseNumber(mustMarshal(panel), &m); err != nil {
		return nil
	}
	delete(m, "zIndex")
	data, err := marshalCompact(m)
	if err != nil {
		return nil
	}
	return data
}

// coalescedPanelUpdateStart mirrors YoloitdStore._coalescedPanelUpdateStart:
// walk back over consecutive same-panel, same-patch-signature updates so an
// undo reverts the whole coalesced run at once.
func coalescedPanelUpdateStart(events []RemoteHistoryEvent, latestIndex int) RemoteHistoryEvent {
	latest := events[latestIndex]
	if latest.Type != "panel.updated" && latest.Type != "panel.placedInGrid" {
		return latest
	}
	start := latestIndex
	signature := patchSignature(latest)
	for start > 0 {
		previous := events[start-1]
		if previous.Type != latest.Type ||
			previous.EntityType != latest.EntityType ||
			previous.EntityID != latest.EntityID ||
			previous.RestoresOpID != nil ||
			previous.Revision+1 != events[start].Revision ||
			patchSignature(previous) != signature {
			break
		}
		start--
	}
	return events[start]
}

// patchSignature mirrors YoloitdStore._patchSignature.
func patchSignature(event RemoteHistoryEvent) string {
	var patch map[string]any
	if len(event.Patch) > 0 {
		if err := decodeUseNumber(event.Patch, &patch); err != nil {
			return ""
		}
	}
	keys := make([]string, 0, len(patch))
	for key := range patch {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return strings.Join(keys, "|")
}

func strPtr(s string) *string { return &s }
