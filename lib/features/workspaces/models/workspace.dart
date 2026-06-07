import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/board/model/board_json_converters.dart';

part 'workspace.g.dart';

@JsonSerializable()
class Workspace extends Equatable {
  const Workspace({
    required this.id,
    required this.name,
    required this.paths,
    this.gitBranch,
    this.addedLines = 0,
    this.removedLines = 0,
    this.isActive = false,
    this.color,
    this.enabledSkills = const [],
  });

  final String id;
  final String name;
  /// Ordered list of referenced folder paths. First path is the "primary" one
  /// used for git info display.
  final List<String> paths;
  final String? gitBranch;
  final int addedLines;
  final int removedLines;
  final bool isActive;
  /// User-chosen accent color for this workspace (null = use theme default)
  @ColorNullableJsonConverter()
  final Color? color;
  /// Skill IDs enabled in this workspace (symlinked into .agents/skills/).
  final List<String> enabledSkills;

  /// Primary path (first in list) — used for git operations and display.
  /// Returns empty string if no paths exist.
  String get path => paths.isNotEmpty ? paths.first : '';

  /// The internal workspace directory where symlinks to all paths live.
  /// Copilot/Claude are launched from here and can see all repos.
  String get workspaceDir =>
      p.join(PlatformDirs.instance.configDir, 'workspaces', id);

  Workspace copyWith({
    String? name,
    List<String>? paths,
    String? gitBranch,
    int? addedLines,
    int? removedLines,
    bool? isActive,
    Color? color,
    bool clearColor = false,
    List<String>? enabledSkills,
  }) {
    return Workspace(
      id: id,
      name: name ?? this.name,
      paths: paths ?? this.paths,
      gitBranch: gitBranch ?? this.gitBranch,
      addedLines: addedLines ?? this.addedLines,
      removedLines: removedLines ?? this.removedLines,
      isActive: isActive ?? this.isActive,
      color: clearColor ? null : (color ?? this.color),
      enabledSkills: enabledSkills ?? this.enabledSkills,
    );
  }

  Map<String, dynamic> toJson() => _$WorkspaceToJson(this);

  factory Workspace.fromJson(Map<String, dynamic> json) {
    // Support both new 'paths' list and legacy 'path' string.
    final List<String> paths;
    if (json['paths'] is List) {
      paths = (json['paths'] as List).cast<String>();
    } else if (json['path'] is String && (json['path'] as String).isNotEmpty) {
      paths = [json['path'] as String];
    } else {
      paths = [];
    }
    // Inject normalized 'paths' into the map so the generated helper
    // doesn't crash on a missing key.
    final normalized = Map<String, dynamic>.from(json)..['paths'] = paths;
    final base = _$WorkspaceFromJson(normalized);
    return Workspace(
      id: base.id,
      name: base.name,
      paths: paths,
      gitBranch: base.gitBranch,
      addedLines: base.addedLines,
      removedLines: base.removedLines,
      isActive: base.isActive,
      color: base.color,
      enabledSkills: base.enabledSkills,
    );
  }

  @override
  List<Object?> get props =>
      [id, name, paths, gitBranch, addedLines, removedLines, isActive, color, enabledSkills];
}
