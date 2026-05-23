import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────── public API ──────────────────────────────────────

class YoloVoiceOverlay extends StatefulWidget {
  const YoloVoiceOverlay({
    super.key,
    required this.status,
    required this.title,
    required this.hint,
    required this.transcript,
    required this.response,
    this.animate = true,
    this.focusNode,
    this.onHide,
    this.onPrimaryAction,
  });

  final String status;
  final String title;
  final String hint;
  final String transcript;
  final String response;
  final bool animate;
  final FocusNode? focusNode;
  final VoidCallback? onHide;
  final VoidCallback? onPrimaryAction;

  @override
  State<YoloVoiceOverlay> createState() => _YoloVoiceOverlayState();
}

// ─────────────────────────── state enum ──────────────────────────────────────

enum _VS {
  idle,
  listening,
  processing,
  thinking,
  responding;

  static _VS from(String s) => switch (s) {
        'listening' => listening,
        'processing' => processing,
        'thinking' => thinking,
        'responding' || 'output' => responding,
        _ => idle,
      };

  /// Minimum ms to stay in this state before leaving.
  int get minMs => switch (this) {
        processing => 1800,
        thinking => 1400,
        _ => 0,
      };
}

// ─────────────────────────── state ───────────────────────────────────────────

class _YoloVoiceOverlayState extends State<YoloVoiceOverlay>
    with TickerProviderStateMixin {
  // Persistent orb ticker — never recreated across states.
  late final AnimationController _orbAnim;

  _VS _shown = _VS.idle;
  DateTime _shownAt = DateTime.now();
  bool _pendingTransition = false;

  @override
  void initState() {
    super.initState();
    _shown = _VS.from(widget.status);
    _orbAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    if (widget.animate) { _orbAnim.repeat(); } else { _orbAnim.value = 0.23; }
  }

  @override
  void didUpdateWidget(YoloVoiceOverlay old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) {
      if (widget.animate && !_orbAnim.isAnimating) _orbAnim.repeat();
      if (!widget.animate && _orbAnim.isAnimating) {
        _orbAnim.stop();
        _orbAnim.value = 0.23;
      }
    }
    if (old.status != widget.status) _maybeTransition();
  }

  void _maybeTransition() {
    if (_pendingTransition) return;
    final target = _VS.from(widget.status);
    if (target == _shown) return;
    final elapsed = DateTime.now().difference(_shownAt).inMilliseconds;
    final wait = _shown.minMs - elapsed;
    if (wait > 0) {
      _pendingTransition = true;
      Future.delayed(Duration(milliseconds: wait), () {
        _pendingTransition = false;
        if (!mounted) return;
        final next = _VS.from(widget.status);
        if (next != _shown) setState(() { _shown = next; _shownAt = DateTime.now(); });
      });
    } else {
      setState(() { _shown = target; _shownAt = DateTime.now(); });
    }
  }

  @override
  void dispose() {
    _orbAnim.dispose();
    super.dispose();
  }

  // ── helpers ─────────────────────────────────────────────────────────────────

  bool get _isListening  => _shown == _VS.listening;
  bool get _isSending    => _shown == _VS.processing;
  bool get _isThinking   => _shown == _VS.thinking;
  bool get _isResponse   => _shown == _VS.responding;

  double get _orbSize => switch (_shown) {
        _VS.listening  => 250,
        _VS.thinking   => 240,
        _VS.processing => 190,
        _VS.responding => 210,
        _VS.idle       => 210,
      };

  _OrbMode get _orbMode => switch (_shown) {
        _VS.listening  => _OrbMode.recording,
        _VS.processing => _OrbMode.sending,
        _VS.thinking   => _OrbMode.thinking,
        _VS.responding => _OrbMode.response,
        _VS.idle       => _OrbMode.ready,
      };

  // In response state the orb slides left; otherwise stays centered.
  Alignment get _orbAlign =>
      _isResponse ? const Alignment(-0.76, -0.1) : const Alignment(0.0, -0.15);

  // ── build ────────────────────────────────────────────────────────────────────

  static const _kW = 700.0;
  static const _kH = 440.0;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onHide?.call();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.space) {
          widget.onPrimaryAction?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _isResponse ? widget.onHide : widget.onPrimaryAction,
        child: SizedBox(
          width: _kW,
          height: _kH,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── orbit particles (thinking) ───────────────────────────────
              AnimatedOpacity(
                opacity: _isThinking ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 700),
                child: Center(
                  child: _OrbitParticles(
                    animate: _isThinking && widget.animate,
                  ),
                ),
              ),

              // ── upload beam (sending) ───────────────────────────────────
              AnimatedOpacity(
                opacity: _isSending ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: Align(
                  alignment: const Alignment(0.0, -0.70),
                  child: _UploadBeam(animate: _isSending && widget.animate),
                ),
              ),

              // ── waveform left (listening) ───────────────────────────────
              AnimatedOpacity(
                opacity: _isListening ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 600),
                child: Align(
                  alignment: const Alignment(-0.52, -0.10),
                  child: SizedBox(
                    width: 150,
                    height: 72,
                    child: _Waveform(
                      animate: _isListening && widget.animate,
                      flip: true,
                    ),
                  ),
                ),
              ),

              // ── waveform right (listening) ──────────────────────────────
              AnimatedOpacity(
                opacity: _isListening ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 600),
                child: Align(
                  alignment: const Alignment(0.52, -0.10),
                  child: SizedBox(
                    width: 150,
                    height: 72,
                    child: _Waveform(
                      animate: _isListening && widget.animate,
                    ),
                  ),
                ),
              ),

              // ── THE ORB — persistent, animates position + size ──────────
              AnimatedAlign(
                alignment: _orbAlign,
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: _orbSize),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (ctx, sz, _) => AnimatedBuilder(
                    animation: _orbAnim,
                    builder: (ctx, _) => SizedBox.square(
                      dimension: sz,
                      child: CustomPaint(
                        painter: _OrbPainter(
                          progress:
                              widget.animate ? _orbAnim.value : 0.23,
                          mode: _orbMode,
                        ),
                        child: Center(child: _orbLabel(sz)),
                      ),
                    ),
                  ),
                ),
              ),

              // ── response card (fades in right side) ─────────────────────
              AnimatedOpacity(
                opacity: _isResponse ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 900),
                child: IgnorePointer(
                  ignoring: !_isResponse,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(
                          right: 20, left: 248, top: 20, bottom: 56),
                      child: _ResponseCard(
                        response: widget.response,
                        streaming: widget.status == 'responding',
                      ),
                    ),
                  ),
                ),
              ),

              // ── bottom text (all non-response states) ───────────────────
              AnimatedOpacity(
                opacity: _isResponse ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 600),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Thinking dots row
                        AnimatedOpacity(
                          opacity: _isThinking ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 600),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ThinkingDots(
                              animate: _isThinking && widget.animate,
                            ),
                          ),
                        ),
                        // Main text — fades per state
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 650),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, anim) =>
                              FadeTransition(opacity: anim, child: child),
                          child: _textContent(),
                        ),
                      ],
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

  Widget _orbLabel(double sz) => ShaderMask(
        shaderCallback: (b) => const LinearGradient(
          colors: [Color(0xFF64DFFF), Color(0xFFB980FF)],
        ).createShader(b),
        child: Text(
          'YoLo',
          style: TextStyle(
            color: Colors.white,
            fontSize: sz * 0.21,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
            shadows: const [
              Shadow(color: Color(0xAA63B8FF), blurRadius: 16),
            ],
          ),
        ),
      );

  Widget _textContent() => KeyedSubtree(
        key: ValueKey(_shown),
        child: switch (_shown) {
          _VS.idle => const _TextBlock(
              primary: 'Click or speak to start',
              primaryColor: Color(0xFFB5B6C8),
              primarySize: 17,
            ),
          _VS.listening => const _TextBlock(
              primary: 'Recording...',
              primaryColor: Color(0xFFCCCCE0),
              primarySize: 17,
              secondary: 'Esc to cancel  •  Space to send',
              secondaryColor: Color(0xFF9293A6),
              secondarySize: 14,
            ),
          _VS.processing => const _TextBlock(
              primary: 'Sending audio...',
              primaryColor: Color(0xFF62C9FF),
              primarySize: 17,
              secondary: 'Please wait',
              secondaryColor: Color(0xFFA08DFF),
              secondarySize: 18,
              secondaryBold: true,
            ),
          _VS.thinking => const _TextBlock(
              primary: 'Thinking...',
              primaryColor: Color(0xFFD58BFF),
              primarySize: 18,
              primaryBold: true,
              secondary: 'Waiting for response...',
              secondaryColor: Color(0xFF9A9BAD),
              secondarySize: 15,
            ),
          _VS.responding => const SizedBox.shrink(),
        },
      );
}

// ─────────────────────────── text block ──────────────────────────────────────

class _TextBlock extends StatelessWidget {
  const _TextBlock({
    required this.primary,
    required this.primaryColor,
    required this.primarySize,
    this.primaryBold = false,
    this.secondary,
    this.secondaryColor,
    this.secondarySize,
    this.secondaryBold = false,
  });

  final String primary;
  final Color primaryColor;
  final double primarySize;
  final bool primaryBold;
  final String? secondary;
  final Color? secondaryColor;
  final double? secondarySize;
  final bool secondaryBold;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlowText(
          primary,
          size: primarySize,
          color: primaryColor,
          weight: primaryBold ? FontWeight.w700 : FontWeight.w600,
        ),
        if (secondary != null) ...[
          const SizedBox(height: 8),
          _GlowText(
            secondary!,
            size: secondarySize!,
            color: secondaryColor!,
            weight: secondaryBold ? FontWeight.w700 : FontWeight.w500,
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────── glow text ───────────────────────────────────────

class _GlowText extends StatelessWidget {
  const _GlowText(
    this.text, {
    required this.size,
    required this.color,
    this.weight = FontWeight.w600,
  });

  final String text;
  final double size;
  final Color color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: weight,
        shadows: [
          Shadow(
              color: color.withValues(alpha: 0.45), blurRadius: 12),
          Shadow(
              color: Colors.black.withValues(alpha: 0.7), blurRadius: 6),
        ],
      ),
    );
  }
}

// ─────────────────────────── response card ───────────────────────────────────

class _ResponseCard extends StatelessWidget {
  const _ResponseCard({required this.response, required this.streaming});

  final String response;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final text = response.trim().isEmpty
        ? 'YoLo! Here is what I found for you...'
        : response.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 620),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          decoration: BoxDecoration(
            color: const Color(0xF2181A24),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF9B6BFF)
                    .withValues(alpha: streaming ? 0.26 : 0.08),
                blurRadius: streaming ? 36 : 18,
                spreadRadius: -8,
              ),
            ],
          ),
          child: Text(
            text,
            maxLines: 7,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 17,
              height: 1.52,
              fontWeight: FontWeight.w500,
              shadows: streaming
                  ? const [
                      Shadow(
                          color: Color(0x889B6BFF), blurRadius: 14),
                    ]
                  : const [],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.only(left: 18),
          child: _GlowText(
            'Tap to close',
            size: 14,
            color: Color(0xFF8C8D9E),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── orb ─────────────────────────────────────────────

enum _OrbMode { ready, recording, sending, thinking, response }

class _OrbPainter extends CustomPainter {
  const _OrbPainter({required this.progress, required this.mode});

  final double progress;
  final _OrbMode mode;

  // Per-mode blob colors
  static const _palettes = <_OrbMode, List<Color>>{
    _OrbMode.ready: [
      Color(0xFF4FEEFF),
      Color(0xFF6A64FF),
      Color(0xFFE065E8),
      Color(0xFF3894FF),
    ],
    _OrbMode.recording: [
      Color(0xFFAA72FF),
      Color(0xFF6644FF),
      Color(0xFFDD60FF),
      Color(0xFF8844FF),
    ],
    _OrbMode.sending: [
      Color(0xFF30E5FF),
      Color(0xFF3066FF),
      Color(0xFF55AAFF),
      Color(0xFF28C8FF),
    ],
    _OrbMode.thinking: [
      Color(0xFFCC58FF),
      Color(0xFF7744FF),
      Color(0xFF9966FF),
      Color(0xFFFF6AE2),
    ],
    _OrbMode.response: [
      Color(0xFF48E6FF),
      Color(0xFFFF68CC),
      Color(0xFF8866FF),
      Color(0xFF3ABFFF),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final colors = _palettes[mode]!;
    final intensity = switch (mode) {
      _OrbMode.ready => 0.7,
      _OrbMode.recording => 1.0,
      _OrbMode.sending => 0.88,
      _OrbMode.thinking => 0.92,
      _OrbMode.response => 0.78,
    };

    // Ambient glow background
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          colors[0].withValues(alpha: 0.22 * intensity),
          colors[2].withValues(alpha: 0.16 * intensity),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: r * 1.3))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    canvas.drawCircle(center, r * 1.1, glowPaint);

    // 4 large, soft overlapping blobs
    for (var i = 0; i < 4; i++) {
      final t = progress * 2 * math.pi + i * (math.pi / 2) + i * 0.22;
      final wobble = 0.9 + math.sin(t * 1.6 + i) * 0.06 * intensity;
      final blobW = r * (1.12 + (i % 2) * 0.14) * wobble;
      final blobH = r * (0.82 + (i % 3) * 0.10) * wobble;
      final dx = math.cos(t * 0.7 + i * 0.8) * r * 0.14;
      final dy = math.sin(t * 0.9 + i * 0.5) * r * 0.10;
      final paint = Paint()
        ..color = colors[i % colors.length]
            .withValues(alpha: (0.28 + 0.10 * intensity))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22)
        ..blendMode = BlendMode.plus;
      canvas.save();
      canvas.translate(center.dx + dx, center.dy + dy);
      canvas.rotate(t * 0.18 + i * 0.78);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: blobW, height: blobH),
          paint);
      canvas.restore();
    }

    // Core dark center for depth
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.18),
          const Color(0xFF1A2B60).withValues(alpha: 0.52),
          const Color(0xFF060912).withValues(alpha: 0.72),
          Colors.transparent,
        ],
        stops: const [0.0, 0.38, 0.68, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r * 0.66));
    canvas.drawCircle(center, r * 0.54, corePaint);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.progress != progress || old.mode != mode;
}

// ─────────────────────────── waveform ────────────────────────────────────────

class _Waveform extends StatefulWidget {
  const _Waveform({required this.animate, this.flip = false});

  final bool animate;
  final bool flip;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    if (widget.animate) { _c.repeat(); } else { _c.value = 0.42; }
  }

  @override
  void didUpdateWidget(_Waveform old) {
    super.didUpdateWidget(old);
    if (widget.animate != old.animate) {
      widget.animate ? _c.repeat() : _c.stop();
    }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (ctx, _) => CustomPaint(
          painter: _WaveformPainter(
            progress: widget.animate ? _c.value : 0.42,
            flip: widget.flip,
          ),
        ),
      );
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.progress, required this.flip});

  final double progress;
  final bool flip;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.6;
    for (var i = 0; i < 18; i++) {
      final x = i * size.width / 17;
      final phase = progress * 2 * math.pi + i * 0.78;
      final amp = math.sin(phase).abs() * 0.82 + 0.10;
      final h = size.height * amp * (i % 4 == 0 ? 0.74 : 0.38);
      paint.color = Color.lerp(
        const Color(0xFF4066FF),
        const Color(0xFFD460FF),
        i / 17,
      )!.withValues(alpha: i.isEven ? 0.82 : 0.36);
      final drawX = flip ? size.width - x : x;
      canvas.drawLine(
        Offset(drawX, cy - h / 2),
        Offset(drawX, cy + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress || old.flip != flip;
}

// ─────────────────────────── upload beam ─────────────────────────────────────

class _UploadBeam extends StatefulWidget {
  const _UploadBeam({required this.animate});

  final bool animate;

  @override
  State<_UploadBeam> createState() => _UploadBeamState();
}

class _UploadBeamState extends State<_UploadBeam>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    if (widget.animate) { _c.repeat(); } else { _c.value = 0.3; }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 80,
        height: 120,
        child: AnimatedBuilder(
          animation: _c,
          builder: (ctx, _) => CustomPaint(
            painter: _UploadBeamPainter(
              progress: widget.animate ? _c.value : 0.3,
            ),
          ),
        ),
      );
}

class _UploadBeamPainter extends CustomPainter {
  const _UploadBeamPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    // Arrow head
    final arrow = Paint()
      ..color = const Color(0xFFC081FF)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(cx - 14, 26)
      ..lineTo(cx, 8)
      ..lineTo(cx + 14, 26);
    canvas.drawPath(path, arrow);
    // Dotted vertical beam
    final dotPaint = Paint();
    for (var i = 0; i < 10; i++) {
      final t = (progress + i / 10) % 1.0;
      dotPaint
        ..color = Color.lerp(
          const Color(0xFF55E6FF),
          const Color(0xFF895CFF),
          t,
        )!.withValues(alpha: 0.9 - t * 0.65)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(Offset(cx, size.height - t * (size.height - 34)), 2.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _UploadBeamPainter old) =>
      old.progress != progress;
}

// ─────────────────────────── orbit particles ─────────────────────────────────

class _OrbitParticles extends StatefulWidget {
  const _OrbitParticles({required this.animate});

  final bool animate;

  @override
  State<_OrbitParticles> createState() => _OrbitParticlesState();
}

class _OrbitParticlesState extends State<_OrbitParticles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
    if (widget.animate) { _c.repeat(); } else { _c.value = 0.2; }
  }

  @override
  void didUpdateWidget(_OrbitParticles old) {
    super.didUpdateWidget(old);
    if (widget.animate != old.animate) {
      widget.animate ? _c.repeat() : _c.stop();
    }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (ctx, _) => CustomPaint(
          size: const Size(300, 300),
          painter: _OrbitParticlesPainter(
            progress: widget.animate ? _c.value : 0.2,
          ),
        ),
      );
}

class _OrbitParticlesPainter extends CustomPainter {
  const _OrbitParticlesPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint();
    const orbR = 120.0; // orbit radius
    for (var i = 0; i < 36; i++) {
      final angle = progress * 2 * math.pi + i * (2 * math.pi / 36);
      final x = center.dx + math.cos(angle) * orbR;
      final y = center.dy + math.sin(angle) * orbR * 0.68;
      paint.color = Color.lerp(
        const Color(0xFF4FAAFF),
        const Color(0xFFD868FF),
        i / 36,
      )!.withValues(alpha: i % 6 == 0 ? 0.9 : 0.38);
      canvas.drawCircle(Offset(x, y), i % 9 == 0 ? 2.8 : 1.4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitParticlesPainter old) =>
      old.progress != progress;
}

// ─────────────────────────── thinking dots ───────────────────────────────────

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots({required this.animate});

  final bool animate;

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    if (widget.animate) { _c.repeat(); } else { _c.value = 0.35; }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (ctx, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(4, (i) {
            final w = math.sin(_c.value * 2 * math.pi + i * 0.7);
            final color = Color.lerp(
              const Color(0xFFFF73F6),
              const Color(0xFF5B5DFF),
              i / 3,
            )!;
            final d = 12.0 + w * 2.0;
            return Container(
              width: d,
              height: d,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.75 + w.abs() * 0.22),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 10,
                  ),
                ],
              ),
            );
          }),
        ),
      );
}
