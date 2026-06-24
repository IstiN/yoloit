import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

/// Persists the user's configured template sources.
///
/// Sources are stored in `~/.config/yoloit/template_sources.json`. A built-in
/// default GitHub source pointing to `IstiN/yoloit` is always returned unless
/// the user explicitly disables or removes it.
class TemplateSourcesService {
  TemplateSourcesService._();

  static final instance = TemplateSourcesService._();

  static const _fileName = 'template_sources.json';
  static const _defaultGithubOwner = 'IstiN';
  static const _defaultGithubRepo = 'yoloit';

  File get _storageFile {
    final dir = PlatformDirs.instance.configDir;
    return File(p.join(dir, _fileName));
  }

  TemplateSource get defaultSource => const TemplateSource(
    id: 'yoloit-github',
    type: TemplateSourceType.github,
    githubOwner: _defaultGithubOwner,
    githubRepo: _defaultGithubRepo,
    githubBranch: 'main',
    githubPath: 'yoloit/templates',
  );

  /// A local source pointing at the built-in templates that ship with the
  /// repository (under `yoloit/templates`). It is only enabled when that
  /// directory exists at runtime, which is the case when running from the
  /// project root during development or when the templates have been bundled
  /// next to the executable.
  TemplateSource? get builtInSource {
    final localPath = p.absolute('yoloit', 'templates');
    if (!Directory(localPath).existsSync()) return null;
    return TemplateSource(
      id: 'yoloit-builtins',
      type: TemplateSourceType.local,
      localPath: localPath,
    );
  }

  Future<List<TemplateSource>> loadAll() async {
    final file = _storageFile;
    final builtIn = builtInSource;
    List<TemplateSource> sources;
    if (!await file.exists()) {
      sources = builtIn == null ? [defaultSource] : [builtIn, defaultSource];
      return sources;
    }
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        sources = builtIn == null ? [defaultSource] : [builtIn, defaultSource];
        return sources;
      }
      final decoded = jsonDecode(raw) as List<dynamic>;
      sources =
          decoded
              .map(
                (e) => TemplateSource.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList();
    } catch (e) {
      assert(() {
        debugPrint('[TemplateSourcesService] loadAll error: $e');
        return true;
      }());
      sources = [];
    }
    final normalized = _normalizeSources(sources);
    if (!_sameSources(sources, normalized.sources)) {
      await saveAll(normalized.sources);
      if (normalized.clearGithubCache) {
        await _clearGithubCache();
      }
    }
    sources = normalized.sources;
    // Ensure the default source exists unless explicitly removed.
    if (!sources.any((s) => s.id == defaultSource.id)) {
      sources = [defaultSource, ...sources];
    }
    // Inject the built-in source at the front unless the user has explicitly
    // configured it (enabled or disabled).
    if (builtIn != null && !sources.any((s) => s.id == builtIn.id)) {
      sources = [builtIn, ...sources];
    }
    return sources;
  }

  ({List<TemplateSource> sources, bool clearGithubCache}) _normalizeSources(
    List<TemplateSource> sources,
  ) {
    var clearGithubCache = false;
    final normalized =
        sources.map((source) {
          if (source.id != defaultSource.id ||
              source.type != TemplateSourceType.github) {
            return source;
          }
          final owner = source.githubOwner ?? '';
          final repo = source.githubRepo ?? '';
          final isLegacyDefault =
              owner == 'yoloit' && repo == 'yoloit' ||
              owner.isEmpty ||
              repo.isEmpty;
          if (!isLegacyDefault &&
              owner == _defaultGithubOwner &&
              repo == _defaultGithubRepo) {
            return source;
          }
          clearGithubCache = true;
          return defaultSource.copyWith(
            enabled: source.enabled,
            githubToken: source.githubToken,
          );
        }).toList();
    return (sources: normalized, clearGithubCache: clearGithubCache);
  }

  bool _sameSources(List<TemplateSource> a, List<TemplateSource> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toJson().toString() != b[i].toJson().toString()) {
        return false;
      }
    }
    return true;
  }

  Future<void> _clearGithubCache() async {
    final cacheDir = Directory(
      p.join(
        PlatformDirs.instance.configDir,
        'templates',
        'cache',
        defaultSource.id,
      ),
    );
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
  }

  Future<void> saveAll(List<TemplateSource> sources) async {
    final file = _storageFile;
    await file.parent.create(recursive: true);
    final encoded = jsonEncode(sources.map((s) => s.toJson()).toList());
    await file.writeAsString(encoded);
  }

  Future<void> addOrUpdate(TemplateSource source) async {
    final sources = await loadAll();
    final index = sources.indexWhere((s) => s.id == source.id);
    final List<TemplateSource> updated;
    if (index >= 0) {
      updated = [...sources];
      updated[index] = source;
    } else {
      updated = [...sources, source];
    }
    await saveAll(updated);
  }

  Future<void> remove(String id) async {
    final sources = await loadAll();
    final updated = sources.where((s) => s.id != id).toList();
    await saveAll(updated);
  }
}
