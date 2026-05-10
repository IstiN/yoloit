import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/collaboration/services/guest_terminal_registry.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';

/// Live xterm view for web/remote guest clients.
///
/// Looks up a persistent [Terminal] instance from [GuestTerminalRegistry]
/// keyed by [nodeId]. Raw PTY bytes arriving over the WebSocket are written
/// into that terminal so rendering is identical to the native client —
/// proper ANSI colors, box-drawing, cursor, scrollback, bold/italic text.
///
/// User keystrokes produced by xterm are forwarded via [onInput] which the
/// enclosing card routes to the host over the `terminal.input` sync message.
class GuestTerminalView extends StatefulWidget {
  const GuestTerminalView({
    super.key,
    required this.nodeId,
    this.onInput,
  });

  final String nodeId;
  final void Function(String data)? onInput;

  @override
  State<GuestTerminalView> createState() => _GuestTerminalViewState();
}

class _GuestTerminalViewState extends State<GuestTerminalView> {
  late final Terminal _terminal;
  late final TerminalController _controller;
  late final FocusNode _focus;

  // Mobile keyboard overlay state
  bool _mobileKbActive = false;
  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _terminal = GuestTerminalRegistry.instance.terminalFor(widget.nodeId);
    _controller = TerminalController();
    _focus = FocusNode(debugLabel: 'guest-terminal-${widget.nodeId}');

    // Forward keystrokes to the host.
    GuestTerminalRegistry.instance.setInputHandler(widget.nodeId, (data) {
      widget.onInput?.call(data);
    });
  }

  @override
  void dispose() {
    GuestTerminalRegistry.instance.removeInputHandler(widget.nodeId);
    _controller.dispose();
    _focus.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _sendInput(String data) => widget.onInput?.call(data);

  void _submitLine(String text) {
    _sendInput(text.isEmpty ? '\r' : '$text\r');
    _inputCtrl.clear();
    _inputFocus.requestFocus();
  }

  void _toggleMobileKb() {
    setState(() => _mobileKbActive = !_mobileKbActive);
    if (_mobileKbActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Grab focus on click so keyboard input goes to the terminal, not the
    // enclosing canvas. Wrapping in ScrollableCardRegion disables canvas
    // pan while the pointer is over the terminal, letting xterm consume
    // two-finger scroll / wheel events for scrollback.
    final colors = context.appColors;
    final terminalWidget = ScrollableCardRegion(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_isMobile) {
            _toggleMobileKb();
          } else {
            _focus.requestFocus();
          }
        },
        child: ColoredBox(
          color: colors.terminalBackground,
          child: TerminalView(
            _terminal,
            controller: _controller,
            focusNode: _focus,
            autofocus: false,
            autoResize: true,
            simulateScroll: true,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            // Bundled monospace font — guarantees identical metrics and full
            // Unicode coverage (cyrillic, CJK, box-drawing) on web and native.
            textStyle: const TerminalStyle(
              fontSize: 13,
              fontFamily: 'JetBrainsMono',
              height: 1.2,
            ),
            theme: _guestTheme,
          ),
        ),
      ),
    );

    if (!_isMobile) return terminalWidget;

    // ── Mobile: wrap terminal with keyboard button + input bar overlay ──────
    return Stack(
      children: [
        // Offset terminal up to make room for input bar when active
        Positioned.fill(
          bottom: _mobileKbActive ? _kInputBarHeight : 0,
          child: terminalWidget,
        ),

        // ⌨ toggle button (top-right corner)
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: _toggleMobileKb,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _mobileKbActive
                    ? const Color(0xFF4B9EFF).withAlpha(200)
                    : colors.surfaceElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _mobileKbActive
                      ? const Color(0xFF4B9EFF)
                      : colors.border,
                ),
              ),
              child: Icon(
                Icons.keyboard,
                size: 14,
                color: _mobileKbActive
                    ? Colors.white
                    : const Color(0xFF6B7898),
              ),
            ),
          ),
        ),

        // Input bar (shown when active)
        if (_mobileKbActive)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _MobileInputBar(
              inputCtrl: _inputCtrl,
              inputFocus: _inputFocus,
              onSend: _submitLine,
              onSpecialKey: _sendInput,
            ),
          ),
      ],
    );
  }

  static const double _kInputBarHeight = 84.0;
}

// ── Mobile input bar ─────────────────────────────────────────────────────────

class _MobileInputBar extends StatelessWidget {
  const _MobileInputBar({
    required this.inputCtrl,
    required this.inputFocus,
    required this.onSend,
    required this.onSpecialKey,
  });

  final TextEditingController inputCtrl;
  final FocusNode inputFocus;
  final void Function(String text) onSend;
  final void Function(String seq) onSpecialKey;

  static const _specialKeys = [
    ('Tab', '\t'),
    ('↑', '\x1b[A'),
    ('↓', '\x1b[B'),
    ('←', '\x1b[D'),
    ('→', '\x1b[C'),
    ('Ctrl+C', '\x03'),
    ('Ctrl+D', '\x04'),
    ('Esc', '\x1b'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Special keys row
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (label, seq) in _specialKeys)
                  GestureDetector(
                    onTap: () => onSpecialKey(seq),
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceElevated,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colors.border),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 11,
                          fontFamily: 'JetBrainsMono',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Text input + send
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: inputCtrl,
                  focusNode: inputFocus,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                    fontFamily: 'JetBrainsMono',
                  ),
                  decoration: InputDecoration(
                    hintText: 'Type command…',
                    hintStyle: const TextStyle(
                      color: Color(0xFF3D4A6B),
                      fontSize: 13,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: colors.terminalBackground,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Color(0xFF4B9EFF),
                        width: 1.5,
                      ),
                    ),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: onSend,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => onSend(inputCtrl.text),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4B9EFF),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '↵',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dark theme that approximates the native macOS Terminal experience.
const TerminalTheme _guestTheme = TerminalTheme(
  cursor: Color(0xFFE0E0E0),
  selection: Color(0x554B9EFF),
  foreground: Color(0xFFE6E6E6),
  background: Color(0xFF0A0A0F),
  black: Color(0xFF000000),
  red: Color(0xFFCC6666),
  green: Color(0xFFB5BD68),
  yellow: Color(0xFFF0C674),
  blue: Color(0xFF81A2BE),
  magenta: Color(0xFFB294BB),
  cyan: Color(0xFF8ABEB7),
  white: Color(0xFFC5C8C6),
  brightBlack: Color(0xFF666666),
  brightRed: Color(0xFFD54E53),
  brightGreen: Color(0xFFB9CA4A),
  brightYellow: Color(0xFFE7C547),
  brightBlue: Color(0xFF7AA6DA),
  brightMagenta: Color(0xFFC397D8),
  brightCyan: Color(0xFF70C0B1),
  brightWhite: Color(0xFFEAEAEA),
  searchHitBackground: Color(0xFFAAAAAA),
  searchHitBackgroundCurrent: Color(0xFFFFFF00),
  searchHitForeground: Color(0xFF000000),
);
