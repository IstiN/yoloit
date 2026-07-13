package main

// Static panel-type catalog mirroring lib/core/remote/yoloitd_panel_catalog.dart.
// Served verbatim by GET /api/boards/:id/panel-types as {"types": [...]}.

var (
	portableLocalPlatforms    = []string{"macos", "linux", "windows", "ios"}
	webPortableLocalPlatforms = []string{"web", "macos", "linux", "windows", "ios"}
	hostLocalPlatforms        = []string{"macos", "linux", "windows"}
	remotePlatforms           = []string{"macos", "linux", "windows", "ios"}
)

type panelTypeDescriptor struct {
	Type                    string
	DisplayName             string
	DefaultWidth            float64
	DefaultHeight           float64
	Actions                 []string
	LocalPlatforms          []string // nil = derived like the Dart default
	RequiresNativeHost      bool
	SupportsRemoteState     bool
	SupportsHeadlessPreview bool
}

// panelTypeDescriptors mirrors yoloitdPanelDescriptors 1:1.
var panelTypeDescriptors = []panelTypeDescriptor{
	{"board.note.markdown", "Markdown Note", 360, 220, []string{"get", "set", "append", "wrap", "nowrap"}, webPortableLocalPlatforms, false, true, true},
	{"board.sticky", "Sticky Note", 260, 220, []string{"get", "set", "append", "color"}, webPortableLocalPlatforms, false, true, true},
	{"board.shape", "Shape / Frame", 300, 220, []string{"get", "set"}, webPortableLocalPlatforms, false, true, true},
	{"board.kanban", "Kanban Board", 640, 420, []string{"columns", "cards", "add-column", "rename-column", "remove-column", "add-card", "move-card", "remove-card", "update-card"}, webPortableLocalPlatforms, false, true, true},
	{"board.webpage", "Webpage", 700, 500, []string{"get", "open"}, webPortableLocalPlatforms, false, true, false},
	{"board.code.snippet", "Code Snippet", 480, 300, []string{"get", "set"}, webPortableLocalPlatforms, false, true, true},
	{"board.checklist", "Checklist", 320, 320, []string{"items", "add", "check", "uncheck", "remove", "rename"}, webPortableLocalPlatforms, false, true, true},
	{"board.files", "Files", 360, 320, []string{"get", "open", "add", "remove", "clear"}, nil, true, true, true},
	{"board.file.preview", "File Preview", 460, 380, []string{"get", "open"}, nil, true, true, true},
	{"board.playlist", "Playlist", 380, 480, []string{"list", "add", "remove", "play", "pause", "stop", "next", "prev"}, nil, true, true, false},
	{"board.audio_recorder", "Audio Recorder", 380, 460, []string{"get", "start", "stop", "list", "set-folder", "set-config", "delete"}, nil, true, true, false},
	{"board.run", "Run", 560, 360, []string{"get", "set-group", "select-session", "clear-session"}, nil, true, true, false},
	{"board.run_configs", "Run Configs", 600, 400, []string{"get", "set-group", "select-session", "clear-session"}, nil, true, true, false},
	{"board.setup_guide", "Setup Guide", 560, 520, []string{"get", "select", "unselect", "set-selected"}, nil, true, true, true},
	{"board.chat", "AI Chat", 420, 500, []string{"messages", "send", "config", "clear", "status"}, webPortableLocalPlatforms, false, true, true},
	{"board.terminal", "Terminal", 520, 360, []string{"config", "set-dir", "set-session"}, nil, true, true, false},
	{"board.filetree", "File Tree", 320, 500, []string{"list", "open", "expand", "collapse", "set-root", "refresh"}, nil, true, true, true},
	{"board.diff.preview", "Diff Preview", 600, 500, []string{"get", "open", "set-root"}, nil, true, true, true},
	{"board.yolo_assistant", "YoLo Assistant", 420, 560, []string{"get", "set-mode", "set-status", "clear"}, nil, true, true, true},
	{"board.widget.custom", "Custom Widget", 360, 420, []string{"get", "set-widget", "set-config", "set"}, webPortableLocalPlatforms, false, true, true},
	{"board.timer", "Timer", 300, 360, []string{"status", "set", "start", "pause", "resume", "reset"}, webPortableLocalPlatforms, false, true, true},
	{"board.calendar", "Calendar", 720, 520, []string{"events", "create-event", "update-event", "delete-event", "set-view"}, webPortableLocalPlatforms, false, true, true},
	{"board.table", "Table", 520, 360, []string{"get", "set", "add-column", "rename-column", "remove-column", "add-row", "update-row", "remove-row", "clear"}, webPortableLocalPlatforms, false, true, true},
	{"board.chart", "Chart", 560, 400, []string{"get", "set-data", "set-type", "set-options", "link-table", "refresh"}, webPortableLocalPlatforms, false, true, true},
	{"board.ui", "UI View", 420, 320, []string{"get", "render", "set-state", "set-scripts"}, webPortableLocalPlatforms, false, true, true},
}

// panelDescriptorFor mirrors yoloitdPanelDescriptorFor.
func panelDescriptorFor(panelType string) *panelTypeDescriptor {
	for i := range panelTypeDescriptors {
		if panelTypeDescriptors[i].Type == panelType {
			return &panelTypeDescriptors[i]
		}
	}
	return nil
}

// capabilitiesMap mirrors descriptor.toJson()['capabilities'].
func capabilitiesMap(d *panelTypeDescriptor) map[string]any {
	local := d.LocalPlatforms
	if local == nil {
		if d.RequiresNativeHost {
			local = hostLocalPlatforms
		} else {
			local = portableLocalPlatforms
		}
	}
	return map[string]any{
		"localPlatforms":          local,
		"remotePlatforms":         remotePlatforms,
		"requiresNativeHost":      d.RequiresNativeHost,
		"supportsRemoteState":     d.SupportsRemoteState,
		"supportsHeadlessPreview": d.SupportsHeadlessPreview,
	}
}

// panelTypes renders the catalog exactly like RemotePanelTypeDescriptor.toJson.
func panelTypes() []map[string]any {
	out := make([]map[string]any, 0, len(panelTypeDescriptors))
	for _, d := range panelTypeDescriptors {
		local := d.LocalPlatforms
		if local == nil {
			if d.RequiresNativeHost {
				local = hostLocalPlatforms
			} else {
				local = portableLocalPlatforms
			}
		}
		out = append(out, map[string]any{
			"type":        d.Type,
			"displayName": d.DisplayName,
			"defaultSize": map[string]any{
				"width":  dartFloat(d.DefaultWidth),
				"height": dartFloat(d.DefaultHeight),
			},
			"actions":      d.Actions,
			"capabilities": capabilitiesMap(&d),
		})
	}
	return out
}
