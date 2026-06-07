import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

part 'terminal_runtime_protocol.g.dart';

const terminalRuntimeProtocolVersion = 1;

enum TerminalRuntimeEventType { output, exit, resizeAck, error }

@JsonSerializable()
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

  Map<String, dynamic> toJson() => _$TerminalRuntimeSessionToJson(this);

  factory TerminalRuntimeSession.fromJson(Map<String, dynamic> json) =>
      _$TerminalRuntimeSessionFromJson(json);
}

@JsonSerializable()
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

  Map<String, dynamic> toJson() => _$TerminalRuntimeEventToJson(this);

  String toJsonLine() => '${jsonEncode(toJson())}\n';

  factory TerminalRuntimeEvent.fromJson(Map<String, dynamic> json) =>
      _$TerminalRuntimeEventFromJson(json);
}
