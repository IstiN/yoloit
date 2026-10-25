import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:yoloit/features/board/bloc/board_cubit.dart';

/// Injectable clock, same pattern as [AudioRecordingManager]: tests can
/// substitute a fake time source (fakeAsync does not fake `DateTime.now`).
typedef Now = DateTime Function();

/// Singleton that keeps Timer countdowns running independently of the UI widget.
///
/// When the timer widget is disposed (board switch), the manager keeps ticking.
/// When the widget re-mounts, it reads the updated remaining time from
/// panel.state (which the manager keeps writing to via BoardCubit).
///
/// Intermediate per-second panel writes are skipped while the timer's board
/// is not the active visible board (a hidden board has no consumers); the
/// accumulated remaining time self-corrects on the first visible tick and the
/// completion write always lands, even while hidden.
class TimerManager {
  static final instance = TimerManager._();
  TimerManager._({Now? now}) : _now = now ?? DateTime.now;

  /// Creates an isolated instance for unit testing.
  factory TimerManager.testInstance({Now? now}) => TimerManager._(now: now);

  final Now _now;

  BoardCubit? _cubit;
  final Map<String, _TimerEntry> _timers = {};

  void setCubit(BoardCubit cubit) => _cubit = cubit;

  /// Start a timer for [panelId] on board [boardId].
  ///
  /// If a timer is already running for this panel, it is replaced.
  void start({
    required String panelId,
    required String boardId,
    required int remaining,
  }) {
    stop(panelId);
    final entry = _TimerEntry(
      panelId: panelId,
      boardId: boardId,
      remaining: remaining,
      lastTick: _now().millisecondsSinceEpoch,
    );
    entry.timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick(panelId);
    });
    _timers[panelId] = entry;
  }

  /// Stop and remove the timer for [panelId].
  void stop(String panelId) {
    _timers.remove(panelId)?.timer?.cancel();
  }

  /// Whether a timer is actively ticking for [panelId].
  bool isRunning(String panelId) => _timers.containsKey(panelId);

  /// Get the current remaining seconds (from the manager's tracking).
  int? remaining(String panelId) => _timers[panelId]?.remaining;

  /// List all active timer panel IDs.
  List<String> get activeTimerIds => _timers.keys.toList();

  /// Stop all timers.
  void disposeAll() {
    for (final entry in _timers.values) {
      entry.timer?.cancel();
    }
    _timers.clear();
  }

  void _tick(String panelId) {
    final entry = _timers[panelId];
    if (entry == null) return;

    final now = _now().millisecondsSinceEpoch;
    final elapsed = now - entry.lastTick;
    final secondsElapsed = (elapsed / 1000).round();
    final newRemaining = math.max(0, entry.remaining - secondsElapsed);
    final done = newRemaining <= 0;

    entry.remaining = done ? 0 : newRemaining;
    entry.lastTick = now;

    // Write back to panel state via BoardCubit. While the board is hidden
    // the write is skipped (nothing consumes it); the completion write
    // always lands and the first visible tick carries the self-corrected
    // accumulated remaining time.
    final cubit = _cubit;
    if (cubit != null && (_isBoardVisible(entry.boardId) || done)) {
      cubit.updatePanel(
        entry.panelId,
        (p) => p.copyWith(state: {
          ...p.state,
          'remaining': entry.remaining,
          'isRunning': !done,
          'isPaused': false,
          'completed': done,
          'lastTick': now,
        }),
        boardId: entry.boardId,
      );
    }

    if (done) {
      stop(panelId);
      _playAlarm();
    }
  }

  /// Whether the timer's board is the active visible board. A null active
  /// board id (cubit not loaded) is treated as visible so behavior is
  /// unchanged when no board has been resolved yet.
  bool _isBoardVisible(String boardId) {
    final cubit = _cubit;
    if (cubit == null) return true;
    final activeId = cubit.state.activeBoardId;
    return activeId == null || activeId == boardId;
  }

  void _playAlarm() {
    try {
      Process.run('afplay', ['/System/Library/Sounds/Ping.aiff']);
    } catch (_) {}
  }
}

class _TimerEntry {
  _TimerEntry({
    required this.panelId,
    required this.boardId,
    required this.remaining,
    required this.lastTick,
  });

  final String panelId;
  final String boardId;
  int remaining;
  int lastTick;
  Timer? timer;
}
