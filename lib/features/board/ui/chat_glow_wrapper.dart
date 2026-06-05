import 'package:flutter/material.dart';
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
  late AnimationController _glowCtrl;
  ValueNotifier<bool>? _notifier;
  bool _isGlowing = false;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
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
    if (processing != _isGlowing) {
      setState(() => _isGlowing = processing);
      if (processing) {
        _glowCtrl.repeat(reverse: true);
      } else {
        _glowCtrl.stop();
        _glowCtrl.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _notifier?.removeListener(_onNotifierChange);
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (context, child) {
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow:
                _isGlowing
                    ? [
                      BoxShadow(
                        color: context.appColors.accentGreenGlow.withAlpha(
                          (20 + _glowCtrl.value * 60).round(),
                        ),
                        blurRadius: 16 + _glowCtrl.value * 8,
                        spreadRadius: 2,
                      ),
                    ]
                    : const [],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
