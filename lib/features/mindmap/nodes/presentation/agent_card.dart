import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';
import 'package:yoloit/ui/components/feedback/status_dot.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

/// Presentation agent/terminal card — shared shell used by both macOS and web.
/// Web falls back to styled text lines; macOS can inject a live terminal body.
class AgentCard extends StatefulWidget {
  const AgentCard({
    super.key,
    required this.props,
    this.body,
    this.onTerminalInput,
    this.onSessionStart,
  });
  final AgentCardProps props;
  final Widget? body;
  final void Function(String data)? onTerminalInput;
  final VoidCallback? onSessionStart;

  @override
  State<AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends State<AgentCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _glowAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));
    if (widget.props.isRunning) _animCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(AgentCard old) {
    super.didUpdateWidget(old);
    _updateAnimation();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(AppColorScheme colors) => switch (widget.props.status) {
    'live' => colors.accentGreen,
    'error' => colors.accentRed,
    _ => colors.accentBlue,
  };

  Color _phaseColor(AppColorScheme colors) {
    final phase = widget.props.hookPhase;
    return switch (phase) {
      null => _statusColor(colors),
      ThinkingPhase() => colors.accentOrange,
      ToolPhase() => colors.primaryLight,
      AwaitingApprovalPhase() => colors.accentOrange,
      DonePhase() => colors.accentGreen,
      ErrorPhase() => colors.accentRed,
    };
  }

  Duration get _animDuration {
    return switch (widget.props.hookPhase) {
      ThinkingPhase() => const Duration(milliseconds: 700),
      ToolPhase() => const Duration(milliseconds: 500),
      AwaitingApprovalPhase() => const Duration(milliseconds: 350),
      DonePhase() => const Duration(milliseconds: 400),
      _ => const Duration(milliseconds: 1800),
    };
  }

  void _updateAnimation() {
    final shouldAnimate = widget.props.hookPhase != null;
    if (_animCtrl.duration != _animDuration) {
      _animCtrl.duration = _animDuration;
    }
    if (shouldAnimate && !_animCtrl.isAnimating) {
      _animCtrl.repeat(reverse: true);
    } else if (!shouldAnimate && _animCtrl.isAnimating) {
      _animCtrl.stop();
      _animCtrl.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isRunning = widget.props.isRunning;
    final color = _phaseColor(colors);
    final phase = widget.props.hookPhase;
    final isActive = phase != null;

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (_, child) {
        final glowAlpha =
            isActive
                ? ((_glowAnim.value * 100 + 40).round()).clamp(40, 140)
                : 60;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: color.withAlpha(glowAlpha), width: 1.5),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              if (isActive)
                BoxShadow(
                  color: color.withAlpha((_glowAnim.value * 60 + 10).round()),
                  blurRadius: phase is ThinkingPhase ? 24 : 16,
                  spreadRadius: phase is ThinkingPhase ? 2 : 1,
                ),
              BoxShadow(
                color: colors.background.withAlpha(144),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          _AgentCardHeader(
            props: widget.props,
            color: color,
            isRunning: isRunning,
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child:
                      widget.body ??
                      (widget.props.isIdle
                          ? _IdlePlaceholder(onStart: widget.onSessionStart)
                          : _TerminalPane(
                            lines: widget.props.lastLines,
                            onInput: widget.onTerminalInput,
                          )),
                ),
                if (phase != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _HookPhaseBar(
                      phase: phase,
                      color: color,
                      animation: _glowAnim,
                    ),
                  ),
              ],
            ),
          ),
          if (isActive) _ActivityStripes(animation: _glowAnim, color: color),
        ],
      ),
    );
  }
}

class _HookPhaseBar extends StatelessWidget {
  const _HookPhaseBar({
    required this.phase,
    required this.color,
    required this.animation,
  });
  final AgentPhase phase;
  final Color color;
  final Animation<double> animation;

  String get _label => switch (phase) {
    ThinkingPhase() => '● Thinking…',
    ToolPhase(:final toolName) => '⚙ $toolName',
    AwaitingApprovalPhase() => '⚠ Waiting for approval',
    DonePhase() => '✓ Done',
    ErrorPhase() => '✕ Error',
  };

  bool get _showDots =>
      phase is ThinkingPhase ||
      phase is ToolPhase ||
      phase is AwaitingApprovalPhase;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: animation,
      builder:
          (_, __) => Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Color.lerp(
                colors.surfaceElevated,
                color,
                0.15 + animation.value * 0.08,
              ),
              border: Border(
                bottom: BorderSide(color: color.withAlpha(80), width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Text(
                  _label,
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                if (_showDots)
                  _DotsIndicator(animation: animation, color: color),
              ],
            ),
          ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  const _DotsIndicator({required this.animation, required this.color});
  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final pulseColor = Color.lerp(colors.surface, color, 1)!;
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final v = animation.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pulseColor.withAlpha(
                    ((v - i * 0.15).clamp(0.1, 1.0) * 200).round(),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: pulseColor.withAlpha(80),
                      blurRadius: 3,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AgentCardHeader extends StatelessWidget {
  const _AgentCardHeader({
    required this.props,
    required this.color,
    required this.isRunning,
  });
  final AgentCardProps props;
  final Color color;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border(bottom: BorderSide(color: colors.divider, width: 1)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              StatusDot(
                color: color,
                isActive: isRunning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      props.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (props.typeName.isNotEmpty)
                      Text(
                        props.typeName,
                        style: TextStyle(
                          fontSize: 9,
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.terminal, size: 13, color: colors.accentGreen),
            ],
          ),
          if (props.repos.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final r in props.repos)
                  RepoBranchPill(repo: r.repo, branch: r.branch),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TerminalPane extends StatefulWidget {
  const _TerminalPane({required this.lines, this.onInput});
  final List<String> lines;
  final void Function(String data)? onInput;

  @override
  State<_TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<_TerminalPane> {
  late final FocusNode _focusNode;

  bool get _interactive => widget.onInput != null;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'agent-card-terminal')
      ..addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  void _send(String data) {
    if (data.isEmpty) return;
    widget.onInput?.call(data);
  }

  Future<void> _pasteClipboard() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text;
    if (text == null || text.isEmpty) return;
    _send(text);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!_interactive) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final isMeta = keyboard.isMetaPressed;
    final isCtrl = keyboard.isControlPressed;
    final isAlt = keyboard.isAltPressed;
    final isShift = keyboard.isShiftPressed;

    if ((isMeta || isCtrl) && !isAlt && key == LogicalKeyboardKey.keyV) {
      unawaited(_pasteClipboard());
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter) {
      _send(isShift && !isMeta && !isCtrl && !isAlt ? '\x1b\r' : '\r');
      return KeyEventResult.handled;
    }

    if (isMeta && key == LogicalKeyboardKey.backspace) {
      _send('\x15');
      return KeyEventResult.handled;
    }

    if ((isAlt || isCtrl) && key == LogicalKeyboardKey.backspace) {
      _send('\x17');
      return KeyEventResult.handled;
    }

    if (isMeta && key == LogicalKeyboardKey.arrowLeft) {
      _send('\x01');
      return KeyEventResult.handled;
    }

    if (isMeta && key == LogicalKeyboardKey.arrowRight) {
      _send('\x05');
      return KeyEventResult.handled;
    }

    if (isAlt && key == LogicalKeyboardKey.arrowLeft) {
      _send('\x1bb');
      return KeyEventResult.handled;
    }

    if (isAlt && key == LogicalKeyboardKey.arrowRight) {
      _send('\x1bf');
      return KeyEventResult.handled;
    }

    if (isMeta && key == LogicalKeyboardKey.keyK) {
      _send('\x0c');
      return KeyEventResult.handled;
    }

    final special = _specialSequenceFor(key);
    if (special != null) {
      _send(special);
      return KeyEventResult.handled;
    }

    if (isCtrl && !isMeta) {
      final control = _controlSequenceFor(key);
      if (control != null) {
        _send(control);
        return KeyEventResult.handled;
      }
    }

    final character = event.character;
    if (character != null &&
        character.isNotEmpty &&
        !isMeta &&
        !isCtrl &&
        character != '\u0000') {
      _send(isAlt ? '\x1b$character' : character);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  static String? _specialSequenceFor(LogicalKeyboardKey key) {
    return switch (key) {
      LogicalKeyboardKey.backspace => '\x7f',
      LogicalKeyboardKey.tab => '\t',
      LogicalKeyboardKey.escape => '\x1b',
      LogicalKeyboardKey.arrowUp => '\x1b[A',
      LogicalKeyboardKey.arrowDown => '\x1b[B',
      LogicalKeyboardKey.arrowRight => '\x1b[C',
      LogicalKeyboardKey.arrowLeft => '\x1b[D',
      LogicalKeyboardKey.home => '\x1b[H',
      LogicalKeyboardKey.end => '\x1b[F',
      LogicalKeyboardKey.delete => '\x1b[3~',
      LogicalKeyboardKey.pageUp => '\x1b[5~',
      LogicalKeyboardKey.pageDown => '\x1b[6~',
      _ => null,
    };
  }

  static String? _controlSequenceFor(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.space) return '\x00';

    final label = key.keyLabel;
    if (label.length == 1) {
      final code = label.toUpperCase().codeUnitAt(0);
      if (code >= 65 && code <= 90) {
        return String.fromCharCode(code - 64);
      }
    }

    return switch (key) {
      LogicalKeyboardKey.bracketLeft => '\x1b',
      LogicalKeyboardKey.backslash => '\x1c',
      LogicalKeyboardKey.bracketRight => '\x1d',
      LogicalKeyboardKey.minus => '\x1f',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final lines = _TerminalLines(lines: widget.lines);
    if (!_interactive) return lines;

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focusNode.requestFocus,
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: _onKeyEvent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              lines,
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _focusNode.hasFocus ? 1 : 0,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: colors.accentBlue.withAlpha(150),
                          width: 1.2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalLines extends StatelessWidget {
  const _TerminalLines({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (lines.isEmpty) {
      return const Center(
        child: Caption('No output'),
      );
    }
    return Container(
      color: colors.terminalBackground,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ListView.builder(
        physics: const ClampingScrollPhysics(),
        itemCount: lines.length,
        itemBuilder:
            (_, i) => Text(
              lines[i],
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                color: colors.terminalText,
                height: 1.4,
              ),
              overflow: TextOverflow.fade,
              softWrap: false,
            ),
      ),
    );
  }
}

class _IdlePlaceholder extends StatelessWidget {
  const _IdlePlaceholder({this.onStart});
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: colors.terminalBackground,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.power_settings_new,
                size: 14,
                color: colors.textPrimary.withAlpha(140),
              ),
              const SizedBox(width: 6),
              Text(
                'Saved session',
                style: TextStyle(
                  color: colors.textPrimary.withAlpha(180),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'PTY not running. Click to start terminal.',
            style: TextStyle(
              color: colors.textPrimary.withAlpha(110),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 10),
          if (onStart != null)
            SizedBox(
              height: 26,
              child: ElevatedButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow, size: 14),
                label: const Text('Start', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accentGreen.withAlpha(40),
                  foregroundColor: colors.accentGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(color: colors.accentGreen.withAlpha(80)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityStripes extends StatelessWidget {
  const _ActivityStripes({required this.animation, required this.color});
  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final stripeColor = Color.lerp(colors.surface, color, 1)!;
    return AnimatedBuilder(
      animation: animation,
      builder:
          (_, __) => Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  stripeColor.withAlpha(0),
                  stripeColor.withAlpha(180),
                  stripeColor.withAlpha(0),
                ],
                stops: [
                  (animation.value - 0.5).clamp(0.0, 1.0),
                  animation.value,
                  (animation.value + 0.5).clamp(0.0, 1.0),
                ],
              ),
            ),
          ),
    );
  }
}

/// Repo + branch pill used in agent card headers.
class RepoBranchPill extends StatelessWidget {
  const RepoBranchPill({super.key, required this.repo, required this.branch});
  final String repo;
  final String branch;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colors.surfaceHighlight,
          border: Border.all(color: colors.border, width: 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 9, color: colors.primaryLight),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                repo,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: colors.terminalText,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 5),
            Icon(Icons.alt_route, size: 9, color: colors.primary),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                branch,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  color: colors.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
