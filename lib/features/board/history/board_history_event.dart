import 'package:equatable/equatable.dart';
import 'package:yoloit/core/remote/yoloitd_models.dart';

class BoardHistoryEvent extends RemoteHistoryEvent with EquatableMixin {
  const BoardHistoryEvent({
    required super.opId,
    required super.boardId,
    required super.type,
    required super.entityType,
    required super.entityId,
    required super.actorId,
    required super.timestamp,
    required super.revision,
    super.before,
    super.after,
    super.patch,
    super.restoresOpId,
  });

  factory BoardHistoryEvent.fromJson(Map<String, dynamic> json) {
    final base = RemoteHistoryEvent.fromJson(json, defaultActorId: 'local');
    return BoardHistoryEvent(
      opId: base.opId,
      boardId: base.boardId,
      type: base.type,
      entityType: base.entityType,
      entityId: base.entityId,
      actorId: base.actorId,
      timestamp: base.timestamp,
      revision: base.revision,
      before: base.before,
      after: base.after,
      patch: base.patch,
      restoresOpId: base.restoresOpId,
    );
  }

  @override
  List<Object?> get props => [
    opId,
    boardId,
    type,
    entityType,
    entityId,
    actorId,
    timestamp,
    revision,
    before,
    after,
    patch,
    restoresOpId,
  ];
}
