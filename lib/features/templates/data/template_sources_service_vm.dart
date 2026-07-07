import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/templates/data/template_sources_service_base.dart';
import 'package:yoloit/features/templates/data/template_sources_service_crud.dart';
import 'package:yoloit/features/templates/model/template_models.dart';
///
/// Sources are stored in `~/.config/yoloit/template_sources.json`. A built-in
/// default GitHub source pointing to `IstiN/yoloit` is always returned unless
/// the user explicitly disables or removes it.
class TemplateSourcesService with TemplateSourcesServiceCrud {
  TemplateSourcesService._();

  static final instance = TemplateSourcesService._();

  static const _fileName = 'template_sources.json';

  File get _storageFile {
    final dir = PlatformDirs.instance.configDir;
    return File(p.join(dir, _fileName));
  }

  TemplateSource get defaultSource => buildDefaultSource();

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
      sources = parseSourcesJson(raw);
    } catch (e) {
      debugLogSourceError('[TemplateSourcesService] loadAll error', e);
      sources = [];
    }
    final normalized = _normalizeSources(sources);
    if (!_sameSources(sources, normalized.sources)) {
      await saveAll(normalized.sources);
      if (normalized.clearGithubCache) {
        await _clearGithubCache();
      }
    }
    sources = ensureBuiltinSources(
      normalized.sources,
      defaultSource: defaultSource,
      builtInSource: builtIn,
    );
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
              owner == kDefaultGithubOwner &&
              repo == kDefaultGithubRepo) {
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
    await file.writeAsString(encodeSourcesJson(sources));
  }
}

/// Persists the user's configured template sources.
///
/// Sources are stored in `~/.config/yoloit/template_sources.json`. A built-in
/// default GitHub source pointing to `IstiN/yoloit` is always returned unless
/// the user explicitly disables or removes it.