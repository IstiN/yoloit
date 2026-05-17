import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/ui/widgets/panel_visibility.dart';

/// Persists UI session state across app restarts:
/// - Panel visibility / sizes
/// - Editor & terminal font sizes (zoom)
/// - Last active terminal session index
class SessionPrefs {
  SessionPrefs._();

  // ── Keys ──────────────────────────────────────────────────────────────────
  static const _kReviewVisible      = 'session.reviewVisible';
  static const _kTerminalVisible    = 'session.terminalVisible';
  static const _kWorkspaceWidth     = 'session.workspaceWidth';
  static const _kEditorWidth        = 'session.editorWidth';
  static const _kReviewWidth        = 'session.reviewWidth';
  static const _kAgentsHeight       = 'session.agentsHeight';
  static const _kEditorHeight       = 'session.editorHeight';
  static const _kReviewHeight       = 'session.reviewHeight';
  static const _kEditorFontSize     = 'session.editorFontSize';
  static const _kTerminalFontSize   = 'session.terminalFontSize';
  static const _kActiveTerminalIdx  = 'session.activeTerminalIndex';
  static const _kActiveWorkspaceId  = 'session.activeWorkspaceId';

  // Panel visibility
  static const _kWorkspaceVis = 'panel.workspace.vis';
  static const _kFileTreeVis  = 'panel.filetree.vis';
  static const _kAgentsVis    = 'panel.agents.vis';
  static const _kEditorVis    = 'panel.editor.vis';

  // First-launch / setup
  static const _kSetupCompleted = 'app.setupCompleted';

  // Canvas mode (panes / mindMap / board)
  static const _kCanvasMode = 'shell.canvasMode';

  // Updates
  static const _kAutoUpdateCheck   = 'updates.autoCheck';
  static const _kLastUpdateCheckMs = 'updates.lastCheckMs';
  static const _kSkippedVersion    = 'updates.skippedVersion';

  // Notifications / sounds
  static const _kAgentSoundsEnabled    = 'notifications.agentSounds';
  static const _kApprovalSoundEnabled  = 'notifications.approvalSound';
  static const _kCompletionSoundEnabled = 'notifications.completionSound';

  // Chat context injection
  static const _kInjectCliHelp = 'chat.injectCliHelpOnFirstMessage';

  // ── Load ─────────────────────────────────────────────────────────────────
  static Future<SessionSnapshot> load() async {
    final p = await SharedPreferences.getInstance();
    return SessionSnapshot(
      reviewVisible:      p.getBool(_kReviewVisible)      ?? true,
      terminalVisible:    p.getBool(_kTerminalVisible)    ?? true,
      workspaceWidth:     p.getDouble(_kWorkspaceWidth)   ?? 220.0,
      editorWidth:        p.getDouble(_kEditorWidth)      ?? 480.0,
      reviewWidth:        p.getDouble(_kReviewWidth)      ?? 260.0,
      agentsHeight:       p.getDouble(_kAgentsHeight),
      editorHeight:       p.getDouble(_kEditorHeight),
      reviewHeight:       p.getDouble(_kReviewHeight),
      editorFontSize:     p.getDouble(_kEditorFontSize)   ?? 13.0,
      terminalFontSize:   p.getDouble(_kTerminalFontSize) ?? 13.0,
      activeTerminalIdx:  p.getInt(_kActiveTerminalIdx)   ?? 0,
      activeWorkspaceId:  p.getString(_kActiveWorkspaceId),
      workspaceVis: panelVisibilityFromPrefs(p.getString(_kWorkspaceVis)),
      fileTreeVis:  panelVisibilityFromPrefs(p.getString(_kFileTreeVis)),
      agentsVis:    panelVisibilityFromPrefs(p.getString(_kAgentsVis)),
      editorVis:    panelVisibilityFromPrefs(p.getString(_kEditorVis)),
      canvasMode:   p.getString(_kCanvasMode) ?? 'board',
    );
  }

  // ── Save helpers (individual fields for low-overhead writes) ─────────────
  static Future<void> saveReviewVisible(bool v)        async => (await _p()).setBool(_kReviewVisible, v);
  static Future<void> saveTerminalVisible(bool v)      async => (await _p()).setBool(_kTerminalVisible, v);
  static Future<void> saveWorkspaceWidth(double v)     async => (await _p()).setDouble(_kWorkspaceWidth, v);
  static Future<void> saveEditorWidth(double v)        async => (await _p()).setDouble(_kEditorWidth, v);
  static Future<void> saveReviewWidth(double v)        async => (await _p()).setDouble(_kReviewWidth, v);
  static Future<void> saveAgentsHeight(double? v)      async { final p = await _p(); v == null ? p.remove(_kAgentsHeight) : p.setDouble(_kAgentsHeight, v); }
  static Future<void> saveEditorHeight(double? v)      async { final p = await _p(); v == null ? p.remove(_kEditorHeight) : p.setDouble(_kEditorHeight, v); }
  static Future<void> saveReviewHeight(double? v)      async { final p = await _p(); v == null ? p.remove(_kReviewHeight) : p.setDouble(_kReviewHeight, v); }
  static Future<void> saveEditorFontSize(double v)     async => (await _p()).setDouble(_kEditorFontSize, v);
  static Future<void> saveTerminalFontSize(double v)   async => (await _p()).setDouble(_kTerminalFontSize, v);
  static Future<void> saveActiveTerminalIdx(int v)     async => (await _p()).setInt(_kActiveTerminalIdx, v);
  static Future<void> saveActiveWorkspaceId(String? v) async {
    final p = await _p();
    v == null ? p.remove(_kActiveWorkspaceId) : p.setString(_kActiveWorkspaceId, v);
  }

  static Future<void> savePanelVis(String panelId, PanelVisibility v) async {
    final key = switch (panelId) {
      'workspace' => _kWorkspaceVis,
      'filetree'  => _kFileTreeVis,
      'agents'    => _kAgentsVis,
      'editor'    => _kEditorVis,
      _ => 'panel.$panelId.vis',
    };
    (await _p()).setString(key, v.toPrefsString());
  }

  static Future<void> saveCanvasMode(String mode) async =>
      (await _p()).setString(_kCanvasMode, mode);

  static Future<SharedPreferences> _p() => SharedPreferences.getInstance();

  static Future<bool> isSetupCompleted() async =>
      (await _p()).getBool(_kSetupCompleted) ?? false;

  static Future<void> markSetupCompleted() async =>
      (await _p()).setBool(_kSetupCompleted, true);

  // ── Update prefs ──────────────────────────────────────────────────────────

  static Future<bool> isAutoUpdateCheckEnabled() async =>
      (await _p()).getBool(_kAutoUpdateCheck) ?? true;

  static Future<void> saveAutoUpdateCheckEnabled(bool v) async =>
      (await _p()).setBool(_kAutoUpdateCheck, v);

  static Future<int?> getLastUpdateCheckMs() async =>
      (await _p()).getInt(_kLastUpdateCheckMs);

  static Future<void> saveLastUpdateCheckMs(int ms) async =>
      (await _p()).setInt(_kLastUpdateCheckMs, ms);

  static Future<String?> getSkippedVersion() async =>
      (await _p()).getString(_kSkippedVersion);

  static Future<void> saveSkippedVersion(String v) async =>
      (await _p()).setString(_kSkippedVersion, v);

  // ── Notification / sound prefs ────────────────────────────────────────────

  static Future<bool> isAgentSoundsEnabled() async =>
      (await _p()).getBool(_kAgentSoundsEnabled) ?? true;
  static Future<void> saveAgentSoundsEnabled(bool v) async =>
      (await _p()).setBool(_kAgentSoundsEnabled, v);

  static Future<bool> isApprovalSoundEnabled() async =>
      (await _p()).getBool(_kApprovalSoundEnabled) ?? true;
  static Future<void> saveApprovalSoundEnabled(bool v) async =>
      (await _p()).setBool(_kApprovalSoundEnabled, v);

  static Future<bool> isCompletionSoundEnabled() async =>
      (await _p()).getBool(_kCompletionSoundEnabled) ?? true;
  static Future<void> saveCompletionSoundEnabled(bool v) async =>
      (await _p()).setBool(_kCompletionSoundEnabled, v);

  // ── Chat context injection ────────────────────────────────────────────────

  static Future<bool> isInjectCliHelpEnabled() async =>
      (await _p()).getBool(_kInjectCliHelp) ?? true;

  static Future<void> saveInjectCliHelpEnabled(bool v) async =>
      (await _p()).setBool(_kInjectCliHelp, v);

  // ── Editor tabs (per workspace) ───────────────────────────────────────────

  static Future<void> saveEditorTabs(String workspaceId, List<String> paths, int activeIndex) async {
    final p = await _p();
    await p.setStringList('editor.tabs.$workspaceId', paths);
    await p.setInt('editor.active.$workspaceId', activeIndex);
  }

  static Future<({List<String> paths, int activeIndex})> loadEditorTabs(String workspaceId) async {
    final p = await _p();
    final paths = p.getStringList('editor.tabs.$workspaceId') ?? [];
    final active = p.getInt('editor.active.$workspaceId') ?? 0;
    return (paths: paths, activeIndex: active);
  }

  // ── Preview-mode paths ────────────────────────────────────────────────────

  static const _kPreviewPaths = 'editor.previewPaths';

  static Future<void> savePreviewPaths(List<String> paths) async =>
      (await _p()).setStringList(_kPreviewPaths, paths);

  static Future<Set<String>> loadPreviewPaths() async =>
      ((await _p()).getStringList(_kPreviewPaths) ?? []).toSet();

  // ── File tree expanded paths (per workspace) ──────────────────────────────

  static Future<void> saveExpandedPaths(String workspaceId, List<String> paths) async =>
      (await _p()).setStringList('filetree.expanded.$workspaceId', paths);

  static Future<List<String>> loadExpandedPaths(String workspaceId) async =>
      (await _p()).getStringList('filetree.expanded.$workspaceId') ?? [];
}

/// Immutable snapshot of persisted session state.
class SessionSnapshot {
  const SessionSnapshot({
    required this.reviewVisible,
    required this.terminalVisible,
    required this.workspaceWidth,
    required this.editorWidth,
    required this.reviewWidth,
    this.agentsHeight,
    this.editorHeight,
    this.reviewHeight,
    required this.editorFontSize,
    required this.terminalFontSize,
    required this.activeTerminalIdx,
    this.activeWorkspaceId,
    this.workspaceVis = PanelVisibility.open,
    this.fileTreeVis  = PanelVisibility.open,
    this.agentsVis    = PanelVisibility.open,
    this.editorVis    = PanelVisibility.open,
    this.canvasMode   = 'board',
  });

  final bool reviewVisible;
  final bool terminalVisible;
  final double workspaceWidth;
  final double editorWidth;
  final double reviewWidth;
  final double? agentsHeight;
  final double? editorHeight;
  final double? reviewHeight;
  final double editorFontSize;
  final double terminalFontSize;
  final int activeTerminalIdx;
  final String? activeWorkspaceId;
  final PanelVisibility workspaceVis;
  final PanelVisibility fileTreeVis;
  final PanelVisibility agentsVis;
  final PanelVisibility editorVis;
  /// Last canvas mode: 'panes', 'mindMap', or 'board'.
  final String canvasMode;
}
