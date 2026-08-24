import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/terminal/data/terminal_backend_service.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';

/// UI bridge: terminal panel widgets register their "open full view"
/// capability so non-UI layers (CLI handlers) can trigger it by panel id.
class BoardTerminalFullViewBridge {
  BoardTerminalFullViewBridge._();

  static final _openers = <String, VoidCallback>{};

  static void register(String panelId, VoidCallback open) {
    _openers[panelId] = open;
  }

  static void unregister(String panelId) {
    _openers.remove(panelId);
  }

  /// Opens the full view for [panelId]. Returns false when the panel widget
  /// is not currently mounted (hidden board, deleted panel).
  static bool open(String panelId) {
    final opener = _openers[panelId];
    if (opener == null) return false;
    opener();
    return true;
  }
}

/// A single terminal tab in the fullscreen view — one live terminal panel
/// from the board the view was opened on.
class BoardTerminalFullViewTab {
  const BoardTerminalFullViewTab({
    required this.panelId,
    required this.title,
    required this.session,
  });

  final String panelId;
  final String title;
  final AgentSession session;
}

/// Modern fullscreen terminal view: the terminal fills the whole screen, a
/// tab bar on top lists every live terminal of the current board (the one
/// the view was opened from is selected), and pinch-to-zoom (touch or
/// trackpad) changes the font size via the gesture handling already built
/// into [TerminalWidget].
///
/// A collapsible debug pane (hidden by default) keeps the diagnostics that
/// the previous fixed-size debug dialog exposed.
class BoardTerminalFullView extends StatefulWidget {
  const BoardTerminalFullView({
    required this.session,
    required this.title,
    this.tabs,
    this.debugLabel,
    super.key,
  });

  /// The session that is selected when the view opens.
  final AgentSession session;

  /// Title of the opening tab — used when [tabs] is not provided.
  final String title;

  /// All live terminal sessions of the board, shown as tabs on top. When
  /// null or empty a single tab is derived from [session] and [title].
  final List<BoardTerminalFullViewTab>? tabs;

  final String? debugLabel;

  @override
  State<BoardTerminalFullView> createState() => _BoardTerminalFullViewState();
}

class _BoardTerminalFullViewState extends State<BoardTerminalFullView> {
  final _termKeys = <String, GlobalKey<TerminalWidgetState>>{};
  final _logScroll = ScrollController();
  final _logs = <String>[];

  bool _controlsVisible = true;
  bool _debugVisible = false;
  bool _forceAltScrollKeys = false;
  Timer? _hideTimer;

  static const _autoHideDelay = Duration(seconds: 3);

  late final List<BoardTerminalFullViewTab> _tabs =
      widget.tabs != null && widget.tabs!.isNotEmpty
          ? widget.tabs!
          : [
            BoardTerminalFullViewTab(
              panelId: '',
              title: widget.title,
              session: widget.session,
            ),
          ];

  late int _activeIndex = () {
    final index = _tabs.indexWhere(
      (tab) => tab.session.id == widget.session.id,
    );
    return index < 0 ? 0 : index;
  }();

  AgentSession get _activeSession => _tabs[_activeIndex].session;

  GlobalKey<TerminalWidgetState> get _termKey => _termKeys.putIfAbsent(
    _activeSession.id,
    () => GlobalKey<TerminalWidgetState>(),
  );

  /// The native macOS traffic lights float over the fullscreen content, so
  /// the top bar keeps clear of them (same inset as the app title bar).
  static bool get _hasMacOSTrafficLights {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _logScroll.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_autoHideDelay, () {
      if (mounted && !_debugVisible) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _pokeControls() {
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    _scheduleHide();
  }

  void _addLog(String msg) {
    if (!_debugVisible) return;
    final now = DateTime.now().toIso8601String().substring(11, 23);
    setState(() {
      _logs.add('$now $msg');
      if (_logs.length > 400) _logs.removeAt(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScroll.hasClients) return;
      _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
    });
  }

  String _escapeForLog(String data) {
    return data
        .replaceAll('\x1B', r'\e')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\x02', r'\x02');
  }

  void _writePty(String sessionId, String data) {
    if (_debugVisible) {
      _addLog('pty[$sessionId] "${_escapeForLog(data)}"');
    }
    TerminalBackendService.instance.write(sessionId, data);
  }

  void _send(String seq, String label) {
    _addLog('send $label bytes="${_escapeForLog(seq)}"');
    _termKey.currentState?.writeToPty(seq);
  }

  void _changeFontSize(double delta) {
    final state = _termKey.currentState;
    if (state == null) return;
    setState(() => state.setFontSize(state.currentFontSize + delta));
    _pokeControls();
  }

  void _selectTab(int index) {
    if (index == _activeIndex || index < 0 || index >= _tabs.length) return;
    // Carry the current font size over to the newly bound tab so pinch /
    // button zoom survives tab switches.
    final fontSize = _termKey.currentState?.currentFontSize;
    setState(() => _activeIndex = index);
    if (fontSize != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _termKey.currentState?.setFontSize(fontSize);
      });
    }
    _pokeControls();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.terminalBackground,
      child: MouseRegion(
        onHover: (_) => _pokeControls(),
        child: Stack(
          children: [
            Positioned.fill(
              child: TerminalWidget(
                key: _termKey,
                session: _activeSession,
                isActive: true,
                debugLabel: widget.debugLabel,
                debugForceAltScrollKeyFallback: _forceAltScrollKeys,
                debugLogSink: (message) => _addLog('scroll $message'),
                terminalOutputWriter: _writePty,
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: _buildTopBar(),
                ),
              ),
            ),
            if (_debugVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 240,
                child: _buildDebugPane(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final colors = context.appColors;
    final fontSize = _termKey.currentState?.currentFontSize ?? 13.0;
    return Container(
      padding: EdgeInsets.only(
        left: _hasMacOSTrafficLights ? 82 : 12,
        right: 12,
        top: 10,
        bottom: 10,
      ),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(235),
        border: Border(bottom: BorderSide(color: colors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.terminal, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _tabs.length; i++) _buildTab(i, colors),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _barButton(
            tooltip: 'Decrease font size',
            icon: Icons.remove,
            onPressed: () => _changeFontSize(-1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              fontSize.toStringAsFixed(0),
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ),
          _barButton(
            tooltip: 'Increase font size',
            icon: Icons.add,
            onPressed: () => _changeFontSize(1),
          ),
          const SizedBox(width: 4),
          _barButton(
            tooltip: _debugVisible ? 'Hide debug pane' : 'Show debug pane',
            icon: Icons.bug_report,
            onPressed: () {
              setState(() => _debugVisible = !_debugVisible);
              _pokeControls();
            },
          ),
          const SizedBox(width: 4),
          _barButton(
            tooltip: 'Close full view',
            icon: Icons.close,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(int index, AppColorScheme colors) {
    final tab = _tabs[index];
    final selected = index == _activeIndex;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tab.title,
        child: GestureDetector(
          onTap: () => _selectTab(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color:
                  selected
                      ? colors.accentGreen.withAlpha(30)
                      : colors.surfaceElevated.withAlpha(120),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? colors.accentGreen : colors.border,
                width: selected ? 1 : 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(
                    Icons.circle,
                    size: 6,
                    color: colors.accentGreen,
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    tab.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          selected ? colors.textPrimary : colors.textSecondary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _barButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 16, color: context.appColors.textSecondary),
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }

  Widget _buildDebugPane() {
    final colors = context.appColors;
    final terminal = _activeSession.terminal;
    final state = _termKey.currentState;
    final debugState =
        state?.debugStateSummary ??
        'alt=${terminal.isUsingAltBuffer} '
            'mouse=${terminal.mouseMode} '
            'altScroll=${terminal.altBufferMouseScrollMode} '
            'buf=${terminal.buffer.height} '
            'lines=${terminal.lines.length}';

    return Container(
      color: colors.background.withAlpha(240),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  debugState,
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
              ),
              _barButton(
                tooltip: 'Dump terminal state',
                icon: Icons.bug_report,
                onPressed: () => _addLog('state $debugState'),
              ),
              _barButton(
                tooltip: 'Copy logs',
                icon: Icons.copy,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _logs.join('\n')));
                  _addLog('copied ${_logs.length} log lines');
                },
              ),
              _barButton(
                tooltip: 'Clear logs',
                icon: Icons.clear_all,
                onPressed: () => setState(_logs.clear),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _debugButton('PgUp', () => _send('\x1B[5~', 'PgUp')),
              _debugButton('PgDn', () => _send('\x1B[6~', 'PgDn')),
              _debugButton('↑', () => _send('\x1B[A', 'Up')),
              _debugButton('↓', () => _send('\x1B[B', 'Down')),
              _debugButton('Copy', () => _send('\x02[', 'CopyMode')),
              _debugButton('Exit', () => _send('q', 'ExitCopy')),
              _debugButton(
                'MouseOn',
                () => _send('\x1B[?1000h\x1B[?1002h\x1B[?1006h', 'MouseOn'),
              ),
              _debugButton(
                'MouseOff',
                () => _send('\x1B[?1000l\x1B[?1002l\x1B[?1006l', 'MouseOff'),
              ),
              _debugButton('NormBuf', () => _send('\x1B[?1049l', 'NormBuf')),
              _debugButton('AltBuf', () => _send('\x1B[?1049h', 'AltBuf')),
              _debugButton(
                _forceAltScrollKeys ? 'ForceKeysOn' : 'ForceKeysOff',
                () {
                  setState(() {
                    _forceAltScrollKeys = !_forceAltScrollKeys;
                    _addLog('forceAltScrollKeys=$_forceAltScrollKeys');
                  });
                },
              ),
              _debugButton('Wheel↑', () => _simulateWheel(-50)),
              _debugButton('Wheel↓', () => _simulateWheel(50)),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              controller: _logScroll,
              itemCount: _logs.length,
              itemBuilder:
                  (_, i) => Text(
                    _logs[i],
                    style: TextStyle(
                      color: colors.accentGreen,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _debugButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  void _simulateWheel(double dy) {
    GestureBinding.instance.handlePointerEvent(
      PointerScrollEvent(
        device: 0,
        position: Offset.zero,
        scrollDelta: Offset(0, dy),
      ),
    );
    _addLog('sim scroll $dy');
  }
}
