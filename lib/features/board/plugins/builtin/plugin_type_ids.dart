/// Stable type identifiers for all built-in board panel plugins.
///
/// Keeping these as pure constants avoids pulling in plugin implementations
/// (and their native dependencies) just to compare or create panel types.
/// Plugin classes should reference these constants rather than hard-coding ids.
library;

// ── Content / productivity panels ───────────────────────────────────────────
const String kMarkdownNotePluginTypeId = 'board.note.markdown';
const String kStickyNotePluginTypeId = 'board.note.sticky';
const String kShapePluginTypeId = 'board.shape';
const String kKanbanPluginTypeId = 'board.kanban';
const String kCodeSnippetPluginTypeId = 'board.code_snippet';
const String kChecklistPluginTypeId = 'board.checklist';
const String kCalendarPluginTypeId = 'board.calendar';
const String kTablePluginTypeId = 'board.table';
const String kChartPluginTypeId = 'board.chart';
const String kSetupGuidePluginTypeId = 'board.setup_guide';
const String kTimerPluginTypeId = 'board.timer';

// ── External / web panels ───────────────────────────────────────────────────
const String kWebpagePluginTypeId = 'board.webpage';

// ── Native desktop-only panels ──────────────────────────────────────────────
const String kFilesPluginTypeId = 'board.files';
const String kFilePreviewPluginTypeId = 'board.file.preview';
const String kFileTreePluginTypeId = 'board.filetree';
const String kDiffPreviewPluginTypeId = 'board.diff.preview';
const String kPlaylistPluginTypeId = 'board.playlist';
const String kAudioRecorderPluginTypeId = 'board.audio_recorder';
const String kRunPluginTypeId = 'board.run';
const String kRunConfigsPluginTypeId = 'board.run_configs';
const String kTerminalPluginTypeId = 'board.terminal';

// ── AI / agent panels ───────────────────────────────────────────────────────
const String kChatPluginTypeId = 'board.chat';
const String kYoloAssistantPluginTypeId = 'board.yolo_assistant';
const String kCustomWidgetPluginTypeId = 'board.widget.custom';
const String kUiViewPluginTypeId = 'board.ui';
