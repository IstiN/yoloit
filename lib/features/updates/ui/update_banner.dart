import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/updates/data/update_service.dart';

/// Phase of the silent auto-update flow.
enum AutoUpdatePhase { downloading, installing, ready, error }

/// Slim non-interactive banner that shows silent update progress.
///
/// Phases:
///   - [AutoUpdatePhase.downloading] — progress bar, no buttons.
///   - [AutoUpdatePhase.installing]  — indeterminate bar, no buttons.
///   - [AutoUpdatePhase.ready]       — 5-second countdown then auto-restart,
///                                     with optional "Restart Now" / "Later".
///   - [AutoUpdatePhase.error]       — shows error, dismiss button.
class AutoUpdateBanner extends StatefulWidget {
  const AutoUpdateBanner({
    super.key,
    required this.info,
    required this.phase,
    required this.progress,
    required this.status,
    required this.launchToken,
    required this.onDismiss,
  });

  final UpdateInfo info;
  final AutoUpdatePhase phase;
  final double? progress;   // 0.0–1.0 during download, null otherwise
  final String status;      // status text (error message when phase==error)
  final String? launchToken;
  final VoidCallback onDismiss;

  @override
  State<AutoUpdateBanner> createState() => _AutoUpdateBannerState();
}

class _AutoUpdateBannerState extends State<AutoUpdateBanner> {
  int _secondsLeft = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.phase == AutoUpdatePhase.ready) _startCountdown();
  }

  @override
  void didUpdateWidget(AutoUpdateBanner old) {
    super.didUpdateWidget(old);
    if (old.phase != AutoUpdatePhase.ready &&
        widget.phase == AutoUpdatePhase.ready) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    _secondsLeft = 5;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_secondsLeft <= 1) {
        t.cancel();
        _restart();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _restart() {
    _timer?.cancel();
    if (widget.launchToken != null) {
      UpdateService.applyUpdate(widget.launchToken!);
    }
  }

  void _postpone() {
    _timer?.cancel();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReady = widget.phase == AutoUpdatePhase.ready;
    final isError = widget.phase == AutoUpdatePhase.error;
    final colors = context.appColors;

    return Material(
      color: isError
          ? Colors.red.shade800.withAlpha(230)
          : colors.accentBlue.withAlpha(230),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  isReady
                      ? Icons.check_circle_outline_rounded
                      : isError
                          ? Icons.error_outline_rounded
                          : Icons.downloading_rounded,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _label(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isReady) ...[
                  _Btn(label: 'Restart Now', onTap: _restart),
                  const SizedBox(width: 6),
                  _Btn(label: 'Later', onTap: _postpone),
                ] else if (isError) ...[
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: const Icon(Icons.close, size: 14, color: Colors.white70),
                  ),
                ],
              ],
            ),
            // Progress / indeterminate bar
            if (widget.phase == AutoUpdatePhase.downloading &&
                widget.progress != null)
              _bar(widget.progress),
            if (widget.phase == AutoUpdatePhase.installing)
              _bar(null),
          ],
        ),
      ),
    );
  }

  String _label() {
    switch (widget.phase) {
      case AutoUpdatePhase.downloading:
        final pct = widget.progress != null
            ? ' ${(widget.progress! * 100).toStringAsFixed(0)}%'
            : '';
        return 'Downloading YoLoIT ${widget.info.tagName}$pct…';
      case AutoUpdatePhase.installing:
        return widget.status.isNotEmpty ? widget.status : 'Installing…';
      case AutoUpdatePhase.ready:
        return 'YoLoIT ${widget.info.tagName} ready — restarting in ${_secondsLeft}s…';
      case AutoUpdatePhase.error:
        return 'Update failed: ${widget.status}';
    }
  }

  Widget _bar(double? value) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 3,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
}

class _Btn extends StatelessWidget {
  const _Btn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(30),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white.withAlpha(60)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}

