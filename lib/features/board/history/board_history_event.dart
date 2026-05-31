import 'package:equatable/equatable.dart';

class BoardHistoryEvent extends Equatable {
  const BoardHistoryEvent({
    required this.opId,
    required this.boardId,
    required this.type,
    required this.entityType,
    required this.entityId,
    required this.actorId,
    required this.timestamp,
    required this.revision,
    this.before,
    this.after,
    this.patch = const {},
    this.restoresOpId,
  });

  final String opId;
  final String boardId;
  final String type;
  final String entityType;
  final String entityId;
  final String actorId;
  final DateTime timestamp;
  final int revision;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final Map<String, dynamic> patch;
  final String? restoresOpId;

  Map<String, dynamic> toJson() => {
    'opId': opId,
    'boardId': boardId,
    'type': type,
    'entityType': entityType,
    'entityId': entityId,
    'actorId': actorId,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'revision': revision,
    if (before != null) 'before': before,
    if (after != null) 'after': after,
    if (patch.isNotEmpty) 'patch': patch,
    if (restoresOpId != null) 'restoresOpId': restoresOpId,
  };

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
      patch: readMap('patch') ?? const {},
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
