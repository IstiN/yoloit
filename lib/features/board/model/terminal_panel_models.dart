import 'package:json_annotation/json_annotation.dart';

part 'terminal_panel_models.g.dart';

@JsonSerializable()
class BoardTerminalConfig {
  const BoardTerminalConfig({
    required this.sessionId,
    required this.sessionName,
    required this.workingDir,
    this.envGroupIds = const [],
  });

  final String sessionId;
  final String sessionName;
  final String workingDir;
  final List<String> envGroupIds;

  bool get isConfigured => workingDir.trim().isNotEmpty;

  Map<String, dynamic> toJson() => _$BoardTerminalConfigToJson(this);

  factory BoardTerminalConfig.fromJson(Map<String, dynamic> json) =>
      _$BoardTerminalConfigFromJson(json);

  BoardTerminalConfig copyWith({
    String? sessionId,
    String? sessionName,
    String? workingDir,
    List<String>? envGroupIds,
  }) {
    return BoardTerminalConfig(
      sessionId: sessionId ?? this.sessionId,
      sessionName: sessionName ?? this.sessionName,
      workingDir: workingDir ?? this.workingDir,
      envGroupIds: envGroupIds ?? this.envGroupIds,
    );
  }
}
