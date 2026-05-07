class BoardTerminalConfig {
  const BoardTerminalConfig({
    required this.sessionId,
    required this.sessionName,
    required this.workingDir,
  });

  final String sessionId;
  final String sessionName;
  final String workingDir;

  bool get isConfigured => workingDir.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'sessionName': sessionName,
    'workingDir': workingDir,
  };

  factory BoardTerminalConfig.fromJson(Map<String, dynamic> json) {
    return BoardTerminalConfig(
      sessionId: json['sessionId'] as String? ?? '',
      sessionName: json['sessionName'] as String? ?? '',
      workingDir: json['workingDir'] as String? ?? '',
    );
  }

  BoardTerminalConfig copyWith({
    String? sessionId,
    String? sessionName,
    String? workingDir,
  }) {
    return BoardTerminalConfig(
      sessionId: sessionId ?? this.sessionId,
      sessionName: sessionName ?? this.sessionName,
      workingDir: workingDir ?? this.workingDir,
    );
  }
}
