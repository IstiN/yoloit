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
    Map<String, dynamic>? readMap(String key) {
      final value = json[key];
      return value is Map ? Map<String, dynamic>.from(value) : null;
    }

    return BoardHistoryEvent(
      opId: json['opId'] as String,
      boardId: json['boardId'] as String,
      type: json['type'] as String,
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      actorId: json['actorId'] as String? ?? 'local',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      before: readMap('before'),
      after: readMap('after'),
      patch: readMap('patch') ?? const <String, dynamic>{},
      restoresOpId: json['restoresOpId'] as String?,
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
