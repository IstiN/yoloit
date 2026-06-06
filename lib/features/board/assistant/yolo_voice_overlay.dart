import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/preview/widgets/markdown_document_preview.dart';

// ─── brightness-aware palette for the voice overlay ─────────────────────────

class _OverlayPalette {
  _OverlayPalette._(this.colors, this._dark);

  factory _OverlayPalette.of(BuildContext context) => _OverlayPalette._(
    context.appColors,
    Theme.of(context).brightness == Brightness.dark,
  );

  final AppColorScheme colors;
  final bool _dark;

  // Response card gradient background
  List<Color> get cardGradient =>
      _dark
          ? [
            colors.surface.withValues(alpha: 0.95),
            colors.surface.withValues(alpha: 0.85),
            colors.surface.withValues(alpha: 0.43),
            colors.surface.withValues(alpha: 0.10),
          ]
          : [
            colors.surfaceHighlight.withValues(alpha: 0.95),
            colors.surfaceHighlight.withValues(alpha: 0.85),
            colors.surfaceHighlight.withValues(alpha: 0.43),
            colors.surfaceHighlight.withValues(alpha: 0.10),
          ];

  // Main text color in response card
  Color get textHigh =>
      colors.textPrimary.withValues(alpha: _dark ? 0.95 : 0.88);

  Color get textHeading =>
      colors.textPrimary.withValues(alpha: _dark ? 0.98 : 0.92);

  // Tool log line text
  Color get textTool =>
      colors.textPrimary.withValues(alpha: _dark ? 0.75 : 0.65);

  // Action label ('Tap YoLo to speak')
  Color get actionLabel => _dark ? colors.textMuted : colors.textSecondary;

  // Code / link accent
  Color get codeAccent => colors.accentBlue;

  // Code block background
  Color get codeBg => (_dark ? colors.surface : colors.surfaceHighlight)
      .withValues(alpha: _dark ? 0.40 : 0.18);

  Color get codeBlockBg => (_dark ? colors.surfaceElevated : colors.surface)
      .withValues(alpha: _dark ? 0.67 : 0.25);

  // Text shadow for response text
  Color get textShadow =>
      _dark ? colors.primary.withValues(alpha: 0.53) : Colors.transparent;

  // Box shadow glow colors
  Color cardGlow(bool streaming) => colors.primaryLight.withValues(
    alpha: _dark ? (streaming ? 0.30 : 0.20) : (streaming ? 0.12 : 0.06),
  );

  Color get cardGlow2 =>
      colors.accentBlue.withValues(alpha: _dark ? 0.14 : 0.06);

  // Glow text shadow
  Color get glowTextShadow => (_dark ? colors.background : colors.surface)
      .withValues(alpha: _dark ? 0.7 : 0.5);
}

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
    this.micAmplitudeStream,
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

  /// Real-time mic amplitude stream (0.0–1.0). When provided, the waveform
  /// reacts to the actual microphone input instead of animating freely.
  final Stream<double>? micAmplitudeStream;

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
    if (old.status != widget.status) {
      // ignore: avoid_print
      print(
        '[VoiceOverlay] status widget: ${old.status} → ${widget.status} (shown=${_shown.name})',
      );
      _maybeTransition();
    }
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
    final target = _VS.from(widget.status);
    if (target == _shown) return;

    // ignore: avoid_print
    print(
      '[VoiceOverlay] _maybeTransition: ${_shown.name} → ${target.name} (pending=$_pendingTransition)',
    );

    // Tool/text streaming should surface immediately in the response card
    // instead of walking through intermediate processing/thinking states.
    // This bypass must come BEFORE the _pendingTransition guard so that a
    // delayed transition never blocks the responding state from showing.
    if (target == _VS.responding) {
      // ignore: avoid_print
      print(
        '[VoiceOverlay] immediate → responding (cancelled pending=$_pendingTransition)',
      );
      _pendingTransition = false; // cancel any pending delayed transition
      setState(() {
        _shown = target;
        _shownAt = DateTime.now();
      });
      return;
    }

    if (_pendingTransition) return;

    final elapsed = DateTime.now().difference(_shownAt).inMilliseconds;
    final wait = _shown.minMs - elapsed;

    // ignore: avoid_print
    print('[VoiceOverlay] minMs=${_shown.minMs} elapsed=$elapsed wait=$wait');

    if (wait > 0) {
      _pendingTransition = true;
      Future.delayed(Duration(milliseconds: wait), () {
        _pendingTransition = false;
        if (!mounted) return;
        final latest = _VS.from(widget.status);
        // ignore: avoid_print
        print(
          '[VoiceOverlay] delayed fired: _shown=${_shown.name} latest=${latest.name}',
        );
        if (latest == _shown) return;

        // Step to next sequential state, not jump to latest
        final curIdx = _order.indexOf(_shown);
        final latestIdx = _order.indexOf(latest);
        final nextState =
            (latestIdx > curIdx + 1) ? _order[curIdx + 1] : latest;

        // ignore: avoid_print
        print(
          '[VoiceOverlay] delayed step: ${_shown.name} → ${nextState.name}',
        );
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

      // ignore: avoid_print
      print(
        '[VoiceOverlay] immediate step: ${_shown.name} → ${nextState.name}',
      );
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

  // Keep listening waves and status text visually coupled to the orb position.
  // Compute the alignment so the orbit center (at 60 % of particle widget height)
  // lands exactly on the orb centre, regardless of particleScale / orbAlignY.
  double get _particleAlignY {
    const orbitFraction =
        0.60; // must stay in sync with _ScatteredParticlesPainter
    final orbH = _orbSize * widget.orbScale;
    final particleH = 320.0 * widget.particleScale;
    final denominator = _kH - particleH;
    if (denominator <= 0) return _orbAlign.y; // degenerate: widget fills parent
    final orbCenterY = (_kH - orbH) * (_orbAlign.y + 1) / 2 + orbH / 2;
    final alignY =
        2 * (orbCenterY - orbitFraction * particleH) / denominator - 1;
    return alignY.clamp(-0.9, 2.0);
  }

  double get _waveAlignY => (_orbAlign.y - 0.06).clamp(-0.9, 0.95);
  double get _textAlignY => (_orbAlign.y + 0.34).clamp(-0.2, 0.95);
  double get _responseCardBottomPadding {
    final orbCenterY = ((_orbAlign.y + 1) * 0.5) * _kH;
    final orbRadius = (_orbSize * widget.orbScale) * 0.5;
    final cardBottomY = orbCenterY - orbRadius + 26;
    return (_kH - cardBottomY).clamp(44.0, 180.0);
  }

  // ── build ─────────────────────────────────────────────────────────────────

  static const _kW = 720.0;
  static const _kH = 460.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
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
                  child: AnimatedAlign(
                    alignment: Alignment(0, _particleAlignY),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    child: _OrbitParticles(
                      animate: (_isThinking || _isSending) && widget.animate,
                      scale: widget.particleScale,
                      colors: colors,
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
                    alignment: Alignment(-widget.waveSpread, _waveAlignY),
                    child: SizedBox(
                      width: widget.waveWidth,
                      height: 80,
                      child: _Waveform(
                        animate: _isListening && widget.animate,
                        flip: true,
                        barCount: widget.waveBarCount,
                        amplitude: widget.waveAmplitude,
                        speed: widget.waveSpeed,
                        micAmplitudeStream: widget.micAmplitudeStream,
                        colors: colors,
                      ),
                    ),
                  ),
                ),

                // ── waveform right (listening) ─────────────────────────
                AnimatedOpacity(
                  opacity: _isListening ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 600),
                  child: Align(
                    alignment: Alignment(widget.waveSpread, _waveAlignY),
                    child: SizedBox(
                      width: widget.waveWidth,
                      height: 80,
                      child: _Waveform(
                        animate: _isListening && widget.animate,
                        barCount: widget.waveBarCount,
                        amplitude: widget.waveAmplitude,
                        speed: widget.waveSpeed,
                        micAmplitudeStream: widget.micAmplitudeStream,
                        colors: colors,
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
                                      colors: colors,
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
                        padding: EdgeInsets.only(
                          bottom: _responseCardBottomPadding,
                        ),
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
                              colors: colors,
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
                  child: AnimatedAlign(
                    alignment: Alignment(0, _textAlignY),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
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
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.10),
                                    end: Offset.zero,
                                  ).animate(
                                    CurvedAnimation(
                                      parent: anim,
                                      curve: Curves.easeOutCubic,
                                    ),
                                  ),
                                  child: child,
                                ),
                              ),
                          child: _textContent(),
                        ),
                      ],
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

  Widget _orbLabel(double sz) {
    final colors = context.appColors;
    return RepaintBoundary(
      child: ShaderMask(
        shaderCallback:
            (b) => LinearGradient(
              colors:
                  widget.titleColor != null
                      ? [widget.titleColor!, widget.titleColor!]
                      : [colors.orbCyan, colors.orbPurple],
            ).createShader(b),
        child: Text(
          'YoLo',
          style: TextStyle(
            color: Colors.white,
            fontSize: widget.titleFontSize ?? sz * 0.15,
            fontWeight: FontWeight.w300,
            letterSpacing: -0.8,
            shadows: [
              Shadow(
                color: colors.orbCyan.withValues(alpha: 0.67),
                blurRadius: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textContent() {
    final colors = context.appColors;
    return KeyedSubtree(
      key: ValueKey(_shown),
      child: switch (_shown) {
        _VS.idle =>
          widget.showIdleHint
              ? _TextBlock(
                primary: 'Click or speak to start',
                primaryColor: colors.textSecondary,
                primarySize: 15,
              )
              : const SizedBox.shrink(),
        _VS.listening => _TextBlock(
          primary: 'Recording...',
          primaryColor: colors.textPrimary,
          primarySize: 15,
          secondary: 'Esc to cancel  •  Space to send',
          secondaryColor: colors.textSecondary,
          secondarySize: 12,
        ),
        _VS.processing => _TextBlock(
          primary: 'Processing...',
          primaryColor: colors.accentBlue,
          primarySize: 16,
          primaryBold: true,
          secondary: 'Please wait',
          secondaryColor: colors.textSecondary,
          secondarySize: 12,
        ),
        _VS.thinking => _TextBlock(
          primary: 'Thinking...',
          primaryColor: colors.primaryLight,
          primarySize: 16,
          primaryBold: true,
          secondary: 'Waiting for response...',
          secondaryColor: colors.textSecondary,
          secondarySize: 12,
        ),
        _VS.responding => const SizedBox.shrink(),
      },
    );
  }
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
    final pal = _OverlayPalette.of(context);
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: weight,
        shadows: [
          Shadow(color: color.withValues(alpha: 0.45), blurRadius: 12),
          Shadow(color: pal.glowTextShadow, blurRadius: 6),
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
    required this.colors,
    this.animate = true,
    this.fontSize = 18.0,
    this.borderSpeed = 1200,
    this.actionLabel = 'Tap to close',
  });

  final String response;
  final bool streaming;
  final AppColorScheme colors;
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

  /// Fade-in controller: animates 0→1 when streaming stops.
  late final AnimationController _crossfadeAnim;
  late final ScrollController _scrollCtrl;
  int _visibleChars = 0;
  String _lastResponse = '';
  bool _isCrossfading = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _borderAnim = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.borderSpeed),
    );
    if (widget.streaming && widget.animate) _borderAnim.repeat();

    _crossfadeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _crossfadeAnim.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _isCrossfading = false);
      }
    });

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

    // Streaming just stopped → simple fade-in of final answer (no frozen tools content).
    if (old.streaming && !widget.streaming && widget.animate) {
      _isCrossfading = true;
      _crossfadeAnim.value = 0.0;
      _crossfadeAnim.forward();
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
          lowerBound: (oldLen / widget.response.length.clamp(1, 99999)).clamp(
            0.0,
            0.99,
          ),
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
    // Auto-scroll to bottom when new tool log lines are added
    if (widget.response.length > old.response.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients &&
            _scrollCtrl.position.maxScrollExtent > 0) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _borderAnim.dispose();
    _typingAnim.dispose();
    _crossfadeAnim.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _displayText(
    String response, {
    bool streaming = false,
    int visibleChars = 0,
  }) {
    final full =
        response.trim().isEmpty
            ? 'YoLo! Here is what I found for you...'
            : response.trim();
    return streaming
        ? full.substring(0, visibleChars.clamp(0, full.length))
        : full;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final displayText = _displayText(
      widget.response,
      streaming: widget.streaming,
      visibleChars: _visibleChars,
    );
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

        // Build the content body, optionally with fade-in animation on final answer.
        final newBody = _buildContentBody(displayText, hasMermaid, contentMaxH);
        final body =
            _isCrossfading
                ? AnimatedBuilder(
                  animation: _crossfadeAnim,
                  builder: (context, child) {
                    final t = Curves.easeOut.transform(_crossfadeAnim.value);
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, (1.0 - t) * 12),
                        child: child,
                      ),
                    );
                  },
                  child: newBody,
                )
                : newBody;

        // Column(mainAxisSize.min) shrinks to content.
        // AnimatedContainer contains ConstrainedBox(maxH=contentMaxH) + CustomScrollView(shrinkWrap).
        // This achieves: short text → small card; long text → capped + scrollable.
        final pal = _OverlayPalette.of(context);
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
                              colors: colors,
                            )
                            : null,
                    child: child,
                  ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 620),
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: pal.cardGradient,
                          stops: const [0.0, 0.45, 0.78, 1.0],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: pal.cardGlow(widget.streaming),
                            blurRadius: widget.streaming ? 40 : 24,
                            spreadRadius: -6,
                          ),
                          BoxShadow(
                            color: pal.cardGlow2,
                            blurRadius: 26,
                            spreadRadius: -14,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: body,
                    ),
                    // Shimmer sweep overlay while streaming.
                    if (widget.streaming)
                      Positioned.fill(
                        child: _ShimmerSweep(
                          animate: widget.animate,
                          colors: colors,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: _GlowText(
                widget.actionLabel,
                size: 14,
                color: pal.actionLabel,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContentBody(String text, bool hasMermaid, double maxH) {
    if (hasMermaid) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: RepaintBoundary(
          child: MarkdownDocumentPreview(content: text),
        ),
      );
    }

    // Split tool log lines (✅/❌/⚙️ prefix) from regular assistant text
    final allLines = text.split('\n');
    final toolLines = <String>[];
    var nonToolStart = 0;
    for (var i = 0; i < allLines.length; i++) {
      final l = allLines[i].trimLeft();
      if (l.startsWith('✅') || l.startsWith('❌') || l.startsWith('⚙️')) {
        toolLines.add(allLines[i]);
        nonToolStart = i + 1;
      } else if (l.isEmpty) {
        nonToolStart = i + 1; // skip blank separator lines
      } else {
        nonToolStart = i;
        break;
      }
    }
    final restText =
        nonToolStart < allLines.length
            ? allLines.sublist(nonToolStart).join('\n').trim()
            : '';

    final pal = _OverlayPalette.of(context);
    final mdStyle = MarkdownStyleSheet(
      p: TextStyle(
        color: pal.textHigh,
        fontSize: widget.fontSize,
        height: 1.52,
        fontWeight: FontWeight.w500,
        shadows: [Shadow(color: pal.textShadow, blurRadius: 14)],
      ),
      h1: TextStyle(
        color: pal.textHeading,
        fontSize: widget.fontSize + 5,
        height: 1.25,
        fontWeight: FontWeight.w800,
      ),
      h2: TextStyle(
        color: pal.textHeading,
        fontSize: widget.fontSize + 3,
        height: 1.3,
        fontWeight: FontWeight.w800,
      ),
      h3: TextStyle(
        color: pal.textHeading,
        fontSize: widget.fontSize + 1,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
      a: TextStyle(
        color: pal.codeAccent,
        fontSize: widget.fontSize,
        decoration: TextDecoration.underline,
      ),
      code: TextStyle(
        color: pal.codeAccent,
        fontSize: widget.fontSize - 1,
        backgroundColor: pal.codeBg,
      ),
      codeblockPadding: const EdgeInsets.all(10),
      codeblockDecoration: BoxDecoration(
        color: pal.codeBlockBg,
        borderRadius: BorderRadius.circular(10),
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: CustomScrollView(
        controller: _scrollCtrl,
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        slivers: [
          if (toolLines.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildToolLogRow(toolLines[i]),
                childCount: toolLines.length,
              ),
            ),
          if (restText.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.only(top: toolLines.isNotEmpty ? 10 : 0),
              sliver: SliverToBoxAdapter(
                child: RepaintBoundary(
                  child: MarkdownBody(
                    data: restText,
                    softLineBreak: true,
                    selectable: false,
                    styleSheet: mdStyle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolLogRow(String line) {
    final l = line.trimLeft();
    final isDone = l.startsWith('✅');
    final isFailed = l.startsWith('❌');
    final state =
        isDone
            ? _ToolState.done
            : isFailed
            ? _ToolState.failed
            : _ToolState.running;
    final text = l.replaceFirst(RegExp(r'^[✅❌⚙️]\s*'), '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 15,
            child: CustomPaint(
              painter: _ToolStateIconPainter(
                state: state,
                colors: widget.colors,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: _OverlayPalette.of(context).textTool,
                fontSize: 12.5,
                fontFamily: 'monospace',
                height: 1.4,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated border painter — draws a running gradient stroke around the card.
class _RunningBorderPainter extends CustomPainter {
  _RunningBorderPainter({
    required this.progress,
    required this.radius,
    required this.colors,
  });

  final double progress;
  final double radius;
  final AppColorScheme colors;

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

      // Color transitions along the trail: head bright (orbCyan), tail fading (orbPink)
      final t = segFrac;
      final color = Color.lerp(colors.orbPink, colors.orbCyan, t)!;
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
            ..color = colors.orbCyan.withValues(alpha: 0.6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(headPos.position, 3, glowPaint);
    }
  }

  @override
  bool shouldRepaint(_RunningBorderPainter old) =>
      old.progress != progress || old.colors != colors;
}

// ─────────────────────────── tool state icon ──────────────────────────────────

enum _ToolState { done, failed, running }

/// Custom painted icon for tool log rows: circle with check/x/dot.
class _ToolStateIconPainter extends CustomPainter {
  const _ToolStateIconPainter({required this.state, required this.colors});

  final _ToolState state;
  final AppColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    final color = switch (state) {
      _ToolState.done => colors.accentGreen,
      _ToolState.failed => colors.accentRed,
      _ToolState.running => colors.primary,
    };

    // Background fill
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
    );
    // Border
    canvas.drawCircle(
      center,
      r - 0.8,
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );

    final icon =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    if (state == _ToolState.done) {
      final path =
          Path()
            ..moveTo(center.dx - r * 0.33, center.dy + r * 0.02)
            ..lineTo(center.dx - r * 0.05, center.dy + r * 0.38)
            ..lineTo(center.dx + r * 0.40, center.dy - r * 0.32);
      canvas.drawPath(path, icon);
    } else if (state == _ToolState.failed) {
      canvas.drawLine(
        Offset(center.dx - r * 0.28, center.dy - r * 0.28),
        Offset(center.dx + r * 0.28, center.dy + r * 0.28),
        icon,
      );
      canvas.drawLine(
        Offset(center.dx + r * 0.28, center.dy - r * 0.28),
        Offset(center.dx - r * 0.28, center.dy + r * 0.28),
        icon,
      );
    } else {
      // Running: filled dot
      canvas.drawCircle(
        center,
        r * 0.3,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_ToolStateIconPainter old) => old.state != state;
}

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
    required this.colors,
    required this.bgColor,
    required this.ovalWidth,
    required this.ovalHeight,
  });

  final double progress;
  final _OrbMode mode;
  final AppColorScheme colors;
  final Color bgColor;
  final double ovalWidth;
  final double ovalHeight;

  List<Color> get _palette {
    final c = colors.orbCyan;
    final p = colors.orbPurple;
    final k = colors.orbPink;
    return switch (mode) {
      _OrbMode.ready => [
        c,
        Color.lerp(c, p, 0.55)!,
        k,
        Color.lerp(c, p, 0.30)!,
        Color.lerp(p, Colors.white, 0.20)!,
      ],
      _OrbMode.recording => [
        p,
        Color.lerp(p, Colors.black, 0.20)!,
        Color.lerp(k, p, 0.20)!,
        Color.lerp(c, p, 0.68)!,
        Color.lerp(k, p, 0.45)!,
      ],
      _OrbMode.sending => [
        c,
        Color.lerp(c, p, 0.80)!,
        Color.lerp(c, Colors.white, 0.12)!,
        Color.lerp(c, Colors.white, 0.07)!,
        Color.lerp(c, p, 0.70)!,
      ],
      _OrbMode.thinking => [
        Color.lerp(k, p, 0.08)!,
        Color.lerp(p, Colors.black, 0.15)!,
        Color.lerp(p, Colors.white, 0.12)!,
        c,
        k,
      ],
      _OrbMode.response => [
        Color.lerp(c, Colors.white, 0.07)!,
        Color.lerp(k, Colors.white, 0.04)!,
        Color.lerp(p, Colors.white, 0.10)!,
        c,
        Color.lerp(p, Colors.white, 0.27)!,
      ],
    };
  }

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
    final palette = _palette;
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
              palette[0].withValues(alpha: 0.10 * intensity),
              palette[2].withValues(alpha: 0.06 * intensity),
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
        palette[i],
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
      old.colors != colors ||
      old.bgColor != bgColor ||
      old.ovalWidth != ovalWidth ||
      old.ovalHeight != ovalHeight;
}

// ─────────────────────────── waveform ────────────────────────────────────────

class _Waveform extends StatefulWidget {
  const _Waveform({
    required this.animate,
    required this.colors,
    this.flip = false,
    this.barCount = 22,
    this.amplitude = 0.85,
    this.speed = 1400,
    this.micAmplitudeStream,
  });

  final bool animate;
  final AppColorScheme colors;
  final bool flip;
  final int barCount;
  final double amplitude;
  final int speed;
  final Stream<double>? micAmplitudeStream;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform> with TickerProviderStateMixin {
  late AnimationController _c;
  // Smoothed real mic amplitude (0-1). Decays toward target at 0.15/frame.
  double _smoothAmplitude = 0.35;
  double _targetAmplitude = 0.35;
  StreamSubscription<double>? _ampSub;

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
    _subscribeAmplitude();
  }

  void _subscribeAmplitude() {
    _ampSub?.cancel();
    _ampSub = widget.micAmplitudeStream?.listen((v) {
      _targetAmplitude = v.clamp(0.0, 1.0);
    });
  }

  @override
  void didUpdateWidget(_Waveform old) {
    super.didUpdateWidget(old);
    if (widget.micAmplitudeStream != old.micAmplitudeStream) {
      _subscribeAmplitude();
      if (widget.micAmplitudeStream == null) _targetAmplitude = 0.35;
    }
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
    _ampSub?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _c,
      builder: (ctx, _) {
        // Smooth amplitude toward target each frame.
        _smoothAmplitude += (_targetAmplitude - _smoothAmplitude) * 0.18;
        final effectiveAmplitude =
            widget.micAmplitudeStream != null
                ? (_smoothAmplitude * 0.85 + 0.15) // never fully silent
                : widget.amplitude;
        return CustomPaint(
          painter: _WaveformPainter(
            progress: widget.animate ? _c.value : 0.42,
            flip: widget.flip,
            colors: colors,
            amplitude: effectiveAmplitude,
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.progress,
    required this.flip,
    required this.colors,
    this.amplitude = 0.85,
  });

  final double progress;
  final bool flip;
  final AppColorScheme colors;
  final double amplitude;

  // Catmull-Rom → cubic bezier smooth path through sampled points
  static Path _smoothPath(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i > 0 ? i - 1 : 0];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[i + 2 < pts.length ? i + 2 : i + 1];
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final t = progress * 2 * math.pi;

    // Wave lines: (amplCoeff, color, strokeW, glowW, alpha, phase)
    final waveDefs = [
      (1.00, colors.primary, 1.6, 14.0, 0.65, 0.00),
      (0.90, colors.primaryLight, 1.2, 11.0, 0.55, 0.90),
      (0.78, colors.accentBlue, 1.0, 9.0, 0.50, 1.80),
      (
        0.65,
        Color.lerp(colors.primaryLight, colors.primary, 0.45)!,
        0.9,
        8.0,
        0.45,
        2.75,
      ),
      (
        0.52,
        Color.lerp(colors.primaryLight, colors.accentRed, 0.18)!,
        0.8,
        7.0,
        0.40,
        3.70,
      ),
      (
        0.40,
        Color.lerp(colors.accentBlue, colors.surfaceHighlight, 0.10)!,
        0.7,
        6.0,
        0.35,
        4.70,
      ),
      (
        0.28,
        Color.lerp(colors.primaryLight, colors.accentBlue, 0.55)!,
        0.6,
        5.0,
        0.28,
        5.60,
      ),
    ];

    const steps = 80;

    // Gradient direction: full color at orb side (frac=0), transparent at tip (frac=1).
    // flip=false (right arm): orb is at x=0, tip at x=width.
    // flip=true  (left  arm): orb is at x=width, tip at x=0.
    final gradOrbEnd = flip ? Offset(size.width, cy) : Offset(0, cy);
    final gradTipEnd = flip ? Offset(0, cy) : Offset(size.width, cy);

    for (final (coeff, color, strokeW, glowW, alpha, phase) in waveDefs) {
      final pts = <Offset>[];
      for (int i = 0; i <= steps; i++) {
        final frac = i / steps;

        // Cosine taper: full at orb (frac=0), zero at tip (frac=1) — no seam artefacts.
        final env = math.cos(frac * math.pi / 2);

        // Two harmonics, BOTH with integer multipliers → perfect loop seam.
        final wave =
            math.sin(t + frac * math.pi * 2.5 + phase) * 0.65 +
            math.sin(t * 2.0 + frac * math.pi * 4.5 + phase * 1.3) * 0.35;

        final yOff = wave * size.height * 0.46 * amplitude * coeff * env;
        final x = frac * size.width;
        final px = flip ? size.width - x : x;
        pts.add(Offset(px, cy + yOff));
      }

      final path = _smoothPath(pts);

      // Gradient shaders fade wave to transparent at the tip.
      ui.Shader gradShader(double a) => ui.Gradient.linear(
        gradOrbEnd,
        gradTipEnd,
        [color.withValues(alpha: a), color.withValues(alpha: 0.0)],
      );

      // 1. Wide outer glow
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = glowW
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = gradShader(alpha * 0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );

      // 2. Mid fill
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = glowW * 0.45
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = gradShader(alpha * 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );

      // 3. Sharp core line
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = gradShader(alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress ||
      old.flip != flip ||
      old.colors != colors ||
      old.amplitude != amplitude;
}

// ─────────────────────────── shimmer sweep ────────────────────────────────────
// Translucent gradient that sweeps left-to-right over the response card
// while LLM is streaming to indicate live generation.

class _ShimmerSweep extends StatefulWidget {
  const _ShimmerSweep({required this.animate, required this.colors});
  final bool animate;
  final AppColorScheme colors;

  @override
  State<_ShimmerSweep> createState() => _ShimmerSweepState();
}

class _ShimmerSweepState extends State<_ShimmerSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(_ShimmerSweep old) {
    super.didUpdateWidget(old);
    if (widget.animate && !old.animate) _c.repeat();
    if (!widget.animate && old.animate) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        // Sweep band: left-edge from -0.4 to 1.0, width=0.35
        final left = Alignment(-1.8 + t * 3.6, 0);
        final right = Alignment(-1.8 + t * 3.6 + 0.8, 0);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: left,
              end: right,
              colors: [
                Colors.transparent,
                colors.primaryLight.withValues(alpha: 0.08),
                colors.accentBlue.withValues(alpha: 0.14),
                colors.primaryLight.withValues(alpha: 0.08),
                Colors.transparent,
              ],
              stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────── upload beam ─────────────────────────────────────

class _UploadBeam extends StatefulWidget {
  const _UploadBeam({required this.animate, required this.colors});

  final bool animate;
  final AppColorScheme colors;

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
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      width: 80,
      height: 120,
      child: AnimatedBuilder(
        animation: _c,
        builder:
            (ctx, _) => CustomPaint(
              painter: _UploadBeamPainter(
                progress: widget.animate ? _c.value : 0.3,
                colors: colors,
              ),
            ),
      ),
    );
  }
}

class _UploadBeamPainter extends CustomPainter {
  const _UploadBeamPainter({required this.progress, required this.colors});

  final double progress;
  final AppColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    // Arrow head
    final arrow =
        Paint()
          ..color = colors.primaryLight
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
          colors.accentBlue,
          colors.primaryLight,
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
      old.progress != progress || old.colors != colors;
}

// ─────────────────────────── orbit particles ─────────────────────────────────
// Scattered floating dots at varying distances — NOT uniform circle.

class _OrbitParticles extends StatefulWidget {
  const _OrbitParticles({
    required this.animate,
    required this.colors,
    this.scale = 1.0,
  });

  final bool animate;
  final AppColorScheme colors;
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
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _c,
      builder:
          (ctx, _) => CustomPaint(
            size: Size(320 * widget.scale, 320 * widget.scale),
            painter: _ScatteredParticlesPainter(
              progress: widget.animate ? _c.value : 0.2,
              colors: colors,
            ),
          ),
    );
  }
}

class _ScatteredParticlesPainter extends CustomPainter {
  const _ScatteredParticlesPainter({
    required this.progress,
    required this.colors,
  });

  final double progress;
  final AppColorScheme colors;

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
    // Clip to widget bounds so particles never escape into the board canvas.
    canvas.clipRect(Offset.zero & size);
    // Keep particles close to and slightly above the orb, not near top edge.
    final center = Offset(size.width / 2, size.height * 0.60);
    final halfW = size.width / 2;
    final paint = Paint();

    for (final p in _particles) {
      final angle = progress * 2 * math.pi * p.speed + p.angleOffset;
      final orbitR = halfW * p.radiusBase;
      // Slightly elliptical
      final x = center.dx + math.cos(angle) * orbitR;
      final y = center.dy + math.sin(angle) * orbitR * 0.56;

      final color =
          Color.lerp(colors.accentBlue, colors.primaryLight, p.colorT)!;

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
      old.progress != progress || old.colors != colors;
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
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _c,
      builder:
          (ctx, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(4, (i) {
              final w = math.sin(_c.value * 2 * math.pi + i * 0.7);
              final color =
                  Color.lerp(colors.primaryLight, colors.primaryDark, i / 3)!;
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
}

// ─────────────────────────── single plectrum preview ─────────────────────────

/// Debug widget — renders a single plectrum shape for visual tuning.
class SinglePlectrumPreview extends StatefulWidget {
  const SinglePlectrumPreview({
    super.key,
    this.color,
    this.rotation = 0.0,
    this.size = 200.0,
  });

  final Color? color;
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
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _anim,
      builder:
          (ctx, _) => CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _SinglePlectrumPainter(
              color: widget.color ?? colors.accentBlue,
              rotation: widget.rotation,
              progress: _anim.value,
            ),
          ),
    );
  }
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

// ─────────────────────────── YoLo orb preview widget ─────────────────────────

/// A compact, animated YoLo orb preview intended for use in the settings UI.
///
/// Renders the orb in its "ready" state using the current theme's orb colours
/// (`orbCyan`, `orbPurple`, `orbPink`).  Automatically reacts to theme changes.
class YoloOrbPreview extends StatefulWidget {
  const YoloOrbPreview({super.key, this.size = 100});

  final double size;

  @override
  State<YoloOrbPreview> createState() => _YoloOrbPreviewState();
}

class _YoloOrbPreviewState extends State<YoloOrbPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _ctrl,
      builder:
          (_, __) => SizedBox.square(
            dimension: widget.size,
            child: CustomPaint(
              painter: _BlobOrbPainter(
                progress: _ctrl.value,
                mode: _OrbMode.ready,
                colors: colors,
                bgColor: Colors.transparent,
                ovalWidth: widget.size,
                ovalHeight: widget.size,
              ),
            ),
          ),
    );
  }
}
