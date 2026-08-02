import 'dart:convert';

import 'package:yoloit/core/remote/yoloitd_models.dart';

/// Kind of undo step selected by [planPanelHistoryUndo].
enum PanelUndoKind {
  /// No undoable panel event was found.
  none,

  /// The latest event was a panel creation; undo removes the created panel.
  removeCreated,

  /// The latest event was a panel mutation; undo restores a before-snapshot.
  restoreSnapshot,

  /// The latest event was a panel deletion; undo restores the deleted panel.
  restoreDeleted,
}

/// Describes how a single panel-history undo step should be applied.
///
/// Produced by [planPanelHistoryUndo]; the caller performs the actual side
/// effects (redo bookkeeping + panel mutation) for its storage backend.
class PanelUndoPlan<P> {
  const PanelUndoPlan._({
    required this.kind,
    this.snapshot,
    this.redoSnapshot,
    this.entityId,
    this.opId,
  });

  /// No undoable panel event found.
  const PanelUndoPlan.none() : this._(kind: PanelUndoKind.none);

  /// Undo a panel creation by removing [snapshot] (the created panel).
  const PanelUndoPlan.removeCreated(P snapshot, String opId)
    : this._(kind: PanelUndoKind.removeCreated, snapshot: snapshot, opId: opId);

  /// Undo a panel mutation by restoring [snapshot]; [redoSnapshot] (the
  /// latest after-snapshot) should be recorded on the redo stack when present.
  const PanelUndoPlan.restoreSnapshot(P snapshot, P? redoSnapshot, String opId)
    : this._(
        kind: PanelUndoKind.restoreSnapshot,
        snapshot: snapshot,
        redoSnapshot: redoSnapshot,
        opId: opId,
      );

  /// Undo a panel deletion by restoring [snapshot] (the deleted panel).
  const PanelUndoPlan.restoreDeleted(P snapshot, String entityId, String opId)
    : this._(
        kind: PanelUndoKind.restoreDeleted,
        snapshot: snapshot,
        entityId: entityId,
        opId: opId,
      );

  final PanelUndoKind kind;

  /// The panel snapshot the undo step applies:
  /// - [PanelUndoKind.removeCreated]: the created panel to remove.
  /// - [PanelUndoKind.restoreSnapshot]: the (possibly coalesced)
  ///   before-snapshot to restore.
  /// - [PanelUndoKind.restoreDeleted]: the deleted panel to restore.
  final P? snapshot;

  /// Latest after-snapshot to record on the redo stack
  /// ([PanelUndoKind.restoreSnapshot] only).
  final P? redoSnapshot;

  /// Entity id of the undone event (redo bookkeeping for deletions).
  final String? entityId;

  /// Op id of the undone event.
  final String? opId;
}

/// Whether two panels serialize to identical snapshots.
bool panelSnapshotsEqual<P>(
  P a,
  P b,
  Map<String, dynamic> Function(P panel) toJson,
) {
  return jsonEncode(toJson(a)) == jsonEncode(toJson(b));
}

/// Whether [current] matches the [after] snapshot of a panel creation event,
/// ignoring z-index differences.
bool panelMatchesCreateUndo<P>(
  P current,
  P after,
  Map<String, dynamic> Function(P panel) toJson,
) {
  final currentSnap = Map<String, dynamic>.from(toJson(current));
  final afterSnap = Map<String, dynamic>.from(toJson(after));
  currentSnap.remove('zIndex');
  afterSnap.remove('zIndex');
  return jsonEncode(currentSnap) == jsonEncode(afterSnap);
}

bool _isCoalescablePanelMutation(RemoteHistoryEvent event) {
  return event.type == 'panel.updated' || event.type == 'panel.placedInGrid';
}

String _patchSignature(RemoteHistoryEvent event) {
  final keys = event.patch.keys.toList()..sort();
  return keys.join('|');
}

/// Walks back over coalesced panel mutations (drag/resize bursts recorded as
/// consecutive same-signature updates) and returns the first event of the
/// run, or [events]\[latestIndex] when the event is not coalescable.
///
/// [previousInRun] optionally tightens which previous events belong to the
/// run (defaults to any coalescable panel mutation).
RemoteHistoryEvent coalescedPanelUpdateStart(
  List<RemoteHistoryEvent> events,
  int latestIndex, {
  bool Function(RemoteHistoryEvent previous, RemoteHistoryEvent latest)?
  previousInRun,
}) {
  final latest = events[latestIndex];
  if (!_isCoalescablePanelMutation(latest)) return latest;
  var start = latestIndex;
  final signature = _patchSignature(latest);
  while (start > 0) {
    final previous = events[start - 1];
    if (!_isCoalescablePanelMutation(previous) ||
        !(previousInRun?.call(previous, latest) ?? true) ||
        previous.entityType != latest.entityType ||
        previous.entityId != latest.entityId ||
        previous.restoresOpId != null ||
        previous.revision + 1 != events[start].revision ||
        _patchSignature(previous) != signature) {
      break;
    }
    start--;
  }
  return events[start];
}

/// Scans [events] from newest to oldest and selects the panel-history undo
/// step to apply. Returns [PanelUndoPlan.none] when nothing can be undone.
///
/// This is the shared core of the local (BoardCubit) and remote (yoloitd)
/// `undoLatestPanelHistory` implementations; it performs no I/O.
PanelUndoPlan<P> planPanelHistoryUndo<P>({
  required List<RemoteHistoryEvent> events,
  required P? Function(String entityId) currentPanelOf,
  required P Function(Map<String, dynamic> json) panelFromJson,
  required Map<String, dynamic> Function(P panel) panelToJson,
  bool Function(RemoteHistoryEvent previous, RemoteHistoryEvent latest)?
  previousInRun,
}) {
  for (var index = events.length - 1; index >= 0; index--) {
    final event = events[index];
    if (event.entityType != 'panel') continue;
    if (event.restoresOpId != null || event.type == 'panel.restored') {
      continue;
    }

    final current = currentPanelOf(event.entityId);
    final before = event.before == null ? null : panelFromJson(event.before!);
    final after = event.after == null ? null : panelFromJson(event.after!);

    if (after != null &&
        before == null &&
        current != null &&
        panelMatchesCreateUndo(current, after, panelToJson)) {
      return PanelUndoPlan.removeCreated(after, event.opId);
    }
    if (before != null &&
        current != null &&
        !panelSnapshotsEqual(current, before, panelToJson)) {
      final coalescedEvent = coalescedPanelUpdateStart(
        events,
        index,
        previousInRun: previousInRun,
      );
      final coalescedBefore = coalescedEvent.before;
      final snapshot =
          coalescedBefore == null ? before : panelFromJson(coalescedBefore);
      final latestAfter =
          event.after == null ? null : panelFromJson(event.after!);
      return PanelUndoPlan.restoreSnapshot(snapshot, latestAfter, event.opId);
    }
    if (before != null && current == null && event.type == 'panel.deleted') {
      return PanelUndoPlan.restoreDeleted(before, event.entityId, event.opId);
    }
  }

  return const PanelUndoPlan.none();
}
