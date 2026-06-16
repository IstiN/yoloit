import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/assistant/yolo_assistant_widget.dart';
import 'package:yoloit/features/board/assistant/yolo_voice_overlay.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class YoloBadgeWithChat extends StatefulWidget {
  const YoloBadgeWithChat();

  @override
  State<YoloBadgeWithChat> createState() => YoloBadgeWithChatState();
}

class YoloBadgeWithChatState extends State<YoloBadgeWithChat>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _entranceSlide;
  late final Animation<double> _entranceFade;

  late final AnimationController _chatController;
  late final Animation<double> _chatSlide;

  bool _chatOpen = false;
  Timer? _entranceDelayTimer;
  final FocusNode _voiceOverlayFocusNode = FocusNode();
  final YoloAssistantController _assistantController =
      YoloAssistantController();
  // In-memory panel instance for the embedded assistant widget
  BoardPanelInstance _badgePanel = const BoardPanelInstance(
    id: '__yolo_badge_assistant__',
    type: 'board.yolo_assistant',
    title: 'YoLo Assistant',
    bounds: BoardPanelBounds(x: 0, y: 0, width: 380, height: 480),
  );

  @override
  void initState() {
    super.initState();
    // Entrance animation for badge
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _entranceSlide = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _entranceFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0, 0.7, curve: Curves.easeOut),
      ),
    );
    _entranceDelayTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _entranceController.forward();
    });

    // Chat panel slide animation
    _chatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _chatSlide = Tween<double>(begin: 380, end: 0).animate(
      CurvedAnimation(parent: _chatController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _entranceDelayTimer?.cancel();
    _voiceOverlayFocusNode.dispose();
    _entranceController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  void toggleChat() {
    setState(() => _chatOpen = !_chatOpen);
    if (_chatOpen) {
      _chatController.forward();
    } else {
      _chatController.reverse();
    }
  }

  Future<void> activateVoiceOverlay() async {
    setState(() {
      _badgePanel = _badgePanel.copyWith(
        state: {
          ..._badgePanel.state,
          'voiceOverlayHidden': false,
          'voiceDraft': '',
          'voicePrompt': '',
          'voiceResponse': '',
          'assistantStatus': 'idle',
        },
      );
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (!mounted) return;
    _voiceOverlayFocusNode.requestFocus();
    await _assistantController.startMic();
  }

  Future<void> hideVoiceOverlay() async {
    if (_assistantStatus == 'listening') {
      await _assistantController.cancelMic();
    } else {
      _assistantController.resetOverlay();
    }
    if (!mounted) return;
    _voiceOverlayFocusNode.unfocus();
  }

  Future<void> handleVoiceOverlayPrimaryAction() async {
    switch (_assistantStatus) {
      case 'listening':
        await _assistantController.stopMic(sendAfterTranscription: true);
      case 'processing':
      case 'thinking':
      case 'responding':
        return;
      case 'output':
        await activateVoiceOverlay();
      case 'ready':
        if (_voiceDraft.trim().isNotEmpty) {
          await _assistantController.sendDraft();
        } else {
          await activateVoiceOverlay();
        }
      default:
        await activateVoiceOverlay();
    }
    if (mounted) _voiceOverlayFocusNode.requestFocus();
  }

  String get _assistantStatus =>
      _badgePanel.state['assistantStatus'] as String? ?? 'idle';

  bool get _voiceOverlayHidden =>
      _badgePanel.state['voiceOverlayHidden'] as bool? ?? true;

  String get _voiceDraft => _badgePanel.state['voiceDraft'] as String? ?? '';

  String get _voicePrompt => _badgePanel.state['voicePrompt'] as String? ?? '';

  String get _voiceResponse =>
      _badgePanel.state['voiceResponse'] as String? ?? '';

  String get _voiceOverlayTitle {
    switch (_assistantStatus) {
      case 'listening':
        return 'Listening...';
      case 'processing':
        return 'Sending Audio...';
      case 'thinking':
        return 'Thinking...';
      case 'responding':
        return 'Here is what I found for you:';
      case 'output':
        return 'Here is what I found for you:';
      case 'ready':
        return 'Ready to send';
      default:
        return 'Voice command';
    }
  }

  String get _voiceOverlayHint {
    switch (_assistantStatus) {
      case 'listening':
        return 'Click or [Space] to Send';
      case 'processing':
        return 'Please wait';
      case 'thinking':
        return 'YoLo is preparing an answer...';
      case 'responding':
        return 'Streaming into this bubble and the YOLO chat.';
      case 'output':
        return 'Press Esc to hide.';
      case 'ready':
        return 'Click or [Space] to Send';
      default:
        return 'Click or [Space] to Send';
    }
  }

  String get _lastUserMessage {
    final messages =
        (_badgePanel.state['messages'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList()
            .reversed;
    for (final message in messages) {
      if ((message['role'] as String?) == 'user') {
        return message['content'] as String? ?? '';
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_entranceSlide.value, 0),
          child: Opacity(opacity: _entranceFade.value, child: child),
        );
      },
      child: SizedBox(
        width: double.infinity,
        height: 540,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Voice overlay (bottom center, chat overlaps when open)
            Align(
              alignment: Alignment.bottomCenter,
              child: Transform.translate(
                offset: const Offset(0, 56),
                child: _buildVoiceOverlay(context),
              ),
            ),
            // Chat tab + panel (bottom-right, on top of overlay)
            Align(
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildChatTab(context),
                  ),
                  AnimatedBuilder(
                    animation: _chatController,
                    builder: (context, child) {
                      final progress = 1.0 - (_chatSlide.value / 380);
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(14),
                            topRight: Radius.circular(14),
                            bottomRight: Radius.circular(14),
                          ),
                          boxShadow:
                              progress > 0.05
                                  ? [
                                    BoxShadow(
                                      color: context.appColors.background
                                          .withValues(alpha: 0.14 * progress),
                                      blurRadius: 20,
                                      spreadRadius: -4,
                                      offset: const Offset(-8, 8),
                                    ),
                                  ]
                                  : [],
                        ),
                        child: ClipRect(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress,
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final availableWidth =
                            MediaQuery.sizeOf(context).width - 44;
                        return SizedBox(
                          width: availableWidth.clamp(260.0, 380.0),
                          height: 480,
                          child: _buildChatPanel(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatTab(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: toggleChat,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 28,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colors.primary, colors.primaryLight],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              bottomLeft: Radius.circular(10),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(-2, 2),
              ),
            ],
          ),
          child: RotatedBox(
            quarterTurns: 3,
            child:
                _chatOpen
                    ? Icon(Icons.close, size: 14, color: colors.textPrimary)
                    : Text(
                      'YOLO',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceOverlay(BuildContext context) {
    final transcript =
        _voiceDraft.trim().isNotEmpty
            ? _voiceDraft
            : (_voicePrompt.trim().isNotEmpty
                ? _voicePrompt
                : _lastUserMessage);
    return YoloVoiceOverlay(
      status: _voiceOverlayHidden ? 'idle' : _assistantStatus,
      // Animate only when the overlay is actually visible and active.
      // The idle orb loop would otherwise run continuously in the background
      // and waste GPU/battery.
      animate: !_voiceOverlayHidden && _assistantStatus != 'idle',
      title: _voiceOverlayTitle,
      hint: _voiceOverlayHint,
      transcript: transcript,
      response: _voiceResponse,
      focusNode: _voiceOverlayFocusNode,
      onHide: () => unawaited(hideVoiceOverlay()),
      onPrimaryAction: () => unawaited(handleVoiceOverlayPrimaryAction()),
      scale: 0.70,
      orbScale: 0.30,
      ovalWidth: 2.00,
      ovalHeight: 1.10,
      titleFontSize: 9.0,
      titleColor:
          Theme.of(context).brightness == Brightness.dark
              ? context.appColors.terminalPrompt
              : context.appColors.accentBlue,
      waveBarCount: 22,
      waveAmplitude: 0.85,
      waveSpeed: 1400,
      waveWidth: 160.0,
      waveSpread: 0.50,
      particleScale: 0.50,
      responseFontSize: 15.0,
      borderSpeed: 1700,
      responseActionLabel: 'Tap YoLo to speak',
      showIdleHint: false,
      orbAlignY: 0.62,
      responseOrbAlignY: 0.66,
      micAmplitudeStream: _assistantController.micAmplitudeStream,
    );
  }

  Widget _buildChatPanel() {
    final colors = AppColorScheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: YoloAssistantWidget(
        panel: _badgePanel,
        controller: _assistantController,
        onUpdateState: (newState) {
          setState(() {
            _badgePanel = _badgePanel.copyWith(state: newState);
          });
        },
      ),
    );
  }
}
