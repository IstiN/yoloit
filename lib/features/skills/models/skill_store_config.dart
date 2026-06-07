import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:yoloit/features/skills/models/skill_entry.dart';

part 'skill_store_config.g.dart';

/// Type of skills store.
enum SkillStoreType {
  github,
  url,
  installScript,
  local,
}

/// Configuration for a single skills store source.
@JsonSerializable()
class SkillStore extends Equatable {
  const SkillStore({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final SkillStoreType type;

  /// For github: "owner/repo". For url: full URL. For installScript: the shell command.
  final String url;

  /// Built-in stores cannot be removed.
  final bool isBuiltIn;

  Map<String, dynamic> toJson() => _$SkillStoreToJson(this);

  factory SkillStore.fromJson(Map<String, dynamic> j) =>
      _$SkillStoreFromJson(j);

  @override
  List<Object?> get props => [id, type, url];
}

/// Root config — fetched from GitHub and cached locally.
/// Also contains a [catalog] of known skills so the UI can show them
/// without having to query each store individually.
@JsonSerializable()
class SkillsStoreConfig extends Equatable {
  const SkillsStoreConfig({
    required this.stores,
    this.catalog = const [],
  });

  final List<SkillStore> stores;

  /// Pre-defined skill catalog loaded from the remote config.
  final List<SkillEntry> catalog;

  static const List<SkillStore> _builtInStores = [
    SkillStore(
      id: 'flutter-skills',
      name: 'Flutter Skills',
      type: SkillStoreType.github,
      url: 'flutter/skills',
      isBuiltIn: true,
    ),
    SkillStore(
      id: 'remotion-skills',
      name: 'Remotion AI Skills',
      type: SkillStoreType.url,
      url: 'https://www.remotion.dev/docs/ai/skills',
      isBuiltIn: true,
    ),
    SkillStore(
      id: 'dmtools-skills',
      name: 'DMTools Skills',
      type: SkillStoreType.installScript,
      url: 'curl -fsSL https://github.com/epam/dm.ai/releases/download/v1.7.175/skill-install.sh | bash',
      isBuiltIn: true,
    ),
  ];

  static SkillsStoreConfig get defaults =>
      const SkillsStoreConfig(stores: _builtInStores);

  Map<String, dynamic> toJson() => _$SkillsStoreConfigToJson(this);

  factory SkillsStoreConfig.fromJson(Map<String, dynamic> j) {
    final base = _$SkillsStoreConfigFromJson(j);
    final existingIds = base.stores.map((s) => s.id).toSet();
    final merged = List<SkillStore>.from(base.stores);
    for (final b in _builtInStores) {
      if (!existingIds.contains(b.id)) merged.insert(0, b);
    }
    return SkillsStoreConfig(stores: merged, catalog: base.catalog);
  }

  SkillsStoreConfig withStore(SkillStore store) =>
      SkillsStoreConfig(stores: [...stores, store], catalog: catalog);

  SkillsStoreConfig withoutStore(String storeId) => SkillsStoreConfig(
        stores: stores.where((s) => s.id != storeId).toList(),
        catalog: catalog,
      );

  @override
  List<Object?> get props => [stores, catalog];
}
