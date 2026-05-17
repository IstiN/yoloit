import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

class TimerPlugin extends BoardPanelPlugin {
  const TimerPlugin();

  static const String kTypeId = 'board.timer';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Timer';

  @override
  IconData get icon => Icons.timer_outlined;

  @override
  Color get accentColor => const Color(0xFF3B82F6);

  @override
  Size get defaultSize => const Size(300, 360);

  @override
  Map<String, dynamic> get initialState => {
    'duration': 300,
    'remaining': 300,
    'isRunning': false,
    'isPaused': false,
    'completed': false,
    'label': '',
    'lastTick': 0,
  };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _TimerContent(panel: panel, renderContext: renderContext);
  }
}

// ─── Timer Content Widget ─────────────────────────────────────────────────────

class _TimerContent extends StatefulWidget {
  const _TimerContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_TimerContent> createState() => _TimerContentState();
}

class _TimerContentState extends State<_TimerContent>
    with SingleTickerProviderStateMixin {
  static const Color _accent = Color(0xFF3B82F6);
  static const Color _completedColor = Color(0xFF10B981);
  static const Color _warningColor = Color(0xFFF59E0B);

  static const List<int> _quickTimers = [1, 5, 15, 25, 45, 60];

  Timer? _tickTimer;
  late AnimationController _pulseCtrl;

  int _remaining = 300;
  int _duration = 300;
  bool _isRunning = false;
  bool _isPaused = false;
  bool _completed = false;
  String _label = '';
  bool _soundPlayed = false;

  // Edit mode
  bool _editing = false;
  final _minutesCtrl = TextEditingController(text: '5');
  final _secondsCtrl = TextEditingController(text: '00');
  final _labelCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _syncState();
  }

  @override
  void didUpdateWidget(_TimerContent old) {
    super.didUpdateWidget(old);
    _syncState();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _pulseCtrl.dispose();
    _minutesCtrl.dispose();
    _secondsCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _syncState() {
    setState(() {
      _duration = widget.panel.state['duration'] as int? ?? 300;
      _remaining = widget.panel.state['remaining'] as int? ?? 300;
      _isRunning = widget.panel.state['isRunning'] as bool? ?? false;
      _isPaused = widget.panel.state['isPaused'] as bool? ?? false;
      _completed = widget.panel.state['completed'] as bool? ?? false;
      _label = widget.panel.state['label'] as String? ?? '';
    });
    if (_completed && !_soundPlayed) {
      _playAlarm();
      _soundPlayed = true;
      _pulseCtrl.forward(from: 0.0);
    }
    if (!_completed) {
      _soundPlayed = false;
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
    if (_isRunning) _startTicker();
    else _stopTicker();
  }

  void _startTicker() {
    if (_tickTimer != null) return;
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!(widget.panel.state['isRunning'] as bool? ?? false)) return;

      final lastTick =
          widget.panel.state['lastTick'] as int? ??
          DateTime.now().millisecondsSinceEpoch;
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastTick;
      final secondsElapsed = (elapsed / 1000).round();
      final newRemaining = math.max(0, _remaining - secondsElapsed);
      final done = newRemaining <= 0;

      widget.renderContext.onUpdateState({
        ...widget.panel.state,
        'remaining': done ? 0 : newRemaining,
        'isRunning': !done,
        'isPaused': false,
        'completed': done,
        'lastTick': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  void _stopTicker() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  void _playAlarm() {
    try {
      Process.run('afplay', ['/System/Library/Sounds/Ping.aiff']);
    } catch (_) {}
  }

  void _saveState(Map<String, dynamic> updates) {
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      ...updates,
    });
  }

  void _start() {
    _saveState({
      if (_remaining <= 0) ...{'remaining': _duration},
      'isRunning': true,
      'isPaused': false,
      'completed': false,
      'lastTick': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _pause() {
    _saveState({
      'remaining': _remaining,
      'isRunning': false,
      'isPaused': true,
      'lastTick': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _reset() {
    _saveState({
      'remaining': _duration,
      'isRunning': false,
      'isPaused': false,
      'completed': false,
    });
  }

  void _enterEditMode() {
    final m = _duration ~/ 60;
    final s = _duration % 60;
    _minutesCtrl.text = m.toString();
    _secondsCtrl.text = s.toString().padLeft(2, '0');
    _labelCtrl.text = _label;
    setState(() => _editing = true);
  }

  void _saveEdit() {
    final m = int.tryParse(_minutesCtrl.text) ?? 0;
    final s = int.tryParse(_secondsCtrl.text) ?? 0;
    final newDuration = (m * 60 + s).clamp(1, 86400);
    _saveState({
      'duration': newDuration,
      'remaining': newDuration,
      'isRunning': false,
      'isPaused': false,
      'completed': false,
      'label': _labelCtrl.text.trim(),
    });
    setState(() => _editing = false);
  }

  void _applyQuickTimer(int minutes) {
    final seconds = minutes * 60;
    _saveState({
      'duration': seconds,
      'remaining': seconds,
      'isRunning': false,
      'isPaused': false,
      'completed': false,
      'label': _labelCtrl.text.trim(),
    });
    setState(() => _editing = false);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  String get _timeText {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get _progress =>
      _duration > 0 ? (_remaining / _duration).clamp(0.0, 1.0) : 0.0;

  Color get _currentAccent {
    if (_completed) return _completedColor;
    if (_progress < 0.2) return _warningColor;
    return _accent;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    if (_editing) return _buildEditor(colors, onSurface);

    return Column(
      children: [
        if (_label.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              _label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: onSurface.withAlpha(160),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),

        Expanded(
          child: GestureDetector(
            onTap: _isRunning || _isPaused || _completed ? null : _enterEditMode,
            child: Center(
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, _) {
                  final pulse = _completed
                      ? 1.0 + _pulseCtrl.value * 0.04
                      : 1.0;
                  return Transform.scale(
                    scale: pulse,
                    child: SizedBox(
                      width: 160,
                      height: 160,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: _progress, end: _progress),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeInOut,
                        builder: (context, value, child) {
                          return CustomPaint(
                            painter: _TimerCirclePainter(
                              progress: value,
                              accent: _currentAccent,
                              trackColor: colors.border,
                              completed: _completed,
                            ),
                            child: child,
                          );
                        },
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_completed)
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 20,
                                  color: _completedColor,
                                ),
                              Text(
                                _timeText,
                                style: TextStyle(
                                  fontSize: _completed ? 28 : 36,
                                  fontWeight: FontWeight.w700,
                                  color: _completed
                                      ? _completedColor
                                      : onSurface,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              if (!_completed) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _remaining <= 60
                                      ? 'less than a minute'
                                      : '${_remaining ~/ 60} min',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: onSurface.withAlpha(100),
                                  ),
                                ),
                              ],
                              if (!_completed && _remaining <= 0)
                                Text(
                                  'Time\'s up!',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _warningColor,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // ── Controls ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SmallBtn(
                icon: Icons.refresh_rounded,
                onPressed:
                    _isRunning || _isPaused || _completed || _remaining < _duration
                        ? _reset
                        : null,
                color: onSurface,
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () {
                  if (_completed) {
                    _reset();
                  } else if (_isRunning) {
                    _pause();
                  } else if (_isPaused) {
                    _start();
                  } else {
                    _start();
                  }
                },
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _currentAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _currentAccent.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    _completed
                        ? Icons.refresh_rounded
                        : _isRunning
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _SmallBtn(
                icon: Icons.edit_outlined,
                onPressed: !_isRunning ? _enterEditMode : null,
                color: onSurface,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditor(AppColorScheme colors, Color onSurface) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Time input ──────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TimeField(
                controller: _minutesCtrl,
                label: 'min',
                onSurface: onSurface,
                colors: colors,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  ':',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: onSurface,
                  ),
                ),
              ),
              _TimeField(
                controller: _secondsCtrl,
                label: 'sec',
                onSurface: onSurface,
                colors: colors,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Quick timers ────────────────────────────────────────────────
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: _quickTimers.map((m) {
              final isActive = _duration == m * 60;
              return GestureDetector(
                onTap: () => _applyQuickTimer(m),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isActive ? _accent.withValues(alpha: 0.15) : colors.surfaceHighlight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isActive ? _accent : colors.border,
                      width: isActive ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    '$m min',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive ? _accent : onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          // ── Label ──────────────────────────────────────────────────────
          TextField(
            controller: _labelCtrl,
            style: TextStyle(fontSize: 13, color: onSurface),
            decoration: InputDecoration(
              hintText: 'Label (optional)',
              hintStyle: TextStyle(
                fontSize: 12,
                color: onSurface.withValues(alpha: 0.4),
              ),
              prefixIcon: Icon(
                Icons.label_outline_rounded,
                size: 16,
                color: onSurface.withValues(alpha: 0.4),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _accent, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              isDense: true,
            ),
            onSubmitted: (_) => _saveEdit(),
          ),

          const SizedBox(height: 14),

          // ── Action buttons ──────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _editing = false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: onSurface.withValues(alpha: 0.6),
                  side: BorderSide(color: colors.border),
                  minimumSize: const Size(80, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: !_isRunning ? _saveEdit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  disabledBackgroundColor: _accent.withValues(alpha: 0.4),
                  minimumSize: const Size(80, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('Set', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Time Field ──────────────────────────────────────────────────────────────

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.controller,
    required this.label,
    required this.onSurface,
    required this.colors,
  });

  final TextEditingController controller;
  final String label;
  final Color onSurface;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 64,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 10,
              ),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

// ─── Timer Circle Painter ─────────────────────────────────────────────────────

class _TimerCirclePainter extends CustomPainter {
  _TimerCirclePainter({
    required this.progress,
    required this.accent,
    required this.trackColor,
    required this.completed,
  });

  final double progress;
  final Color accent;
  final Color trackColor;
  final bool completed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 8;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0 || completed) {
      final progressPaint = Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;

      final sweep = completed ? 2 * math.pi : (1.0 - progress) * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        -sweep,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_TimerCirclePainter old) =>
      old.progress != progress ||
      old.accent != accent ||
      old.completed != completed;
}

// ─── Small Button Widget ──────────────────────────────────────────────────────

class _SmallBtn extends StatelessWidget {
  const _SmallBtn({
    required this.icon,
    required this.onPressed,
    required this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      color: onPressed == null ? color.withValues(alpha: 0.25) : color.withValues(alpha: 0.7),
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      style: IconButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
