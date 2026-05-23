import 'dart:math' as math;
import 'dart:ui' as ui;
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
    this.scale = 1.0,
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
  final double scale;

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

  int get minMs => switch (this) {
        processing => 1800,
        thinking => 1400,
        _ => 0,
      };
}

// ─────────────────────────── main state ──────────────────────────────────────

class _YoloVoiceOverlayState extends State<YoloVoiceOverlay>
    with TickerProviderStateMixin {
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
      duration: const Duration(milliseconds: 8000),
    );
    if (widget.animate) {
      _orbAnim.repeat();
    } else {
      _orbAnim.value = 0.23;
    }
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

  // Natural state order — enforce sequential transitions
  static const _order = [
    _VS.idle,
    _VS.listening,
    _VS.processing,
    _VS.thinking,
    _VS.responding,
  ];

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
        final latest = _VS.from(widget.status);
        if (latest == _shown) return;

        // Step to next sequential state, not jump to latest
        final curIdx = _order.indexOf(_shown);
        final latestIdx = _order.indexOf(latest);
        final nextState =
            (latestIdx > curIdx + 1) ? _order[curIdx + 1] : latest;

        setState(() {
          _shown = nextState;
          _shownAt = DateTime.now();
        });
        // If we stepped to intermediate, trigger another transition
        if (nextState != latest) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _maybeTransition();
          });
        }
      });
    } else {
      // No min time required — but still step sequentially for forward moves
      final curIdx = _order.indexOf(_shown);
      final targetIdx = _order.indexOf(target);
      final nextState =
          (targetIdx > curIdx + 1) ? _order[curIdx + 1] : target;

      setState(() {
        _shown = nextState;
        _shownAt = DateTime.now();
      });
      if (nextState != target) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _maybeTransition();
        });
      }
    }
  }

  @override
  void dispose() {
    _orbAnim.dispose();
    super.dispose();
  }

  bool get _isListening => _shown == _VS.listening;
  bool get _isSending => _shown == _VS.processing;
  bool get _isThinking => _shown == _VS.thinking;
  bool get _isResponse => _shown == _VS.responding;

  double get _orbSize => switch (_shown) {
        _VS.listening => 260,
        _VS.thinking => 250,
        _VS.processing => 200,
        _VS.responding => 220,
        _VS.idle => 220,
      };

  _OrbMode get _orbMode => switch (_shown) {
        _VS.listening => _OrbMode.recording,
        _VS.processing => _OrbMode.sending,
        _VS.thinking => _OrbMode.thinking,
        _VS.responding => _OrbMode.response,
        _VS.idle => _OrbMode.ready,
      };

  Alignment get _orbAlign =>
      _isResponse ? const Alignment(-0.70, -0.06) : const Alignment(0.0, -0.10);

  // ── build ─────────────────────────────────────────────────────────────────

  static const _kW = 720.0;
  static const _kH = 460.0;

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
          width: _kW * widget.scale,
          height: _kH * widget.scale,
          child: Transform.scale(
            scale: widget.scale,
            child: SizedBox(
              width: _kW,
              height: _kH,
              child: Stack(
            fit: StackFit.expand,
            children: [
              // ── orbit particles (thinking) ──────────────────────────
              AnimatedOpacity(
                opacity: _isThinking ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 700),
                child: Center(
                  child: _OrbitParticles(
                    animate: _isThinking && widget.animate,
                  ),
                ),
              ),

              // ── upload beam (sending) ───────────────────────────────
              AnimatedOpacity(
                opacity: _isSending ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: Align(
                  alignment: const Alignment(0.0, -0.70),
                  child: _UploadBeam(animate: _isSending && widget.animate),
                ),
              ),

              // ── waveform left (listening) ───────────────────────────
              AnimatedOpacity(
                opacity: _isListening ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 600),
                child: Align(
                  alignment: const Alignment(-0.50, -0.08),
                  child: SizedBox(
                    width: 160,
                    height: 80,
                    child: _Waveform(
                      animate: _isListening && widget.animate,
                      flip: true,
                    ),
                  ),
                ),
              ),

              // ── waveform right (listening) ─────────────────────────
              AnimatedOpacity(
                opacity: _isListening ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 600),
                child: Align(
                  alignment: const Alignment(0.50, -0.08),
                  child: SizedBox(
                    width: 160,
                    height: 80,
                    child: _Waveform(
                      animate: _isListening && widget.animate,
                    ),
                  ),
                ),
              ),

              // ── THE ORB — persistent, smooth position + size ───────
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
                        painter: _BlobOrbPainter(
                          progress: widget.animate ? _orbAnim.value : 0.23,
                          mode: _orbMode,
                        ),
                        child: Center(child: _orbLabel(sz)),
                      ),
                    ),
                  ),
                ),
              ),

              // ── response card (slides in from right) ──────────────
              AnimatedOpacity(
                opacity: _isResponse ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 900),
                child: IgnorePointer(
                  ignoring: !_isResponse,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        right: 18,
                        left: 260,
                        top: 20,
                        bottom: 56,
                      ),
                      child: _ResponseCard(
                        response: widget.response,
                        streaming: widget.status == 'responding',
                      ),
                    ),
                  ),
                ),
              ),

              // ── bottom text (non-response states) ──────────────────
              AnimatedOpacity(
                opacity: _isResponse ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 600),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
            fontSize: sz * 0.20,
            fontWeight: FontWeight.w300,
            letterSpacing: -0.8,
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
          Shadow(color: color.withValues(alpha: 0.45), blurRadius: 12),
          Shadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 6),
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
                    .withValues(alpha: streaming ? 0.30 : 0.08),
                blurRadius: streaming ? 40 : 18,
                spreadRadius: -6,
              ),
            ],
          ),
          child: Text(
            text,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 17,
              height: 1.52,
              fontWeight: FontWeight.w500,
              shadows: streaming
                  ? const [
                      Shadow(color: Color(0x889B6BFF), blurRadius: 14),
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

// ─────────────────────────── BLOB ORB PAINTER ───────────────────────────────
// Draws 5 large overlapping irregular translucent blobs with visible edges,
// matching the reference: organic shapes, NOT circles.

enum _OrbMode { ready, recording, sending, thinking, response }

class _BlobOrbPainter extends CustomPainter {
  const _BlobOrbPainter({required this.progress, required this.mode});

  final double progress;
  final _OrbMode mode;

  static const _palettes = <_OrbMode, List<Color>>{
    _OrbMode.ready: [
      Color(0xFF3CE8FF), // cyan
      Color(0xFF5A7AFF), // blue
      Color(0xFFE060E0), // pink
      Color(0xFF3B9EFF), // light blue
      Color(0xFFC47AFF), // lavender
    ],
    _OrbMode.recording: [
      Color(0xFFAA66FF), // purple
      Color(0xFF6644FF), // deep purple
      Color(0xFFE050FF), // magenta
      Color(0xFF5588FF), // blue
      Color(0xFFCC50DD), // pink-purple
    ],
    _OrbMode.sending: [
      Color(0xFF30E5FF), // cyan
      Color(0xFF3060FF), // blue
      Color(0xFF55B0FF), // sky
      Color(0xFF28C8FF), // aqua
      Color(0xFF4488FF), // medium blue
    ],
    _OrbMode.thinking: [
      Color(0xFFCC50FF), // purple
      Color(0xFF6644FF), // deep blue
      Color(0xFF9966FF), // violet
      Color(0xFF3BAAFF), // cyan
      Color(0xFFFF60DD), // pink
    ],
    _OrbMode.response: [
      Color(0xFF48E6FF), // cyan
      Color(0xFFFF60CC), // pink
      Color(0xFF8866FF), // purple
      Color(0xFF3ABFFF), // blue
      Color(0xFFC870FF), // lavender
    ],
  };

  // Blob shape configs: each blob has offset angle, size multiplier, aspect ratio
  static const _blobConfigs = [
    (angle: 0.0, scale: 1.06, aspect: 0.88, phase: 0.0),
    (angle: 1.25, scale: 0.98, aspect: 0.92, phase: 0.4),
    (angle: 2.50, scale: 1.04, aspect: 0.84, phase: 0.8),
    (angle: 3.90, scale: 0.96, aspect: 0.90, phase: 1.3),
    (angle: 5.10, scale: 1.00, aspect: 0.86, phase: 1.8),
  ];

  /// Create an organic blob path using cubic bezier curves.
  /// The blob is a deformed ellipse where control points wobble.
  Path _blobPath(
    Offset center,
    double w,
    double h,
    double wobbleT,
    int seed,
  ) {
    final path = Path();
    const segments = 12; // More segments = smoother curve
    final rng = math.Random(seed);
    final points = <Offset>[];

    for (var i = 0; i < segments; i++) {
      final angle = (i / segments) * 2 * math.pi;
      // Gentle wobble for organic feel (not too bumpy)
      // Integer multipliers ensure animation loops seamlessly (2π period)
      final wobble = 1.0 +
          math.sin(wobbleT * 2 + i * 0.55 + rng.nextDouble() * 0.3) * 0.04 +
          math.cos(wobbleT * 1 + i * 0.7) * 0.03;
      final rx = w / 2 * wobble;
      final ry = h / 2 * wobble;
      points.add(Offset(
        center.dx + math.cos(angle) * rx,
        center.dy + math.sin(angle) * ry,
      ));
    }

    // Catmull-Rom style: smooth cubic through all points
    path.moveTo(points[0].dx, points[0].dy);
    for (var i = 0; i < segments; i++) {
      final p0 = points[i];
      final p1 = points[(i + 1) % segments];
      final prev = points[(i - 1 + segments) % segments];
      final next2 = points[(i + 2) % segments];
      // Tangent-based control points for smooth curve
      final cp1 = Offset(
        p0.dx + (p1.dx - prev.dx) / 6,
        p0.dy + (p1.dy - prev.dy) / 6,
      );
      final cp2 = Offset(
        p1.dx - (next2.dx - p0.dx) / 6,
        p1.dy - (next2.dy - p0.dy) / 6,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p1.dx, p1.dy);
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final colors = _palettes[mode]!;
    final intensity = switch (mode) {
      _OrbMode.ready => 0.72,
      _OrbMode.recording => 1.0,
      _OrbMode.sending => 0.88,
      _OrbMode.thinking => 0.95,
      _OrbMode.response => 0.80,
    };

    // Soft ambient glow behind everything
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          colors[0].withValues(alpha: 0.10 * intensity),
          colors[2].withValues(alpha: 0.06 * intensity),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: r * 1.35))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(center, r * 1.2, glowPaint);

    // Draw 5 distinct translucent blobs with visible edges
    for (var i = 0; i < 5; i++) {
      final cfg = _blobConfigs[i];
      final t = progress * 2 * math.pi + cfg.phase;
      // Slow orbital movement — integer multiplier for seamless loop
      final blobAngle = cfg.angle + t;

      // Larger offset so individual shapes are clearly visible
      final dx = math.cos(blobAngle) * r * 0.32;
      final dy = math.sin(blobAngle) * r * 0.26;
      final blobCenter = Offset(center.dx + dx, center.dy + dy);

      final blobW = r * 2 * cfg.scale * (0.82 + math.sin(t) * 0.04);
      final blobH = blobW * cfg.aspect;

      final path = _blobPath(blobCenter, blobW, blobH, t, i * 42 + 7);

      // Fill: linear gradient — OPAQUE at far edge → TRANSPARENT toward orb center
      // Direction: from blob's far side to orb center
      final dirX = blobCenter.dx - center.dx;
      final dirY = blobCenter.dy - center.dy;
      final dirLen = math.sqrt(dirX * dirX + dirY * dirY).clamp(1.0, double.infinity);
      final normX = dirX / dirLen;
      final normY = dirY / dirLen;
      final gradRadius = blobW * 0.50;
      final gradFrom = Offset(blobCenter.dx + normX * gradRadius,
                               blobCenter.dy + normY * gradRadius);
      final gradTo = Offset(blobCenter.dx - normX * gradRadius,
                             blobCenter.dy - normY * gradRadius);

      final fillPaint = Paint()
        ..shader = ui.Gradient.linear(
          gradFrom,
          gradTo,
          [
            colors[i].withValues(alpha: 0.28 + 0.14 * intensity),
            colors[i].withValues(alpha: 0.10 + 0.06 * intensity),
            colors[i].withValues(alpha: 0.0),
          ],
          [0.0, 0.5, 1.0],
        )
        ..blendMode = BlendMode.plus;
      canvas.drawPath(path, fillPaint);

      // Wide halo glow — very soft, creates the glowing aura
      final glowEdge = Paint()
        ..color = colors[i].withValues(alpha: 0.05 + 0.04 * intensity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16)
        ..blendMode = BlendMode.plus;
      canvas.drawPath(path, glowEdge);
    }

    // No inner glow — keep center clear for YoLo text

    // No dark core — center stays clean
  }

  @override
  bool shouldRepaint(covariant _BlobOrbPainter old) =>
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
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.animate) {
      _c.repeat();
    } else {
      _c.value = 0.42;
    }
  }

  @override
  void didUpdateWidget(_Waveform old) {
    super.didUpdateWidget(old);
    if (widget.animate != old.animate) {
      if (widget.animate) {
        _c.repeat();
      } else {
        _c.stop();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

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
    final paint = Paint()..strokeCap = StrokeCap.round;

    // Mix of thin lines and small dots like the reference
    for (var i = 0; i < 22; i++) {
      final x = i * size.width / 21;
      final phase = progress * 2 * math.pi + i * 0.72;
      final amp = math.sin(phase).abs() * 0.85 + 0.08;
      final drawX = flip ? size.width - x : x;
      final color = Color.lerp(
        const Color(0xFF4066FF),
        const Color(0xFFD460FF),
        i / 21,
      )!;

      if (i % 3 == 2) {
        // Dots
        paint
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: 0.65 + amp * 0.2)
          ..strokeWidth = 0;
        canvas.drawCircle(Offset(drawX, cy), 1.6 + amp * 1.2, paint);
      } else {
        // Lines
        final h = size.height * amp * (i % 5 == 0 ? 0.78 : 0.40);
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = i % 4 == 0 ? 2.8 : 1.6
          ..color = color.withValues(alpha: i.isEven ? 0.80 : 0.35);
        canvas.drawLine(
          Offset(drawX, cy - h / 2),
          Offset(drawX, cy + h / 2),
          paint,
        );
      }
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
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.animate) {
      _c.repeat();
    } else {
      _c.value = 0.3;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

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

    // Dotted beam
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
      canvas.drawCircle(
        Offset(cx, size.height - t * (size.height - 34)),
        2.2,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UploadBeamPainter old) =>
      old.progress != progress;
}

// ─────────────────────────── orbit particles ─────────────────────────────────
// Scattered floating dots at varying distances — NOT uniform circle.

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
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    if (widget.animate) {
      _c.repeat();
    } else {
      _c.value = 0.2;
    }
  }

  @override
  void didUpdateWidget(_OrbitParticles old) {
    super.didUpdateWidget(old);
    if (widget.animate != old.animate) {
      if (widget.animate) {
        _c.repeat();
      } else {
        _c.stop();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (ctx, _) => CustomPaint(
          size: const Size(320, 320),
          painter: _ScatteredParticlesPainter(
            progress: widget.animate ? _c.value : 0.2,
          ),
        ),
      );
}

class _ScatteredParticlesPainter extends CustomPainter {
  const _ScatteredParticlesPainter({required this.progress});

  final double progress;

  // Pre-computed particle configs (radius offset, angle offset, size, speed)
  static final _particles = List.generate(50, (i) {
    final rng = math.Random(i * 37 + 13);
    return (
      radiusBase: 0.50 + rng.nextDouble() * 0.40, // 0.50..0.90 of half-width
      angleOffset: rng.nextDouble() * 2 * math.pi,
      size: 1.0 + rng.nextDouble() * 2.4,
      speed: 0.6 + rng.nextDouble() * 0.8,
      colorT: rng.nextDouble(),
      bright: rng.nextDouble() > 0.70, // ~30% are bright
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final halfW = size.width / 2;
    final paint = Paint();

    for (final p in _particles) {
      final angle =
          progress * 2 * math.pi * p.speed + p.angleOffset;
      final orbitR = halfW * p.radiusBase;
      // Slightly elliptical
      final x = center.dx + math.cos(angle) * orbitR;
      final y = center.dy + math.sin(angle) * orbitR * 0.72;

      final color = Color.lerp(
        const Color(0xFF4FAAFF),
        const Color(0xFFD868FF),
        p.colorT,
      )!;

      if (p.bright) {
        paint
          ..color = color.withValues(alpha: 0.85)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
        canvas.drawCircle(Offset(x, y), p.size * 1.1, paint);
      } else {
        paint
          ..color = color.withValues(alpha: 0.40)
          ..maskFilter = null;
        canvas.drawCircle(Offset(x, y), p.size * 0.7, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScatteredParticlesPainter old) =>
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
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.animate) {
      _c.repeat();
    } else {
      _c.value = 0.35;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

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
