import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class RunQuickAction extends Equatable {
  const RunQuickAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.command,
    this.appendNewline = false,
  });

  final String id;
  final String label;
  final String icon;
  final String command;
  final bool appendNewline;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'icon': icon,
    'command': command,
    'appendNewline': appendNewline,
  };

  factory RunQuickAction.fromJson(Map<String, dynamic> json) => RunQuickAction(
    id: json['id'] as String? ?? 'qa_${DateTime.now().millisecondsSinceEpoch}',
    label: json['label'] as String? ?? 'Action',
    icon: json['icon'] as String? ?? 'bolt',
    command: json['command'] as String? ?? '',
    appendNewline: json['appendNewline'] as bool? ?? false,
  );

  @override
  List<Object?> get props => [id, label, icon, command, appendNewline];
}

class RunConfig extends Equatable {
  const RunConfig({
    required this.id,
    required this.name,
    required this.command,
    this.group = 'default',
    this.workingDir,
    this.env = const {},
    this.color,
    this.isFlutterRun = false,
    this.quickActions = const [],
  });

  final String id;
  final String name;
  final String command;
  final String group;
  final String? workingDir;
  final Map<String, String> env;
  final Color? color;
  final bool isFlutterRun;
  final List<RunQuickAction> quickActions;

  RunConfig copyWith({
    String? id,
    String? name,
    String? command,
    String? group,
    String? workingDir,
    bool clearWorkingDir = false,
    Map<String, String>? env,
    Color? color,
    bool clearColor = false,
    bool? isFlutterRun,
    List<RunQuickAction>? quickActions,
  }) {
    return RunConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      command: command ?? this.command,
      group: group ?? this.group,
      workingDir: clearWorkingDir ? null : (workingDir ?? this.workingDir),
      env: env ?? this.env,
      color: clearColor ? null : (color ?? this.color),
      isFlutterRun: isFlutterRun ?? this.isFlutterRun,
      quickActions: quickActions ?? this.quickActions,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'command': command,
    'group': group,
    'workingDir': workingDir,
    'env': env,
    'color': color?.toARGB32(),
    'isFlutterRun': isFlutterRun,
    'quickActions': quickActions.map((a) => a.toJson()).toList(),
  };

  factory RunConfig.fromJson(Map<String, dynamic> json) => RunConfig(
    id: json['id'] as String,
    name: json['name'] as String,
    command: json['command'] as String,
    group: json['group'] as String? ?? 'default',
    workingDir: json['workingDir'] as String?,
    env: (json['env'] as Map<String, dynamic>?)?.cast<String, String>() ?? {},
    color: json['color'] != null ? Color(json['color'] as int) : null,
    isFlutterRun: json['isFlutterRun'] as bool? ?? false,
    quickActions:
        (json['quickActions'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(RunQuickAction.fromJson)
            .where((a) => a.command.trim().isNotEmpty)
            .toList() ??
        const [],
  );

  static RunConfig flutterRunMacos(
    String workspacePath, {
    String group = 'default',
  }) => RunConfig(
    id: 'preset_flutter_run_macos',
    name: 'Flutter Run (macOS)',
    command: 'flutter run -d macos --debug',
    group: group,
    workingDir: workspacePath,
    color: const Color(0xFF54C5F8),
    isFlutterRun: true,
    quickActions: const [
      RunQuickAction(
        id: 'flutter_hot_reload',
        label: 'Hot Reload',
        icon: 'local_fire_department',
        command: 'r',
      ),
      RunQuickAction(
        id: 'flutter_hot_restart',
        label: 'Hot Restart',
        icon: 'restart_alt',
        command: 'R',
      ),
    ],
  );

  static RunConfig flutterTest({String group = 'default'}) => RunConfig(
    id: 'preset_flutter_test',
    name: 'Flutter Test',
    command: 'flutter test',
    group: group,
    color: Color(0xFF00FF9F),
  );

  static RunConfig flutterBuildMacos({String group = 'default'}) => RunConfig(
    id: 'preset_flutter_build_macos',
    name: 'Flutter Build (macOS)',
    command: 'flutter build macos',
    group: group,
    color: Color(0xFFFFD700),
  );

  @override
  List<Object?> get props => [
    id,
    name,
    command,
    group,
    workingDir,
    env,
    color?.toARGB32(),
    isFlutterRun,
    quickActions,
  ];
}
