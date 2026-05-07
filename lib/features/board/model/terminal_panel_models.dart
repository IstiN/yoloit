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

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'sessionName': sessionName,
    'workingDir': workingDir,
    if (envGroupIds.isNotEmpty) 'envGroupIds': envGroupIds,
  };

  factory BoardTerminalConfig.fromJson(Map<String, dynamic> json) {
    return BoardTerminalConfig(
      sessionId: json['sessionId'] as String? ?? '',
      sessionName: json['sessionName'] as String? ?? '',
      workingDir: json['workingDir'] as String? ?? '',
      envGroupIds: (json['envGroupIds'] as List?)?.cast<String>() ?? const [],
    );
  }

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
