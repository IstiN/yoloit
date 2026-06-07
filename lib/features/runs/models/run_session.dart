import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:yoloit/features/runs/models/run_config.dart';

part 'run_session.g.dart';

enum RunStatus { idle, running, stopped, failed }

@JsonSerializable()
class RunOutputLine extends Equatable {
  const RunOutputLine({
    required this.text,
    required this.isError,
    required this.timestamp,
  });

  final String text;
  final bool isError;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => _$RunOutputLineToJson(this);

  factory RunOutputLine.fromJson(Map<String, dynamic> j) =>
      _$RunOutputLineFromJson(j);

  @override
  List<Object?> get props => [text, isError, timestamp];
}

@JsonSerializable()
class RunSession extends Equatable {
  const RunSession({
    required this.id,
    required this.config,
    required this.workspacePath,
    this.status = RunStatus.idle,
    this.output = const [],
    this.exitCode,
    this.startedAt,
  });

  final String id;
  final RunConfig config;
  final String workspacePath;
  final RunStatus status;
  final List<RunOutputLine> output;
  final int? exitCode;
  final DateTime? startedAt;

  RunSession copyWith({
    String? id,
    RunConfig? config,
    String? workspacePath,
    RunStatus? status,
    List<RunOutputLine>? output,
    int? exitCode,
    bool clearExitCode = false,
    DateTime? startedAt,
  }) {
    return RunSession(
      id: id ?? this.id,
      config: config ?? this.config,
      workspacePath: workspacePath ?? this.workspacePath,
      status: status ?? this.status,
      output: output ?? this.output,
      exitCode: clearExitCode ? null : (exitCode ?? this.exitCode),
      startedAt: startedAt ?? this.startedAt,
    );
  }

  Map<String, dynamic> toJson() => _$RunSessionToJson(this);

  factory RunSession.fromJson(Map<String, dynamic> j) =>
      _$RunSessionFromJson(j);

  @override
  List<Object?> get props => [id, status, output, exitCode];
}
