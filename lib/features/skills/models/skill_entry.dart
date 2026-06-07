import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'skill_entry.g.dart';

/// Where a skill comes from.
enum SkillSourceType {
  github,
  url,
  installScript,
  local,
}

/// A single skill available in the store or installed globally.
@JsonSerializable()
class SkillEntry extends Equatable {
  const SkillEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.source,
    required this.sourceType,
    this.storeId,
    this.installCommand,
    this.installUrl,
    this.isInstalled = false,
    this.computedHash,
  });

  final String id;
  final String name;
  final String description;
  final String source;
  final SkillSourceType sourceType;

  /// Which store this skill came from (null = global/unknown).
  final String? storeId;

  /// Shell command to install this skill (for installScript type).
  final String? installCommand;

  /// URL for more info or docs.
  final String? installUrl;

  /// Whether the skill is installed in the global skills dir.
  final bool isInstalled;

  /// Hash from skills-lock.json (if available).
  final String? computedHash;

  SkillEntry copyWith({
    bool? isInstalled,
    String? computedHash,
    String? description,
  }) =>
      SkillEntry(
        id: id,
        name: name,
        description: description ?? this.description,
        source: source,
        sourceType: sourceType,
        storeId: storeId,
        installCommand: installCommand,
        installUrl: installUrl,
        isInstalled: isInstalled ?? this.isInstalled,
        computedHash: computedHash ?? this.computedHash,
      );

  Map<String, dynamic> toJson() => _$SkillEntryToJson(this);

  factory SkillEntry.fromJson(Map<String, dynamic> j) =>
      _$SkillEntryFromJson(j);

  @override
  List<Object?> get props => [id, source, sourceType, isInstalled];
}
