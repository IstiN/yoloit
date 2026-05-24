import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:yoloit/features/preview/widgets/markdown_document_preview.dart';

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
    this.scale = 2.0,
    this.orbScale = 0.30,
    this.ovalWidth = 2.0,
    this.ovalHeight = 1.10,
    this.titleFontSize = 9,
    this.titleColor,
    this.waveBarCount = 22,
    this.waveAmplitude = 0.85,
    this.waveSpeed = 1400,
    this.waveWidth = 160,
    this.waveSpread = 0.50,
    this.particleScale = 0.3,
    this.responseFontSize = 18.0,
    this.borderSpeed = 1200,
    this.responseActionLabel = 'Tap to close',
    this.showIdleHint = true,
    this.orbAlignY = -0.10,
    this.responseOrbAlignY = 0.62,
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
  final double orbScale;
  final double ovalWidth;
  final double ovalHeight;
  final double? titleFontSize;
  final Color? titleColor;
  final int waveBarCount;
  final double waveAmplitude;
  final int waveSpeed;
  final double waveWidth;
  final double waveSpread;
  final double particleScale;
  final double responseFontSize;
  final int borderSpeed;
  final String responseActionLabel;
  final bool showIdleHint;
  final double orbAlignY;
  final double responseOrbAlignY;

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
    processing => 600,
    thinking => 500,
    responding => 3000,
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
      final nextState = (targetIdx > curIdx + 1) ? _order[curIdx + 1] : target;

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
    _VS.processing => 250,
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
      _isResponse
          ? Alignment(0.0, widget.responseOrbAlignY)
          : Alignment(0.0, widget.orbAlignY);

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
                  // ── orbit particles (thinking + processing) ────────────
                  AnimatedOpacity(
                    opacity: (_isThinking || _isSending) ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 700),
                    child: Center(
                      child: _OrbitParticles(
                        animate: (_isThinking || _isSending) && widget.animate,
                        scale: widget.particleScale,
                      ),
                    ),
                  ),

                  // ── upload beam (sending) — hidden, processing uses orb ──
                  const SizedBox.shrink(),

                  // ── waveform left (listening) ───────────────────────────
                  AnimatedOpacity(
                    opacity: _isListening ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 600),
                    child: Align(
                      alignment: Alignment(-widget.waveSpread, -0.08),
                      child: SizedBox(
                        width: widget.waveWidth,
                        height: 80,
                        child: _Waveform(
                          animate: _isListening && widget.animate,
                          flip: true,
                          barCount: widget.waveBarCount,
                          amplitude: widget.waveAmplitude,
                          speed: widget.waveSpeed,
                        ),
                      ),
                    ),
                  ),

                  // ── waveform right (listening) ─────────────────────────
                  AnimatedOpacity(
                    opacity: _isListening ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 600),
                    child: Align(
                      alignment: Alignment(widget.waveSpread, -0.08),
                      child: SizedBox(
                        width: widget.waveWidth,
                        height: 80,
                        child: _Waveform(
                          animate: _isListening && widget.animate,
                          barCount: widget.waveBarCount,
                          amplitude: widget.waveAmplitude,
                          speed: widget.waveSpeed,
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
                    builder:
                        (ctx, sz, _) => AnimatedBuilder(
                          animation: _orbAnim,
                          builder:
                              (ctx, _) => GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: widget.onPrimaryAction,
                                child: SizedBox.square(
                                  dimension: sz * widget.orbScale,
                                  child: CustomPaint(
                                    painter: _BlobOrbPainter(
                                      progress:
                                          widget.animate
                                              ? _orbAnim.value
                                              : 0.23,
                                      mode: _orbMode,
                                      bgColor:
                                          Theme.of(ctx).scaffoldBackgroundColor,
                                      ovalWidth: widget.ovalWidth,
                                      ovalHeight: widget.ovalHeight,
                                    ),
                                    child: Center(child: _orbLabel(sz)),
                                  ),
                                ),
                              ),
                        ),
                  ),
                ),

                  // ── response card (above the orb) ─────────────────────
                AnimatedOpacity(
                  opacity: _isResponse ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 900),
                  child: IgnorePointer(
                    ignoring: !_isResponse,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 152),
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: widget.onPrimaryAction,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 200,
                              maxWidth: 470,
                              minHeight: 60,
                              maxHeight: 250,
                            ),
                            child: _ResponseCard(
                              response: widget.response,
                              streaming: widget.status == 'responding',
                              animate: widget.animate,
                              fontSize: widget.responseFontSize,
                              borderSpeed: widget.borderSpeed,
                              actionLabel: widget.responseActionLabel,
                            ),
                          ),
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
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 650),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder:
                                  (child, anim) => FadeTransition(
                                    opacity: anim,
                                    child: child,
                                  ),
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
    );
  }

  Widget _orbLabel(double sz) => ShaderMask(
    shaderCallback:
        (b) => LinearGradient(
          colors:
              widget.titleColor != null
                  ? [widget.titleColor!, widget.titleColor!]
                  : const [Color(0xFF64DFFF), Color(0xFFB980FF)],
        ).createShader(b),
    child: Text(
      'YoLo',
      style: TextStyle(
        color: Colors.white,
        fontSize: widget.titleFontSize ?? sz * 0.15,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.8,
        shadows: const [Shadow(color: Color(0xAA63B8FF), blurRadius: 16)],
      ),
    ),
  );

  Widget _textContent() => KeyedSubtree(
    key: ValueKey(_shown),
    child: switch (_shown) {
      _VS.idle =>
        widget.showIdleHint
            ? const _TextBlock(
              primary: 'Click or speak to start',
              primaryColor: Color(0xFFB5B6C8),
              primarySize: 17,
            )
            : const SizedBox.shrink(),
      _VS.listening => const _TextBlock(
        primary: 'Recording...',
        primaryColor: Color(0xFFCCCCE0),
        primarySize: 17,
        secondary: 'Esc to cancel  •  Space to send',
        secondaryColor: Color(0xFF9293A6),
        secondarySize: 14,
      ),
      _VS.processing => const _TextBlock(
        primary: 'Processing...',
        primaryColor: Color(0xFF62C9FF),
        primarySize: 18,
        primaryBold: true,
        secondary: 'Please wait',
        secondaryColor: Color(0xFF9A9BAD),
        secondarySize: 15,
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

class _ResponseCard extends StatefulWidget {
  const _ResponseCard({
    required this.response,
    required this.streaming,
    this.animate = true,
    this.fontSize = 18.0,
    this.borderSpeed = 1200,
    this.actionLabel = 'Tap to close',
  });

  final String response;
  final bool streaming;
  final bool animate;
  final double fontSize;
  final int borderSpeed;
  final String actionLabel;

  @override
  State<_ResponseCard> createState() => _ResponseCardState();
}

class _ResponseCardState extends State<_ResponseCard>
    with TickerProviderStateMixin {
  late final AnimationController _borderAnim;
  late AnimationController _typingAnim;
  int _visibleChars = 0;
  String _lastResponse = '';

  @override
  void initState() {
    super.initState();
    _borderAnim = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.borderSpeed),
    );
    if (widget.streaming && widget.animate) _borderAnim.repeat();

    _lastResponse = widget.response;
    _visibleChars = widget.streaming ? 0 : widget.response.length;
    _typingAnim = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (widget.response.length * 30).clamp(300, 6000),
      ),
    );
    if (widget.streaming && widget.animate && widget.response.isNotEmpty) {
      _typingAnim.forward();
    }
    _typingAnim.addListener(_updateVisibleChars);
  }

  void _updateVisibleChars() {
    final target = (_typingAnim.value * _lastResponse.length).round();
    if (target != _visibleChars) {
      setState(() => _visibleChars = target);
    }
  }

  @override
  void didUpdateWidget(_ResponseCard old) {
    super.didUpdateWidget(old);
    // Border animation
    if (widget.borderSpeed != old.borderSpeed) {
      _borderAnim.duration = Duration(milliseconds: widget.borderSpeed);
    }
    final shouldAnimate = widget.streaming && widget.animate;
    final wasAnimating = old.streaming && old.animate;
    if (shouldAnimate && !wasAnimating) {
      _borderAnim.repeat();
    } else if (!shouldAnimate && wasAnimating) {
      _borderAnim.stop();
    }
    // Typing animation — when response text changes (new chars)
    if (widget.response != old.response) {
      _lastResponse = widget.response;
      if (widget.streaming && widget.animate) {
        final oldLen = _visibleChars;
        _typingAnim.dispose();
        _typingAnim = AnimationController(
          vsync: this,
          duration: Duration(
            milliseconds: ((widget.response.length - oldLen) * 30).clamp(
              100,
              4000,
            ),
          ),
          lowerBound: oldLen / widget.response.length.clamp(1, 99999),
        );
        _typingAnim.addListener(_updateVisibleChars);
        _typingAnim.forward();
      } else {
        _visibleChars = widget.response.length;
      }
    }
    if (!widget.streaming) {
      _visibleChars = widget.response.length;
    }
  }

  @override
  void dispose() {
    _borderAnim.dispose();
    _typingAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fullText =
        widget.response.trim().isEmpty
            ? 'YoLo! Here is what I found for you...'
            : widget.response.trim();
    final displayText =
        widget.streaming
            ? fullText.substring(0, _visibleChars.clamp(0, fullText.length))
            : fullText;
    final hasMermaid = displayText.contains('```mermaid');
    return LayoutBuilder(
      builder: (context, constraints) {
        // Total available height (bounded by parent ConstrainedBox, e.g. 170px).
        // Subtract label row + gap to get max body height.
        const labelRowHeight = 34.0;
        final maxH =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 250.0;
        final contentMaxH = (maxH - labelRowHeight - 40).clamp(40.0, 600.0);
        // ↑ 40 = AnimatedContainer padding (20 top + 20 bottom)

        // Column(mainAxisSize.min) shrinks to content.
        // AnimatedContainer contains ConstrainedBox(maxH=contentMaxH) + CustomScrollView(shrinkWrap).
        // This achieves: short text → small card; long text → capped + scrollable.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedBuilder(
              animation: _borderAnim,
              builder:
                  (ctx, child) => CustomPaint(
                    painter:
                        widget.streaming
                            ? _RunningBorderPainter(
                              progress: _borderAnim.value,
                              radius: 28,
                            )
                            : null,
                    child: child,
                  ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 620),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                decoration: BoxDecoration(
                  color: const Color(0xF2181A24),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(
                        0xFF9B6BFF,
                      ).withValues(alpha: widget.streaming ? 0.30 : 0.08),
                      blurRadius: widget.streaming ? 40 : 18,
                      spreadRadius: -6,
                    ),
                  ],
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: contentMaxH),
                  child: hasMermaid
                      ? MarkdownDocumentPreview(content: displayText)
                      : CustomScrollView(
                        shrinkWrap: true,
                        physics: const ClampingScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: MarkdownBody(
                              data: displayText,
                              softLineBreak: true,
                              selectable: false,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  fontSize: widget.fontSize,
                                  height: 1.52,
                                  fontWeight: FontWeight.w500,
                                  shadows:
                                      widget.streaming
                                          ? const [
                                            Shadow(
                                              color: Color(0x889B6BFF),
                                              blurRadius: 14,
                                            ),
                                          ]
                                          : const [],
                                ),
                                h1: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.98),
                                  fontSize: widget.fontSize + 5,
                                  height: 1.25,
                                  fontWeight: FontWeight.w800,
                                ),
                                h2: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.98),
                                  fontSize: widget.fontSize + 3,
                                  height: 1.3,
                                  fontWeight: FontWeight.w800,
                                ),
                                h3: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.98),
                                  fontSize: widget.fontSize + 1,
                                  height: 1.35,
                                  fontWeight: FontWeight.w700,
                                ),
                                a: TextStyle(
                                  color: const Color(0xFF8BD8FF),
                                  fontSize: widget.fontSize,
                                  decoration: TextDecoration.underline,
                                ),
                                code: TextStyle(
                                  color: const Color(0xFF8BD8FF),
                                  fontSize: widget.fontSize - 1,
                                  backgroundColor: const Color(0x66101420),
                                ),
                                codeblockPadding: const EdgeInsets.all(10),
                                codeblockDecoration: BoxDecoration(
                                  color: const Color(0xAA101420),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: _GlowText(
                widget.actionLabel,
                size: 14,
                color: const Color(0xFF8C8D9E),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Animated border painter — draws a running gradient stroke around the card.
class _RunningBorderPainter extends CustomPainter {
  _RunningBorderPainter({required this.progress, required this.radius});

  final double progress;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().first;
    final totalLen = metrics.length;

    final headLen = totalLen * 0.30;
    final startDist = progress * totalLen;

    // Draw multiple sub-segments with fading opacity for gradient trail effect
    const segments = 12;
    for (var s = 0; s < segments; s++) {
      final segFrac = s / segments;
      final segStart = (startDist + headLen * segFrac) % totalLen;
      final segEnd =
          (startDist + headLen * (segFrac + 1.0 / segments)) % totalLen;

      Path sub;
      if (segEnd > segStart) {
        sub = metrics.extractPath(segStart, segEnd);
      } else {
        sub = metrics.extractPath(segStart, totalLen);
        sub.addPath(metrics.extractPath(0, segEnd), Offset.zero);
      }

      // Color transitions along the trail: head bright, tail fading
      final t = segFrac;
      final color =
          Color.lerp(
            const Color(0xFFFF60DD), // tail: pink
            const Color(0xFF64DFFF), // head: cyan
            t,
          )!;
      final alpha = (0.15 + t * 0.85).clamp(0.0, 1.0);

      final paint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0 + t * 0.5
            ..strokeCap = StrokeCap.round
            ..color = color.withValues(alpha: alpha);

      canvas.drawPath(sub, paint);
    }

    // Bright glow at head position
    final headPos = metrics.getTangentForOffset(
      (startDist + headLen) % totalLen,
    );
    if (headPos != null) {
      final glowPaint =
          Paint()
            ..color = const Color(0xFF64DFFF).withValues(alpha: 0.6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(headPos.position, 3, glowPaint);
    }
  }

  @override
  bool shouldRepaint(_RunningBorderPainter old) => old.progress != progress;
}

// ─────────────────────────── BLOB ORB PAINTER ───────────────────────────────
// Draws 5 large overlapping irregular translucent blobs with visible edges,
// matching the reference: organic shapes, NOT circles.

enum _OrbMode { ready, recording, sending, thinking, response }

/// Shared plectrum shape + painting used by both _BlobOrbPainter and
/// SinglePlectrumPreview. Single source of truth for the shape.
Path _buildPlectrumPath({
  required Offset center,
  required double rw,
  required double rh,
  required double rotation,
}) {
  final cosR = math.cos(rotation);
  final sinR = math.sin(rotation);

  // 10-point organic plectrum shape
  final pts = <Offset>[
    Offset(0, -rh * 0.90),
    Offset(rw * 0.65, -rh * 0.65),
    Offset(rw * 0.95, -rh * 0.05),
    Offset(rw * 0.72, rh * 0.48),
    Offset(rw * 0.28, rh * 0.78),
    Offset(0, rh * 0.88),
    Offset(-rw * 0.30, rh * 0.76),
    Offset(-rw * 0.74, rh * 0.44),
    Offset(-rw * 0.92, -rh * 0.10),
    Offset(-rw * 0.60, -rh * 0.68),
  ];

  Offset rotate(Offset p) => Offset(
    center.dx + p.dx * cosR - p.dy * sinR,
    center.dy + p.dx * sinR + p.dy * cosR,
  );
  final rPts = pts.map(rotate).toList();

  // Smooth Catmull-Rom cubic spline (divisor 5)
  final path = Path();
  path.moveTo(rPts[0].dx, rPts[0].dy);
  for (var i = 0; i < rPts.length; i++) {
    final p0 = rPts[i];
    final p1 = rPts[(i + 1) % rPts.length];
    final prev = rPts[(i - 1 + rPts.length) % rPts.length];
    final next2 = rPts[(i + 2) % rPts.length];
    final cp1 = Offset(
      p0.dx + (p1.dx - prev.dx) / 5,
      p0.dy + (p1.dy - prev.dy) / 5,
    );
    final cp2 = Offset(
      p1.dx - (next2.dx - p0.dx) / 5,
      p1.dy - (next2.dy - p0.dy) / 5,
    );
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p1.dx, p1.dy);
  }
  path.close();
  return path;
}

/// Paint a single plectrum shape with shadow + rotation-aware gradient.
/// Wide end (top before rotation) = opaque, narrow tip (bottom) = transparent.
/// Gradient rotates WITH the shape.
void _paintPlectrum(
  Canvas canvas,
  Path path,
  double rotation,
  Color color,
  Offset center,
  double shapeHeight, {
  double intensity = 1.0,
}) {
  // Shadow
  final shadowPaint =
      Paint()
        ..color = color.withValues(alpha: 0.12 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
  canvas.drawPath(path, shadowPaint);

  // Gradient endpoints match exactly the shape's top/bottom after rotation.
  // Unrotated: top=(0, -h/2), bottom=(0, +h/2).
  // After rotation by `rotation`: apply same cos/sin transform.
  final cosR = math.cos(rotation);
  final sinR = math.sin(rotation);
  final halfH = shapeHeight * 0.5;

  // Wide end (top of unrotated shape) → OPAQUE
  final gradStart = Offset(
    center.dx + 0 * cosR - (-halfH) * sinR, // = center.dx + halfH * sinR
    center.dy + 0 * sinR + (-halfH) * cosR, // = center.dy - halfH * cosR
  );
  // Narrow tip (bottom of unrotated shape) → TRANSPARENT
  final gradEnd = Offset(
    center.dx + 0 * cosR - halfH * sinR, // = center.dx - halfH * sinR
    center.dy + 0 * sinR + halfH * cosR, // = center.dy + halfH * cosR
  );

  final fillPaint =
      Paint()
        ..shader = ui.Gradient.linear(
          gradStart,
          gradEnd,
          [
            color.withValues(
              alpha: 0.55 * intensity,
            ), // wide end: fully visible
            color.withValues(alpha: 0.45 * intensity), // still visible
            color.withValues(alpha: 0.18 * intensity), // ~55%: fading
            color.withValues(alpha: 0.05 * intensity), // ~80%: almost gone
            color.withValues(alpha: 0.0), // tip: fully transparent
          ],
          [0.0, 0.3, 0.55, 0.8, 1.0],
        );
  canvas.drawPath(path, fillPaint);
}

class _BlobOrbPainter extends CustomPainter {
  const _BlobOrbPainter({
    required this.progress,
    required this.mode,
    required this.bgColor,
    required this.ovalWidth,
    required this.ovalHeight,
  });

  final double progress;
  final _OrbMode mode;
  final Color bgColor;
  final double ovalWidth;
  final double ovalHeight;

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
    (angle: 1.25, scale: 0.98, aspect: 0.92, phase: 1.26),
    (angle: 2.50, scale: 1.04, aspect: 0.84, phase: 2.51),
    (angle: 3.90, scale: 0.96, aspect: 0.90, phase: 3.77),
    (angle: 5.10, scale: 1.00, aspect: 0.86, phase: 5.03),
  ];

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
    final glowPaint =
        Paint()
          ..shader = RadialGradient(
            colors: [
              colors[0].withValues(alpha: 0.10 * intensity),
              colors[2].withValues(alpha: 0.06 * intensity),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: center, radius: r * 1.35))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(center, r * 1.2, glowPaint);

    // Draw 5 plectrum blobs using shared painter
    for (var i = 0; i < 5; i++) {
      final cfg = _blobConfigs[i];
      final t = progress * 2 * math.pi + cfg.phase;
      final blobAngle = cfg.angle + t;

      final dx = math.cos(blobAngle) * r * 0.32;
      final dy = math.sin(blobAngle) * r * 0.26;
      final blobCenter = Offset(center.dx + dx, center.dy + dy);

      final blobW = r * 2 * cfg.scale * (0.72 + math.sin(t) * 0.04);
      final blobH = blobW * cfg.aspect;

      final rng = math.Random(i * 42 + 7);
      final wobble =
          1.0 +
          math.sin(t * 2 + rng.nextDouble() * 0.3) * 0.03 +
          math.cos(t * 1 + rng.nextDouble() * 0.2) * 0.02;
      final rw = blobW / 2 * wobble;
      final rh = blobH / 2 * wobble;
      final rot = rng.nextDouble() * math.pi * 2 + t * 1;

      final path = _buildPlectrumPath(
        center: blobCenter,
        rw: rw,
        rh: rh,
        rotation: rot,
      );
      _paintPlectrum(
        canvas,
        path,
        rot,
        colors[i],
        blobCenter,
        rh * 2,
        intensity: intensity,
      );
    }

    // Center overlay: horizontal oval in theme color
    final ovalW = r * ovalWidth;
    final ovalH = r * ovalHeight;
    final ovalRect = Rect.fromCenter(
      center: center,
      width: ovalW * 2,
      height: ovalH * 2,
    );

    final centerPaint =
        Paint()
          ..shader = RadialGradient(
            colors: [
              bgColor,
              bgColor,
              bgColor.withValues(alpha: 0.70),
              bgColor.withValues(alpha: 0.25),
              bgColor.withValues(alpha: 0.05),
              bgColor.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.25, 0.45, 0.65, 0.85, 1.0],
          ).createShader(ovalRect);

    // Draw as oval path
    final centerPath = Path()..addOval(ovalRect);
    canvas.drawPath(centerPath, centerPaint);
  }

  @override
  bool shouldRepaint(covariant _BlobOrbPainter old) =>
      old.progress != progress ||
      old.mode != mode ||
      old.bgColor != bgColor ||
      old.ovalWidth != ovalWidth ||
      old.ovalHeight != ovalHeight;
}

// ─────────────────────────── waveform ────────────────────────────────────────

class _Waveform extends StatefulWidget {
  const _Waveform({
    required this.animate,
    this.flip = false,
    this.barCount = 22,
    this.amplitude = 0.85,
    this.speed = 1400,
  });

  final bool animate;
  final bool flip;
  final int barCount;
  final double amplitude;
  final int speed;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform> with TickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.speed),
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
    if (widget.speed != old.speed) {
      _c.dispose();
      _c = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: widget.speed),
      );
      if (widget.animate) _c.repeat();
    } else if (widget.animate != old.animate) {
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
    builder:
        (ctx, _) => CustomPaint(
          painter: _WaveformPainter(
            progress: widget.animate ? _c.value : 0.42,
            flip: widget.flip,
            barCount: widget.barCount,
            amplitude: widget.amplitude,
          ),
        ),
  );
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.progress,
    required this.flip,
    this.barCount = 22,
    this.amplitude = 0.85,
  });

  final double progress;
  final bool flip;
  final int barCount;
  final double amplitude;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final count = barCount.clamp(6, 60);
    final t = progress * 2 * math.pi;

    // Build smooth organic wave path (filled curves, not bars)
    for (var layer = 0; layer < 3; layer++) {
      final phaseShift = layer * 1.2;
      final ampScale = amplitude * (1.0 - layer * 0.25);
      final path = Path();
      path.moveTo(flip ? size.width : 0, cy);

      final points = <Offset>[];
      for (var i = 0; i <= count; i++) {
        final frac = i / count;
        final x = frac * size.width;
        // Multi-frequency organic wave (all t multipliers must be integers for seamless loop)
        final wave =
            math.sin(t + frac * 8 + phaseShift) * 0.5 +
            math.sin(t * 2 + frac * 12 + phaseShift * 1.5) * 0.3 +
            math.cos(t * 3 + frac * 5 + phaseShift * 0.7) * 0.2;
        // Taper at edges
        final envelope = math.sin(frac * math.pi).clamp(0.0, 1.0);
        final y = cy + wave * size.height * 0.4 * ampScale * envelope;
        points.add(Offset(flip ? size.width - x : x, y));
      }

      // Draw smooth curve through points
      path.moveTo(points.first.dx, cy);
      path.lineTo(points.first.dx, points.first.dy);
      for (var i = 0; i < points.length - 1; i++) {
        final p0 = points[i];
        final p1 = points[i + 1];
        final cpx = (p0.dx + p1.dx) / 2;
        path.cubicTo(cpx, p0.dy, cpx, p1.dy, p1.dx, p1.dy);
      }
      // Close back to center line
      path.lineTo(points.last.dx, cy);
      path.close();

      final colorStart =
          Color.lerp(
            const Color(0xFF66D4FF),
            const Color(0xFFFF6EE0),
            layer / 2.0,
          )!;
      final colorEnd =
          Color.lerp(
            const Color(0xFFB980FF),
            const Color(0xFF4066FF),
            layer / 2.0,
          )!;

      final paint =
          Paint()
            ..style = PaintingStyle.fill
            ..shader = LinearGradient(
              colors: [
                colorStart.withValues(alpha: 0.45 - layer * 0.10),
                colorEnd.withValues(alpha: 0.45 - layer * 0.10),
              ],
            ).createShader(Offset.zero & size);

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress ||
      old.flip != flip ||
      old.barCount != barCount ||
      old.amplitude != amplitude;
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
      builder:
          (ctx, _) => CustomPaint(
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
    final arrow =
        Paint()
          ..color = const Color(0xFFC081FF)
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
    final path =
        Path()
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
  const _OrbitParticles({required this.animate, this.scale = 1.0});

  final bool animate;
  final double scale;

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
    builder:
        (ctx, _) => CustomPaint(
          size: Size(320 * widget.scale, 320 * widget.scale),
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
      radiusBase: 0.50 + rng.nextDouble() * 0.40,
      angleOffset: rng.nextDouble() * 2 * math.pi,
      size: 1.0 + rng.nextDouble() * 2.4,
      speed: (1 + rng.nextInt(3)).toDouble(), // integer 1,2,3 for seamless loop
      colorT: rng.nextDouble(),
      bright: rng.nextDouble() > 0.70,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Center shifted up so particles orbit above vertical midpoint
    final center = Offset(size.width / 2, size.height * 0.42);
    final halfW = size.width / 2;
    final paint = Paint();

    for (final p in _particles) {
      final angle = progress * 2 * math.pi * p.speed + p.angleOffset;
      final orbitR = halfW * p.radiusBase;
      // Slightly elliptical
      final x = center.dx + math.cos(angle) * orbitR;
      final y = center.dy + math.sin(angle) * orbitR * 0.72;

      final color =
          Color.lerp(
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
    builder:
        (ctx, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(4, (i) {
            final w = math.sin(_c.value * 2 * math.pi + i * 0.7);
            final color =
                Color.lerp(
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

// ─────────────────────────── single plectrum preview ─────────────────────────

/// Debug widget — renders a single plectrum shape for visual tuning.
class SinglePlectrumPreview extends StatefulWidget {
  const SinglePlectrumPreview({
    super.key,
    this.color = const Color(0xFF3CE8FF),
    this.rotation = 0.0,
    this.size = 200.0,
  });

  final Color color;
  final double rotation;
  final double size;

  @override
  State<SinglePlectrumPreview> createState() => _SinglePlectrumPreviewState();
}

class _SinglePlectrumPreviewState extends State<SinglePlectrumPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder:
        (ctx, _) => CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _SinglePlectrumPainter(
            color: widget.color,
            rotation: widget.rotation,
            progress: _anim.value,
          ),
        ),
  );
}

class _SinglePlectrumPainter extends CustomPainter {
  const _SinglePlectrumPainter({
    required this.color,
    required this.rotation,
    required this.progress,
  });

  final Color color;
  final double rotation;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    final t = progress * 2 * math.pi;
    final wobble = 1.0 + math.sin(t * 2) * 0.02;
    final rw = r * 0.85 * wobble;
    final rh = r * 0.80 * wobble;
    final rot = rotation + t * 1;

    final path = _buildPlectrumPath(
      center: center,
      rw: rw,
      rh: rh,
      rotation: rot,
    );
    _paintPlectrum(canvas, path, rot, color, center, rh * 2);
  }

  @override
  bool shouldRepaint(covariant _SinglePlectrumPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.rotation != rotation;
}
