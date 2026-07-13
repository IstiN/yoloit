package main

// Wire DTOs mirroring lib/core/remote/yoloitd_models.dart and its generated
// yoloitd_models.g.dart. JSON field names and shapes MUST match the Dart
// models exactly: both yoloitd and yoloit-hub read and write the same
// boards.json / history event files, and Flutter clients parse these shapes.

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math"
	"strconv"
	"time"
)

// dartFloat formats like Dart's double.toString()/jsonEncode: integral values
// keep one decimal ("120.0"), others use the shortest round-trip form.
type dartFloat float64

func (f dartFloat) MarshalJSON() ([]byte, error) {
	return []byte(formatDartFloat(float64(f))), nil
}

func formatDartFloat(v float64) string {
	if v == math.Trunc(v) && math.Abs(v) < 1e16 {
		return strconv.FormatFloat(v, 'f', 1, 64)
	}
	return strconv.FormatFloat(v, 'g', -1, 64)
}

// dartTime mirrors DateTime.toIso8601String() for UTC timestamps:
// 6-digit fraction when microseconds are present, 3-digit for milliseconds
// only, none otherwise, always with a trailing Z.
type dartTime time.Time

func (t dartTime) MarshalJSON() ([]byte, error) {
	u := time.Time(t).UTC()
	base := u.Format("2006-01-02T15:04:05")
	micro := u.Nanosecond() / 1000
	var frac string
	switch {
	case micro%1000 != 0:
		frac = fmt.Sprintf(".%06d", micro)
	case micro != 0:
		frac = fmt.Sprintf(".%03d", micro/1000)
	}
	return []byte(strconv.Quote(base + frac + "Z")), nil
}

// RemoteBoard mirrors the Dart RemoteBoard class. Viewport/links/drawings/
// metadata are free-form JSON decoded with UseNumber so client payloads
// round-trip textually through the store.
type RemoteBoard struct {
	ID       string           `json:"id"`
	Name     string           `json:"name"`
	Viewport map[string]any   `json:"viewport"`
	Panels   []RemotePanel    `json:"panels"`
	Links    []map[string]any `json:"links"`
	Drawings []map[string]any `json:"drawings"`
	Metadata map[string]any   `json:"metadata"`
}

func defaultViewport() map[string]any {
	return map[string]any{
		"scale":       dartFloat(1.0),
		"translation": map[string]any{"dx": dartFloat(0.0), "dy": dartFloat(0.0)},
	}
}

func (b *RemoteBoard) UnmarshalJSON(data []byte) error {
	var raw struct {
		ID       string           `json:"id"`
		Name     string           `json:"name"`
		Viewport map[string]any   `json:"viewport"`
		Panels   []RemotePanel    `json:"panels"`
		Links    []map[string]any `json:"links"`
		Drawings []map[string]any `json:"drawings"`
		Metadata map[string]any   `json:"metadata"`
	}
	if err := decodeUseNumber(data, &raw); err != nil {
		return err
	}
	b.ID = raw.ID
	b.Name = raw.Name
	b.Viewport = raw.Viewport
	if b.Viewport == nil {
		b.Viewport = defaultViewport()
	}
	b.Panels = raw.Panels
	if b.Panels == nil {
		b.Panels = []RemotePanel{}
	}
	b.Links = raw.Links
	if b.Links == nil {
		b.Links = []map[string]any{}
	}
	b.Drawings = raw.Drawings
	if b.Drawings == nil {
		b.Drawings = []map[string]any{}
	}
	b.Metadata = raw.Metadata
	if b.Metadata == nil {
		b.Metadata = map[string]any{}
	}
	return nil
}

// HistoryRevision mirrors Dart's metadata['historyRevision'] ?? 0.
func (b *RemoteBoard) HistoryRevision() int64 {
	return toInt64(b.Metadata["historyRevision"])
}

// Summary mirrors Dart's RemoteBoard.summary(active:).
func (b *RemoteBoard) Summary(active bool) map[string]any {
	defaultFolder, _ := b.Metadata["defaultFolder"].(string)
	return map[string]any{
		"id":            b.ID,
		"name":          b.Name,
		"panelCount":    len(b.Panels),
		"linkCount":     len(b.Links),
		"defaultFolder": trimSpace(defaultFolder),
		"active":        active,
	}
}

func (b *RemoteBoard) Archived() bool {
	archived, _ := b.Metadata["archived"].(bool)
	return archived
}

// RemotePanel mirrors the Dart RemotePanel class, including its fromJson
// defaults and nullable color.
type RemotePanel struct {
	ID     string            `json:"id"`
	Type   string            `json:"type"`
	Title  string            `json:"title"`
	Bounds RemotePanelBounds `json:"bounds"`
	State  map[string]any    `json:"state"`
	Params map[string]any    `json:"params"`
	Color  *int64            `json:"color"`
	ZIndex int64             `json:"zIndex"`
	Hidden bool              `json:"hidden"`
	Locked bool              `json:"locked"`
	Pinned bool              `json:"pinned"`
}

// panelFromMap mirrors _$RemotePanelFromJson: known keys only, Dart defaults
// for missing ones. Returns an error when "bounds" is absent, matching the
// Dart TypeError that surfaces as a 500.
func panelFromMap(m map[string]any) (RemotePanel, error) {
	p := RemotePanel{
		Type:   "board.note.markdown",
		Title:  "Panel",
		State:  map[string]any{},
		Params: map[string]any{},
	}
	if id, ok := m["id"].(string); ok {
		p.ID = id
	}
	if t, ok := m["type"].(string); ok {
		p.Type = t
	}
	if t, ok := m["title"].(string); ok {
		p.Title = t
	}
	boundsRaw, ok := m["bounds"].(map[string]any)
	if !ok {
		return p, fmt.Errorf("type 'Null' is not a subtype of type 'Map<String, dynamic>' in type cast (bounds)")
	}
	p.Bounds = boundsFromMap(boundsRaw)
	if state, ok := m["state"].(map[string]any); ok {
		p.State = state
	}
	if params, ok := m["params"].(map[string]any); ok {
		p.Params = params
	}
	if color, present := m["color"]; present && color != nil {
		c := toInt64(color)
		p.Color = &c
	}
	p.ZIndex = toInt64(m["zIndex"])
	p.Hidden, _ = m["hidden"].(bool)
	p.Locked, _ = m["locked"].(bool)
	p.Pinned, _ = m["pinned"].(bool)
	return p, nil
}

// RemotePanelBounds mirrors the Dart RemotePanelBounds class.
type RemotePanelBounds struct {
	X      dartFloat `json:"x"`
	Y      dartFloat `json:"y"`
	Width  dartFloat `json:"width"`
	Height dartFloat `json:"height"`
}

// boundsFromMap mirrors _$RemotePanelBoundsFromJson defaults.
func boundsFromMap(m map[string]any) RemotePanelBounds {
	return RemotePanelBounds{
		X:      dartFloat(toFloat64(m["x"], 120.0)),
		Y:      dartFloat(toFloat64(m["y"], 120.0)),
		Width:  dartFloat(toFloat64(m["width"], 360.0)),
		Height: dartFloat(toFloat64(m["height"], 240.0)),
	}
}

// RemoteHistoryEvent mirrors the Dart RemoteHistoryEvent class. Before/After/
// Patch are raw JSON so panel snapshots keep their exact encoding
// (patch defaults to {} in Dart, restoresOpId is nullable).
type RemoteHistoryEvent struct {
	OpID         string          `json:"opId"`
	BoardID      string          `json:"boardId"`
	Type         string          `json:"type"`
	EntityType   string          `json:"entityType"`
	EntityID     string          `json:"entityId"`
	ActorID      string          `json:"actorId"`
	Timestamp    dartTime        `json:"timestamp"`
	Revision     int64           `json:"revision"`
	Before       json.RawMessage `json:"before"`
	After        json.RawMessage `json:"after"`
	Patch        json.RawMessage `json:"patch"`
	RestoresOpID *string         `json:"restoresOpId"`
}

// UnmarshalJSON mirrors _$RemoteHistoryEventFromJson, including the
// 'remote' actor fallback from RemoteHistoryEvent.fromJson and the
// `patch ?? const {}` default. Timestamps are Dart ISO-8601 UTC strings.
func (e *RemoteHistoryEvent) UnmarshalJSON(data []byte) error {
	var raw struct {
		OpID         string          `json:"opId"`
		BoardID      string          `json:"boardId"`
		Type         string          `json:"type"`
		EntityType   string          `json:"entityType"`
		EntityID     string          `json:"entityId"`
		ActorID      string          `json:"actorId"`
		Timestamp    string          `json:"timestamp"`
		Revision     int64           `json:"revision"`
		Before       json.RawMessage `json:"before"`
		After        json.RawMessage `json:"after"`
		Patch        json.RawMessage `json:"patch"`
		RestoresOpID *string         `json:"restoresOpId"`
	}
	if err := decodeUseNumber(data, &raw); err != nil {
		return err
	}
	e.OpID = raw.OpID
	e.BoardID = raw.BoardID
	e.Type = raw.Type
	e.EntityType = raw.EntityType
	e.EntityID = raw.EntityID
	e.ActorID = raw.ActorID
	if e.ActorID == "" {
		e.ActorID = "remote"
	}
	if raw.Timestamp != "" {
		parsed, err := time.Parse(time.RFC3339Nano, raw.Timestamp)
		if err != nil {
			return err
		}
		e.Timestamp = dartTime(parsed)
	}
	e.Revision = raw.Revision
	e.Before = raw.Before
	e.After = raw.After
	e.Patch = raw.Patch
	if len(e.Patch) == 0 {
		e.Patch = json.RawMessage(`{}`)
	}
	e.RestoresOpID = raw.RestoresOpID
	return nil
}

// --- JSON helpers ---

// decodeUseNumber decodes JSON keeping numbers as json.Number so arbitrary
// client payloads round-trip without float mangling.
func decodeUseNumber(data []byte, v any) error {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	return dec.Decode(v)
}

// toInt64 mirrors Dart's (num)?.toInt() ?? 0 coercion.
func toInt64(v any) int64 {
	switch n := v.(type) {
	case json.Number:
		if i, err := n.Int64(); err == nil {
			return i
		}
		f, _ := n.Float64()
		return int64(f)
	case float64:
		return int64(n)
	case int64:
		return n
	}
	return 0
}

func toFloat64(v any, fallback float64) float64 {
	switch n := v.(type) {
	case json.Number:
		f, err := n.Float64()
		if err != nil {
			return fallback
		}
		return f
	case float64:
		return n
	}
	return fallback
}

func dartTimeNow() dartTime { return dartTime(time.Now().UTC()) }

// dartISO formats like DateTime.toUtc().toIso8601String().
func dartISO(t time.Time) string {
	data, err := dartTime(t).MarshalJSON()
	if err != nil {
		return ""
	}
	s, err := strconv.Unquote(string(data))
	if err != nil {
		return ""
	}
	return s
}

// panelFromRaw decodes a panel snapshot from a history event's before/after
// payload (always a full RemotePanel JSON object).
func panelFromRaw(raw json.RawMessage) (RemotePanel, error) {
	var m map[string]any
	if err := decodeUseNumber(raw, &m); err != nil {
		return RemotePanel{}, err
	}
	return panelFromMap(m)
}

// rawIsNull reports whether a raw event payload is absent or JSON null.
func rawIsNull(raw json.RawMessage) bool {
	trimmed := bytes.TrimSpace(raw)
	return len(trimmed) == 0 || string(trimmed) == "null"
}
