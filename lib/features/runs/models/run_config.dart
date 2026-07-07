import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:yoloit/features/board/model/board_json_converters.dart';

part 'run_config.g.dart';

@JsonSerializable()
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

  Map<String, dynamic> toJson() => _$RunQuickActionToJson(this);

  factory RunQuickAction.fromJson(Map<String, dynamic> json) =>
      _$RunQuickActionFromJson(json);

  @override
  List<Object?> get props => [id, label, icon, command, appendNewline];
}

@JsonSerializable()
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
  @ColorNullableJsonConverter()
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

  Map<String, dynamic> toJson() => _$RunConfigToJson(this);

  factory RunConfig.fromJson(Map<String, dynamic> json) =>
      _$RunConfigFromJson(json);

  // Preset run colors are persisted with the config and reused for run badges
  // outside any widget tree, so they intentionally stay as fixed accent values.
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
    color: const Color(0xFF00FF9F),
  );

  static RunConfig flutterBuildMacos({String group = 'default'}) => RunConfig(
    id: 'preset_flutter_build_macos',
    name: 'Flutter Build (macOS)',
    command: 'flutter build macos',
    group: group,
    color: const Color(0xFFFFD700),
  );

  static RunConfig flutterRunWeb(
    String workspacePath, {
    String group = 'default',
  }) => RunConfig(
    id: 'preset_flutter_run_web',
    name: 'Flutter Run (Web)',
    command: 'flutter run -d chrome --debug --target lib/main_web_full.dart',
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

  static RunConfig flutterBuildWeb({String group = 'default'}) => RunConfig(
    id: 'preset_flutter_build_web',
    name: 'Flutter Build (Web)',
    command: 'flutter build web',
    group: group,
    color: const Color(0xFFFFD700),
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
