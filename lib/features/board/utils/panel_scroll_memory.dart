import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Persists per-panel scroll offsets in [BoardPanelInstance.state].
///
/// Offsets survive board switches and app restarts because board state is
/// persisted to disk. UI-only session caches (e.g. chat) should mirror here.
class PanelScrollMemory {
  static const String stateKey = 'scrollOffset';

  static double? read(Map<String, dynamic> state) {
    final raw = state[stateKey];
    if (raw is num) return raw.toDouble();
    return null;
  }

  static Map<String, dynamic> write(
    Map<String, dynamic> state,
    double offset,
  ) {
    return {...state, stateKey: offset};
  }

  /// Restores [offset] after layout, retrying while content height grows.
  static void restoreAfterLayout(
    ScrollController controller, {
    required double? offset,
    bool Function()? isActive,
    int attemptsLeft = 24,
  }) {
    if (offset == null || offset <= 0 || attemptsLeft <= 0) return;

    bool tryJump() {
      if (isActive != null && !isActive()) return true;
      if (!controller.hasClients) return false;

      final position = controller.position;
      final maxExtent = position.maxScrollExtent;
      final target = offset.clamp(position.minScrollExtent, maxExtent);

      if (offset > maxExtent + 0.5) return false;
      if ((position.pixels - target).abs() < 0.5) return true;

      try {
        position.jumpTo(target);
        return true;
      } catch (_) {
        return false;
      }
    }

    if (tryJump()) return;

    void scheduleRetry(int left) {
      if (left <= 0) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (tryJump()) return;
        scheduleRetry(left - 1);
      });
    }

    scheduleRetry(attemptsLeft);
  }

  /// Saves scroll offset while scrolling and on [dispose]/[flush].
  static PanelScrollSaveHandle? attachAutoSave({
    required ScrollController controller,
    required Map<String, dynamic> Function() readState,
    required void Function(Map<String, dynamic>)? onUpdateState,
  }) {
    if (onUpdateState == null) return null;
    return PanelScrollSaveHandle._(
      controller: controller,
      readState: readState,
      onUpdateState: onUpdateState,
    );
  }
}

/// Tracks a [ScrollController] and mirrors its offset into panel state.
class PanelScrollSaveHandle {
  PanelScrollSaveHandle._({
    required ScrollController controller,
    required Map<String, dynamic> Function() readState,
    required void Function(Map<String, dynamic>) onUpdateState,
  }) : _controller = controller,
       _readState = readState,
       _onUpdateState = onUpdateState {
    _lastPersisted = PanelScrollMemory.read(readState()) ?? -1;
    _controller.addListener(_onScroll);
  }

  final ScrollController _controller;
  final Map<String, dynamic> Function() _readState;
  final void Function(Map<String, dynamic>) _onUpdateState;
  double _lastPersisted = -1;
  bool _disposed = false;

  void _onScroll() {
    if (_disposed || !_controller.hasClients) return;
    _maybePersist(_controller.offset);
  }

  void _maybePersist(double offset) {
    if (offset <= 0) return;
    if (_lastPersisted >= 0 && (offset - _lastPersisted).abs() < 6) return;
    _lastPersisted = offset;
    _onUpdateState(PanelScrollMemory.write(_readState(), offset));
  }

  /// Persists the latest offset. Safe to call from [State.deactivate].
  void flush() {
    if (_disposed) return;
    if (_controller.hasClients) {
      _maybePersist(_controller.offset);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.removeListener(_onScroll);
    flush();
  }
}
