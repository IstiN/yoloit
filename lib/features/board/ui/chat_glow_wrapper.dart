import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget.dart';

class ChatGlowWrapper extends StatefulWidget {
  const ChatGlowWrapper({
    required this.panelId,
    required this.borderRadius,
    required this.child,
  });

  final String panelId;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<ChatGlowWrapper> createState() => ChatGlowWrapperState();
}

class ChatGlowWrapperState extends State<ChatGlowWrapper>
    with SingleTickerProviderStateMixin {
  // Ticker-driven pulse, throttled to ~30fps. Using a raw Ticker (not
  // AnimationController.repeat or Timer.periodic) so TickerMode — applied
  // by the board when the overview is open or the app is backgrounded —
  // mutes the callback automatically. The visible curve is a triangle wave
  // that matches the previous `AnimationController.repeat(reverse: true)`:
  // 0 → 1 → 0 over [_pulsePeriod] (2400ms), and the per-frame
  // Opacity saveLayer composite is invoked ~30 times/sec instead of 60.
  late final Ticker _pulseTicker;
  final ValueNotifier<double> _pulseValue = ValueNotifier<double>(0.0);
  Duration _lastEmit = Duration.zero;

  /// Total cycle length of the pulse (0 → 1 → 0).
  static const Duration _pulsePeriod = Duration(milliseconds: 2400);

  /// Throttle: emit at most one value update per [_emitInterval]. 33ms is
  /// ≈30fps — smooth enough for a slow glow, halves the per-second
  /// Opacity render-layer composites vs. running at the display refresh
  /// rate.
  static const Duration _emitInterval = Duration(milliseconds: 33);

  ValueNotifier<bool>? _notifier;
  bool _isGlowing = false;

  @override
  void initState() {
    super.initState();
    _pulseTicker = createTicker(_onPulseTick);
    _attachNotifier();
    // The child widget may register its notifier after us; retry next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_notifier == null && mounted) _attachNotifier();
    });
  }

  @override
  void didUpdateWidget(ChatGlowWrapper old) {
    super.didUpdateWidget(old);
    if (old.panelId != widget.panelId) _attachNotifier();
    // Re-attach if notifier appeared late
    if (_notifier == null) _attachNotifier();
  }

  void _attachNotifier() {
    _notifier?.removeListener(_onNotifierChange);
    _notifier = ChatPanelWidget.processingNotifiers[widget.panelId];
    _notifier?.addListener(_onNotifierChange);
    _onNotifierChange();
  }

  void _onNotifierChange() {
    final processing = _notifier?.value ?? false;
    if (processing == _isGlowing) return;
    setState(() => _isGlowing = processing);
    if (processing) {
      _lastEmit = Duration.zero;
      if (!_pulseTicker.isActive) _pulseTicker.start();
    } else {
      _pulseTicker.stop();
      _pulseValue.value = 0.0;
    }
  }

  void _onPulseTick(Duration elapsed) {
    // Throttle: at most one value update every ~33ms. Skipping the update
    // also skips the AnimatedBuilder rebuild and the Opacity render-layer
    // composite (the part that triggers saveLayer).
    if (elapsed - _lastEmit < _emitInterval) return;
    _lastEmit = elapsed;
    final periodMicros = _pulsePeriod.inMicroseconds;
    final phase = (elapsed.inMicroseconds % periodMicros) / periodMicros;
    // Triangle wave 0 → 1 → 0 over the period — same shape as the previous
    // linear reverse animation (0 → 1 over 1200ms, then 1 → 0 over 1200ms).
    final value = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    if (_pulseValue.value != value) _pulseValue.value = value;
  }

  /// Whether the glow ticker is actively scheduling frames.
  ///
  /// Reflects the TickerMode state: when the board is hidden behind the
  /// overview, TickerMode mutes the ticker and we report `false` even
  /// though the ticker is still "started" — its callback is simply not
  /// being invoked.
  @visibleForTesting
  bool get isGlowAnimating => _pulseTicker.isActive && !_pulseTicker.muted;

  /// The pulse value notifier. Tests can listen to it to count the
  /// number of value updates per second (the throttling keeps this
  /// around 30/sec instead of 60/sec at the display refresh rate).
  @visibleForTesting
  ValueNotifier<double> get debugPulseValue => _pulseValue;

  @override
  void dispose() {
    _notifier?.removeListener(_onNotifierChange);
    _pulseTicker.dispose();
    _pulseValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      // The glow blur extends past the panel bounds.
      clipBehavior: Clip.none,
      children: [
        if (_isGlowing)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseValue,
              // The blurred shadow is rasterized ONCE into its own layer
              // (RepaintBoundary). The pulse only animates the layer
              // opacity, which the compositor applies without re-rasterizing
              // the shadow on every frame. The value updates are also
              // throttled to ~30fps (see _onPulseTick) to halve the
              // per-second Opacity saveLayer composites vs. the display
              // refresh rate.
              builder:
                  (context, glow) => Opacity(
                    // 0.25..1.0 matches the previous 20..80 alpha range.
                    opacity: 0.25 + 0.75 * _pulseValue.value,
                    child: glow ?? const SizedBox.shrink(),
                  ),
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    boxShadow: [
                      BoxShadow(
                        color: context.appColors.accentGreenGlow.withAlpha(80),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        widget.child,
      ],
    );
  }
}
