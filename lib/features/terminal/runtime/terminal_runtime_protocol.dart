import 'dart:convert';

const terminalRuntimeProtocolVersion = 1;

enum TerminalRuntimeEventType { output, exit, resizeAck, error }

class TerminalRuntimeSession {
  const TerminalRuntimeSession({
    required this.id,
    required this.cwd,
    required this.command,
    required this.createdAt,
    required this.alive,
    this.title,
    this.pid,
  });

  final String id;
  final String cwd;
  final String command;
  final DateTime createdAt;
  final bool alive;
  final String? title;
  final int? pid;

  Map<String, Object?> toJson() => {
    'id': id,
    'cwd': cwd,
    'command': command,
    'createdAt': createdAt.toIso8601String(),
    'alive': alive,
    if (title != null) 'title': title,
    if (pid != null) 'pid': pid,
  };

  factory TerminalRuntimeSession.fromJson(Map<String, Object?> json) {
    return TerminalRuntimeSession(
      id: json['id'] as String,
      cwd: json['cwd'] as String,
      command: json['command'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      alive: json['alive'] as bool? ?? false,
      title: json['title'] as String?,
      pid: json['pid'] as int?,
    );
  }
}

class TerminalRuntimeEvent {
  const TerminalRuntimeEvent({
    required this.sessionId,
    required this.type,
    this.data,
    this.exitCode,
    this.message,
  });

  final String sessionId;
  final TerminalRuntimeEventType type;
  final String? data;
  final int? exitCode;
  final String? message;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'type': type.name,
    if (data != null) 'data': data,
    if (exitCode != null) 'exitCode': exitCode,
    if (message != null) 'message': message,
  };

  String toJsonLine() => '${jsonEncode(toJson())}\n';

  factory TerminalRuntimeEvent.fromJson(Map<String, Object?> json) {
    return TerminalRuntimeEvent(
      sessionId: json['sessionId'] as String,
      type: TerminalRuntimeEventType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => TerminalRuntimeEventType.error,
      ),
      data: json['data'] as String?,
      exitCode: json['exitCode'] as int?,
      message: json['message'] as String?,
    );
  }
}
