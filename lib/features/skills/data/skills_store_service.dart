import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/utils/http_utils.dart';
import 'package:yoloit/features/skills/models/skill_entry.dart';
import 'package:yoloit/features/skills/models/skill_store_config.dart';

/// Manages the skills store config and fetches available skills from stores.
///
/// Source of truth: skills_store.json committed to the yoloit GitHub repo.
/// Remote URL: https://raw.githubusercontent.com/IstiN/yoloit/main/skills_store.json
///
/// Strategy:
///   1. Try to fetch remote config from GitHub (always up-to-date catalog).
///   2. Cache the result locally at ~/.config/yoloit/skills_store.json.
///   3. On failure, use the cached local copy.
///   4. On no cache, fall back to built-in defaults.
class SkillsStoreService {
  SkillsStoreService._();
  static final instance = SkillsStoreService._();

  static const _remoteConfigUrl =
      'https://raw.githubusercontent.com/IstiN/yoloit/main/skills_store.json';

  static const _fetchTimeout = Duration(seconds: 8);

  SkillsStoreConfig _config = SkillsStoreConfig.defaults;
  List<SkillEntry> _availableSkills = [];

  /// Whether the last load successfully fetched from remote.
  bool _loadedFromRemote = false;

  String get _cacheConfigPath =>
      p.join(PlatformDirs.instance.configDir, 'skills_store.json');

  String get _skillsDir => PlatformDirs.instance.skillsDir;

  SkillsStoreConfig get config => _config;
  List<SkillEntry> get availableSkills => _availableSkills;
  bool get loadedFromRemote => _loadedFromRemote;

  // ── Load ────────────────────────────────────────────────────────────────────

  /// Loads config + scans installed skills. Returns full skill list.
  Future<List<SkillEntry>> load() async {
    await _loadConfig();
    _availableSkills = await _buildSkillList();
    return _availableSkills;
  }

  Future<void> _loadConfig() async {
    // 1. Try remote
    final remote = await _fetchRemoteConfig();
    if (remote != null) {
      _config = remote;
      _loadedFromRemote = true;
      await _saveLocalCache(remote);
      return;
    }
    _loadedFromRemote = false;

    // 2. Try local cache
    final cached = await _loadLocalCache();
    if (cached != null) {
      _config = cached;
      return;
    }

    // 3. Built-in defaults
    _config = SkillsStoreConfig.defaults;
  }

  Future<SkillsStoreConfig?> _fetchRemoteConfig() async {
    final data = await fetchJson(
      url: _remoteConfigUrl,
      timeout: _fetchTimeout,
    );
    if (data == null) return null;
    return SkillsStoreConfig.fromJson(data);
  }

  Future<SkillsStoreConfig?> _loadLocalCache() async {
    try {
      final file = File(_cacheConfigPath);
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        return SkillsStoreConfig.fromJson(data);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveLocalCache(SkillsStoreConfig config) async {
    try {
      final file = File(_cacheConfigPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config.toJson()),
      );
    } catch (_) {}
  }

  // ── Custom store management ─────────────────────────────────────────────────

  /// Saves a user-modified config (e.g. added custom stores) to local cache.
  /// Does NOT push to GitHub — users update the remote by committing to the repo.
  Future<void> saveConfig(SkillsStoreConfig config) async {
    _config = config;
    await _saveLocalCache(config);
  }

  // ── Skill list ──────────────────────────────────────────────────────────────

  /// Builds the combined skill list: installed skills + catalog from config.
  Future<List<SkillEntry>> _buildSkillList() async {
    final installed = await _scanInstalledSkills();
    final installedIds = installed.map((s) => s.id).toSet();

    // Prefer catalog from remote config; fall back to hard-coded list.
    final catalogSkills = _config.catalog.isNotEmpty
        ? _config.catalog
        : _builtInFlutterSkills();

    // Merge installed status into catalog entries.
    final fromCatalog = catalogSkills
        .map((s) => installedIds.contains(s.id) ? s.copyWith(isInstalled: true) : s)
        .toList();

    // Add installed skills not present in catalog (manually installed).
    final catalogIds = fromCatalog.map((s) => s.id).toSet();
    final extra = installed.where((s) => !catalogIds.contains(s.id)).toList();

    return [...fromCatalog, ...extra];
  }

  /// Scans ~/.config/yoloit/skills/ for installed skill directories.
  Future<List<SkillEntry>> _scanInstalledSkills() async {
    final dir = Directory(_skillsDir);
    if (!await dir.exists()) return [];
    final skills = <SkillEntry>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final skillId = p.basename(entity.path);
        final skillMd = File(p.join(entity.path, 'SKILL.md'));
        String description = '';
        String name = skillId;
        if (await skillMd.exists()) {
          final content = await skillMd.readAsString();
          description = _extractDescription(content);
          name = _extractName(content) ?? skillId;
        }
        skills.add(SkillEntry(
          id: skillId,
          name: name,
          description: description,
          source: 'local',
          sourceType: SkillSourceType.local,
          isInstalled: true,
        ));
      }
    }
    return skills;
  }

  String _extractDescription(String content) {
    final lines = content.split('\n');
    for (final line in lines) {
      if (line.startsWith('description:')) {
        return line.replaceFirst('description:', '').trim();
      }
    }
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty &&
          !trimmed.startsWith('#') &&
          !trimmed.startsWith('---') &&
          !trimmed.startsWith('name:')) {
        return trimmed.length > 120 ? '${trimmed.substring(0, 120)}…' : trimmed;
      }
    }
    return '';
  }

  String? _extractName(String content) {
    for (final line in content.split('\n')) {
      if (line.startsWith('name:')) {
        return line.replaceFirst('name:', '').trim();
      }
    }
    return null;
  }

  /// Refreshes installed status after an install/uninstall.
  Future<void> refresh() async {
    _availableSkills = await _buildSkillList();
  }

  /// Reads the raw SKILL.md content for an installed skill, if present.
  Future<String?> readSkillContent(String skillId) async {
    final file = File(p.join(_skillsDir, skillId, 'SKILL.md'));
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Hard-coded fallback list for when the remote has no catalog field.
  List<SkillEntry> _builtInFlutterSkills() {
    const flutterSkills = [
      ('flutter-adding-home-screen-widgets', 'Adding Home Screen Widgets', 'Add home screen widgets to a Flutter app'),
      ('flutter-animating-apps', 'Animating Apps', 'Add animations and transitions to Flutter apps'),
      ('flutter-architecting-apps', 'Architecting Apps', 'Structure and architect Flutter apps'),
      ('flutter-building-forms', 'Building Forms', 'Build forms and handle user input in Flutter'),
      ('flutter-building-layouts', 'Building Layouts', 'Create and manage layouts in Flutter'),
      ('flutter-building-plugins', 'Building Plugins', 'Create Flutter platform plugins'),
      ('flutter-caching-data', 'Caching Data', 'Cache data efficiently in Flutter'),
      ('flutter-embedding-native-views', 'Embedding Native Views', 'Embed native platform views in Flutter'),
      ('flutter-handling-concurrency', 'Handling Concurrency', 'Manage async operations and concurrency'),
      ('flutter-handling-http-and-json', 'Handling HTTP and JSON', 'Make HTTP requests and parse JSON'),
      ('flutter-implementing-navigation-and-routing', 'Navigation and Routing', 'Implement navigation and routing'),
      ('flutter-improving-accessibility', 'Improving Accessibility', 'Make Flutter apps more accessible'),
      ('flutter-interoperating-with-native-apis', 'Native API Interop', 'Use native platform APIs from Flutter'),
      ('flutter-localizing-apps', 'Localizing Apps', 'Add internationalization and localization'),
      ('flutter-managing-state', 'Managing State', 'Manage application and UI state'),
      ('flutter-reducing-app-size', 'Reducing App Size', 'Optimize and reduce Flutter app size'),
      ('flutter-setting-up-on-linux', 'Setup on Linux', 'Set up Flutter development on Linux'),
      ('flutter-setting-up-on-macos', 'Setup on macOS', 'Set up Flutter development on macOS'),
      ('flutter-setting-up-on-windows', 'Setup on Windows', 'Set up Flutter development on Windows'),
      ('flutter-testing-apps', 'Testing Apps', 'Write tests for Flutter apps'),
      ('flutter-theming-apps', 'Theming Apps', 'Apply themes and styling to Flutter apps'),
      ('flutter-working-with-databases', 'Working with Databases', 'Integrate databases in Flutter'),
    ];
    return flutterSkills
        .map((t) => SkillEntry(
              id: t.$1,
              name: t.$2,
              description: t.$3,
              source: 'flutter/skills',
              sourceType: SkillSourceType.github,
              storeId: 'flutter-skills',
              isInstalled: false,
            ))
        .toList();
  }
}
