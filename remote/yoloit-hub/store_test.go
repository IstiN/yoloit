package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestStoreInitSeedsDefaultBoard(t *testing.T) {
	dataDir := t.TempDir()
	store := NewStore(dataDir, "actor")
	if err := store.Init(); err != nil {
		t.Fatalf("init: %v", err)
	}
	boards, err := store.LoadBoards()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(boards) != 1 || boards[0].Name != "Remote Board" {
		t.Fatalf("seeded boards: %v", boards)
	}
	active, err := store.ActiveBoardID()
	if err != nil {
		t.Fatalf("active: %v", err)
	}
	if active != boards[0].ID {
		t.Fatalf("active %q, want %q", active, boards[0].ID)
	}
}

func TestStoreAtomicRoundTrip(t *testing.T) {
	dataDir := t.TempDir()
	store := NewStore(dataDir, "actor")
	if err := store.Init(); err != nil {
		t.Fatalf("init: %v", err)
	}
	first, err := store.CreateBoard("Second")
	if err != nil {
		t.Fatalf("create: %v", err)
	}

	reloaded := NewStore(dataDir, "actor")
	boards, err := reloaded.LoadBoards()
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	if len(boards) != 2 {
		t.Fatalf("reloaded %d boards, want 2", len(boards))
	}
	if boards[1].ID != first.ID || boards[1].Name != "Second" {
		t.Fatalf("round-trip mismatch: %+v", boards[1])
	}
	// boards.json is a top-level JSON array, like yoloitd writes it.
	raw, err := os.ReadFile(filepath.Join(dataDir, "boards.json"))
	if err != nil {
		t.Fatalf("read boards.json: %v", err)
	}
	var asArray []map[string]any
	if err := json.Unmarshal(raw, &asArray); err != nil {
		t.Fatalf("boards.json is not a JSON array: %v", err)
	}
	if len(asArray) != 2 {
		t.Fatalf("boards.json entries: %d", len(asArray))
	}
	// No temp files left behind by atomic writes.
	leftovers, err := filepath.Glob(filepath.Join(dataDir, "*.tmp"))
	if err != nil || len(leftovers) != 0 {
		t.Fatalf("temp leftovers: %v (err %v)", leftovers, err)
	}
	// Atomic writes are indented for human diffing, like the Dart store.
	if !strings.Contains(string(raw), "\n  ") {
		t.Fatal("boards.json is not indented like yoloitd writes it")
	}
}

func TestStoreFindBoardFallbacks(t *testing.T) {
	dataDir := t.TempDir()
	store := NewStore(dataDir, "actor")
	if err := store.Init(); err != nil {
		t.Fatal(err)
	}
	board, _ := store.CreateBoard("Target Board")

	byID, err := store.FindBoard(board.ID)
	if err != nil || byID == nil || byID.ID != board.ID {
		t.Fatalf("find by id: %v %v", byID, err)
	}
	byName, err := store.FindBoard("target board")
	if err != nil || byName == nil || byName.ID != board.ID {
		t.Fatalf("find by case-insensitive name: %v %v", byName, err)
	}
	// Use a prefix long enough to distinguish from the seeded default board
	// (ids share the "board-<epoch>" head; Dart likewise returns the first
	// prefix match).
	prefix := board.ID[:len(board.ID)-2]
	byPrefix, err := store.FindBoard(prefix)
	if err != nil || byPrefix == nil || byPrefix.ID != board.ID {
		t.Fatalf("find by id prefix: %v %v", byPrefix, err)
	}
	missing, err := store.FindBoard("nope")
	if err != nil || missing != nil {
		t.Fatalf("find missing: %v %v", missing, err)
	}
}

func TestStoreUpdateBoardRevisionAndHistory(t *testing.T) {
	dataDir := t.TempDir()
	store := NewStore(dataDir, "actor")
	if err := store.Init(); err != nil {
		t.Fatal(err)
	}
	boards, _ := store.LoadBoards()
	boardID := boards[0].ID

	before, after, err := store.UpdateBoard(boardID, func(b *RemoteBoard) {
		b.Panels = append(b.Panels, RemotePanel{
			ID:     "p-1",
			Type:   "board.note.markdown",
			Title:  "T",
			Bounds: RemotePanelBounds{X: 1, Y: 2, Width: 3, Height: 4},
			State:  map[string]any{},
			Params: map[string]any{},
		})
	}, func(b, a *RemoteBoard, revision int64) *RemoteHistoryEvent {
		return &RemoteHistoryEvent{
			OpID:       nextID("op"),
			BoardID:    boardID,
			Type:       "panel.created",
			EntityType: "panel",
			EntityID:   "p-1",
			ActorID:    store.ActorID,
			Timestamp:  dartTimeNow(),
			Revision:   revision,
			Patch:      json.RawMessage(`{}`),
		}
	})
	if err != nil {
		t.Fatalf("update: %v", err)
	}
	if before.HistoryRevision() != 0 || after.HistoryRevision() != 1 {
		t.Fatalf("revisions: before=%d after=%d", before.HistoryRevision(), after.HistoryRevision())
	}

	// No-op update must not bump the revision.
	_, after2, err := store.UpdateBoard(boardID, func(b *RemoteBoard) {}, func(b, a *RemoteBoard, revision int64) *RemoteHistoryEvent {
		t.Fatal("historyEvent must not fire for a no-op update")
		return nil
	})
	if err != nil {
		t.Fatalf("no-op update: %v", err)
	}
	if after2.HistoryRevision() != 1 {
		t.Fatalf("no-op update bumped revision to %d", after2.HistoryRevision())
	}
}

func TestStoreDeleteBoardActiveFallback(t *testing.T) {
	dataDir := t.TempDir()
	store := NewStore(dataDir, "actor")
	if err := store.Init(); err != nil {
		t.Fatal(err)
	}
	second, _ := store.CreateBoard("Second")

	// Deleting the active board falls back to the first remaining one.
	if err := store.DeleteBoard(second.ID); err != nil {
		t.Fatalf("delete: %v", err)
	}
	active, err := store.ActiveBoardID()
	if err != nil {
		t.Fatalf("active: %v", err)
	}
	boards, _ := store.LoadBoards()
	if len(boards) != 1 || active != boards[0].ID {
		t.Fatalf("after delete: boards=%d active=%q", len(boards), active)
	}
}

func TestSafeSegment(t *testing.T) {
	if got := safeSegment("board-123/weird name"); got != "board-123_weird_name" {
		t.Fatalf("safeSegment: %q", got)
	}
}

func TestNextIDUniqueUnderContention(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 1000; i++ {
		id := nextID("board")
		if seen[id] {
			t.Fatalf("duplicate id %q", id)
		}
		seen[id] = true
		if !strings.HasPrefix(id, "board-") {
			t.Fatalf("id prefix: %q", id)
		}
	}
}
