part of 'board_cubit.dart';

Timer? _panelLockRenewalTimer;
const _panelLockRenewalInterval = Duration(seconds: 30);

/// Panel-lock helpers for collaborative remote editing.
extension BoardCubitLocks on BoardCubit {
  void _startPanelLockRenewal(String boardId, String panelId) {
    final board = state.boards.firstWhereOrNull((b) => b.id == boardId);
    if (board == null || remoteInfoForBoard(board) == null) return;
    _panelLockRenewalTimer?.cancel();
    _panelLockRenewalTimer = Timer.periodic(_panelLockRenewalInterval, (_) {
      unawaited(acquirePanelLock(boardId, panelId));
    });
  }

  void _stopPanelLockRenewal() {
    _panelLockRenewalTimer?.cancel();
    _panelLockRenewalTimer = null;
  }

  static const _panelLocksMetadataKey = 'panelLocks';

  /// Returns the actor id that currently holds a non-expired remote lock on
  /// [panelId], or `null` if the panel is free or locked by the local actor.
  String? panelLockActor(BoardDocument board, String panelId) {
    final locks = board.metadata[_panelLocksMetadataKey];
    if (locks is! Map) return null;
    final lock = locks[panelId];
    if (lock is! Map) return null;
    final actorId = lock['actorId'] as String?;
    final expires = lock['expiresAt'];
    if (actorId == null || actorId == _actorId) return null;
    if (expires is int &&
        expires < DateTime.now().toUtc().millisecondsSinceEpoch) {
      return null;
    }
    return actorId;
  }

  Set<String> _panelIdsLockedByActor(BoardDocument board, String actorId) {
    final locks = board.metadata[_panelLocksMetadataKey];
    if (locks is! Map) return const <String>{};
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final ids = <String>{};
    for (final entry in locks.entries) {
      final lock = entry.value;
      if (lock is! Map) continue;
      if (lock['actorId'] != actorId) continue;
      final expires = lock['expiresAt'];
      if (expires is int && expires < now) continue;
      ids.add(entry.key.toString());
    }
    return ids;
  }

  @visibleForTesting
  Set<String> panelIdsLockedByActorForTest(
    BoardDocument board,
    String actorId,
  ) => _panelIdsLockedByActor(board, actorId);

  Future<bool> acquirePanelLock(
    String boardId,
    String panelId, {
    int ttlSec = 60,
  }) async {
    final board = state.boards.firstWhereOrNull((b) => b.id == boardId);
    if (board == null) return false;
    final remote = remoteInfoForBoard(board);
    if (remote == null) {
      // Local boards do not need locks; skip the extra persistence round-trip.
      return true;
    }
    try {
      await YoloitRemoteClient(
        baseUrl: remote.url,
        token: remote.token,
      ).acquirePanelLock(
        remote.boardId,
        panelId,
        actorId: _actorId,
        ttlSec: ttlSec,
      );
    } on YoloitRemoteException catch (error) {
      if (error.statusCode == 409) {
        String? conflictingActor;
        try {
          final decoded = jsonDecode(error.body ?? '{}');
          if (decoded is Map) {
            conflictingActor = decoded['actorId'] as String?;
          }
        } catch (_) {}
        _emitPanelLockConflict(panelId, conflictingActor);
        return false;
      }
      assert(() {
        debugPrint('[BoardCubit] failed to acquire remote panel lock: $error');
        return true;
      }());
    } catch (error) {
      assert(() {
        debugPrint('[BoardCubit] failed to acquire remote panel lock: $error');
        return true;
      }());
    }
    _suppressRemoteSync = true;
    try {
      await _updateBoard(
        boardId,
        (b) {
          final locks =
              b.metadata[_panelLocksMetadataKey] is Map
                  ? Map<String, dynamic>.from(
                    b.metadata[_panelLocksMetadataKey] as Map,
                  )
                  : <String, dynamic>{};
          final expires =
              DateTime.now().toUtc().millisecondsSinceEpoch + ttlSec * 1000;
          locks[panelId] = {'actorId': _actorId, 'expiresAt': expires};
          return b.copyWith(
            metadata: {...b.metadata, _panelLocksMetadataKey: locks},
          );
        },
        historyEvent: null,
      );
    } finally {
      _suppressRemoteSync = false;
    }
    return true;
  }

  Future<void> releasePanelLock(String boardId, String panelId) async {
    final board = state.boards.firstWhereOrNull((b) => b.id == boardId);
    if (board == null) return;
    final remote = remoteInfoForBoard(board);
    if (remote != null) {
      try {
        await YoloitRemoteClient(
          baseUrl: remote.url,
          token: remote.token,
        ).releasePanelLock(remote.boardId, panelId);
      } catch (error) {
        assert(() {
          debugPrint(
            '[BoardCubit] failed to release remote panel lock: $error',
          );
          return true;
        }());
      }
    }
    _suppressRemoteSync = true;
    try {
      await _updateBoard(
        boardId,
        (b) {
          final locks =
              b.metadata[_panelLocksMetadataKey] is Map
                  ? Map<String, dynamic>.from(
                    b.metadata[_panelLocksMetadataKey] as Map,
                  )
                  : <String, dynamic>{};
          if (!locks.containsKey(panelId)) return b;
          final next = Map<String, dynamic>.from(locks)..remove(panelId);
          return b.copyWith(
            metadata: {...b.metadata, _panelLocksMetadataKey: next},
          );
        },
        historyEvent: null,
      );
    } finally {
      _suppressRemoteSync = false;
    }
  }
}
