import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The current state of the voice interaction.
enum VoiceVisualizerState { idle, listening, speaking, processing }

/// Animated circular visualizer for the voice mode of the YoLo Assistant.
///
/// Renders different animations depending on [state]:
/// - **idle** – gentle breathing pulse
/// - **listening** – expanding ripple waves
/// - **speaking** – vertical bars with varying heights
/// - **processing** – rotating dots
class AssistantVoiceVisualizer extends StatefulWidget {
  const AssistantVoiceVisualizer({
    super.key,
    required this.state,
    this.size = 180,
    this.color = const Color(0xFF8B5CF6),
  });

  final VoiceVisualizerState state;
  final double size;
  final Color color;

  @override
  State<AssistantVoiceVisualizer> createState() =>
      _AssistantVoiceVisualizerState();
}

class _AssistantVoiceVisualizerState extends State<AssistantVoiceVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant AssistantVoiceVisualizer old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _controller.duration = _duration;
      if (!_controller.isAnimating) _controller.repeat();
    }
  }

  Duration get _duration {
    switch (widget.state) {
      case VoiceVisualizerState.idle:
        return const Duration(milliseconds: 2000);
      case VoiceVisualizerState.listening:
        return const Duration(milliseconds: 1600);
      case VoiceVisualizerState.speaking:
        return const Duration(milliseconds: 800);
      case VoiceVisualizerState.processing:
        return const Duration(milliseconds: 1200);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _VisualizerPainter(
            progress: _controller.value,
            state: widget.state,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  _VisualizerPainter({
    required this.progress,
    required this.state,
    required this.color,
  });

  final double progress;
  final VoiceVisualizerState state;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    switch (state) {
      case VoiceVisualizerState.idle:
        _paintIdle(canvas, center, radius);
      case VoiceVisualizerState.listening:
        _paintListening(canvas, center, radius);
      case VoiceVisualizerState.speaking:
        _paintSpeaking(canvas, center, radius);
      case VoiceVisualizerState.processing:
        _paintProcessing(canvas, center, radius);
    }
  }

  void _paintIdle(Canvas canvas, Offset center, double radius) {
    final scale = 0.95 + 0.1 * math.sin(progress * 2 * math.pi);
    final paint =
        Paint()
          ..color = color.withAlpha(40)
          ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * scale * 0.7, paint);
    paint.color = color.withAlpha(80);
    canvas.drawCircle(center, radius * scale * 0.5, paint);
    paint.color = color.withAlpha(140);
    canvas.drawCircle(center, radius * scale * 0.32, paint);
  }

  void _paintListening(Canvas canvas, Offset center, double radius) {
    const rippleCount = 3;
    for (int i = 0; i < rippleCount; i++) {
      final t = (progress + i / rippleCount) % 1.0;
      final r = radius * 0.3 + radius * 0.7 * t;
      final opacity = (1.0 - t).clamp(0.0, 1.0);
      final paint =
          Paint()
            ..color = color.withAlpha((opacity * 100).toInt())
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0;
      canvas.drawCircle(center, r, paint);
    }
    // Inner solid circle
    canvas.drawCircle(
      center,
      radius * 0.25,
      Paint()
        ..color = color.withAlpha(180)
        ..style = PaintingStyle.fill,
    );
  }

  void _paintSpeaking(Canvas canvas, Offset center, double radius) {
    const barCount = 7;
    final barWidth = radius * 0.14;
    final totalWidth = barCount * barWidth + (barCount - 1) * barWidth * 0.5;
    var x = center.dx - totalWidth / 2;
    for (int i = 0; i < barCount; i++) {
      final phase = progress * 2 * math.pi + i * 0.9;
      final heightFraction = 0.3 + 0.7 * ((math.sin(phase) + 1) / 2);
      final barHeight = radius * 1.2 * heightFraction;
      final paint =
          Paint()
            ..color = color.withAlpha(160 + (40 * heightFraction).toInt())
            ..style = PaintingStyle.fill;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, center.dy),
          width: barWidth,
          height: barHeight,
        ),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, paint);
      x += barWidth * 1.5;
    }
  }

  void _paintProcessing(Canvas canvas, Offset center, double radius) {
    const dotCount = 3;
    final dotRadius = radius * 0.08;
    final orbitRadius = radius * 0.3;
    for (int i = 0; i < dotCount; i++) {
      final angle = progress * 2 * math.pi + i * (2 * math.pi / dotCount);
      final dx = center.dx + orbitRadius * math.cos(angle);
      final dy = center.dy + orbitRadius * math.sin(angle);
      final paint =
          Paint()
            ..color = color.withAlpha(180)
            ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(dx, dy), dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter old) =>
      old.progress != progress || old.state != state || old.color != color;
}
