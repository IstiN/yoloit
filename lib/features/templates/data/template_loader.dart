import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

/// Loads board templates from a single source.
abstract class TemplateLoader {
  const TemplateLoader();

  /// Discovers and parses all templates available from this source.
  Future<List<BoardTemplate>> load(TemplateSource source);

  /// For remote sources, refreshes the local cache. Local sources no-op.
  Future<void> sync(TemplateSource source);
}

/// Loads templates from a local directory.
///
/// Expected layout:
/// ```
/// <localPath>/
///   flutter_project/template.yaml
///   home_notes/template.yaml
/// ```
class LocalTemplateLoader extends TemplateLoader {
  const LocalTemplateLoader();

  @override
  Future<List<BoardTemplate>> load(TemplateSource source) async {
    final root = source.localPath;
    if (root == null || root.trim().isEmpty) {
      throw ArgumentError('Local source is missing localPath');
    }
    final dir = Directory(root);
    if (!await dir.exists()) return const [];
    final templates = <BoardTemplate>[];
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final template = await _loadTemplateDirectory(entity, source);
      if (template != null) templates.add(template);
    }
    return templates;
  }

  @override
  Future<void> sync(TemplateSource source) async {
    // Local sources do not need syncing.
  }

  Future<BoardTemplate?> _loadTemplateDirectory(
    Directory dir,
    TemplateSource source,
  ) async {
    final file = File(p.join(dir.path, 'template.yaml'));
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final json = _yamlToJson(loadYaml(raw));
      if (json is! Map<String, dynamic>) return null;
      return _parseTemplate(json, source: source, sourcePath: dir.path);
    } catch (e) {
      assert(() {
        debugPrint('[LocalTemplateLoader] failed to load ${dir.path}: $e');
        return true;
      }());
      return null;
    }
  }
}

/// Loads templates from a GitHub repository via the Contents API.
///
/// The repository path is taken from [TemplateSource.githubPath] (default
/// `yoloit/templates`). Each immediate subdirectory that contains a
/// `template.yaml` file becomes a template.
class GitHubTemplateLoader extends TemplateLoader {
  const GitHubTemplateLoader();

  static const _githubApiHost = 'api.github.com';
  static const _timeout = Duration(seconds: 30);

  @override
  Future<List<BoardTemplate>> load(TemplateSource source) async {
    final cacheDir = _cacheDirFor(source);
    if (await cacheDir.exists()) {
      return const LocalTemplateLoader().load(
        source.copyWith(type: TemplateSourceType.local, localPath: cacheDir.path),
      );
    }
    // If no cache exists yet, sync first.
    await sync(source);
    return load(source);
  }

  @override
  Future<void> sync(TemplateSource source) async {
    final owner = source.githubOwner;
    final repo = source.githubRepo;
    if (owner == null || repo == null) {
      throw ArgumentError('GitHub source is missing owner or repo');
    }
    final branch = source.githubBranch ?? 'main';
    final path = source.githubPath;
    final cacheDir = _cacheDirFor(source);
    await cacheDir.create(recursive: true);

    final headers = _headers(source);

    final listUrl =
        'https://$_githubApiHost/repos/$owner/$repo/contents/$path?ref=$branch';
    final entries = _asJsonList(await _fetchJson(listUrl, headers: headers));

    for (final entry in entries) {
      final type = entry['type'] as String?;
      final name = entry['name'] as String? ?? '';
      if (type != 'dir') continue;
      await _syncTemplateDirectory(
        owner: owner,
        repo: repo,
        branch: branch,
        basePath: path,
        dirName: name,
        targetDir: Directory(p.join(cacheDir.path, name)),
        headers: headers,
      );
    }
  }

  Future<void> _syncTemplateDirectory({
    required String owner,
    required String repo,
    required String branch,
    required String basePath,
    required String dirName,
    required Directory targetDir,
    required Map<String, String> headers,
  }) async {
    final listUrl =
        'https://$_githubApiHost/repos/$owner/$repo/contents/$basePath/$dirName?ref=$branch';
    final entries = _asJsonList(await _fetchJson(listUrl, headers: headers));
    final templateFile =
        entries.where((e) => e['name'] == 'template.yaml').firstOrNull;
    if (templateFile == null) return;

    await targetDir.create(recursive: true);
    final downloadUrl = templateFile['download_url'] as String?;
    if (downloadUrl == null || downloadUrl.isEmpty) return;

    final content = await _fetchText(downloadUrl, headers: headers);
    if (content == null) return;
    await File(p.join(targetDir.path, 'template.yaml')).writeAsString(content);
  }

  Map<String, String> _headers(TemplateSource source) {
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    if (source.githubToken case final token?) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<dynamic> _fetchJson(
    String url, {
    required Map<String, String> headers,
  }) async {
    final text = await _fetchText(url, headers: headers);
    if (text == null || text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (e) {
      assert(() {
        debugPrint('[GitHubTemplateLoader] json decode failed: $url: $e');
        return true;
      }());
      return null;
    }
  }

  Future<String?> _fetchText(
    String url, {
    required Map<String, String> headers,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      headers.forEach(req.headers.set);
      final resp = await req.close().timeout(_timeout);
      if (resp.statusCode != 200) return null;
      return await resp.transform(utf8.decoder).join();
    } catch (e) {
      assert(() {
        debugPrint('[GitHubTemplateLoader] fetch failed: $url: $e');
        return true;
      }());
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Directory _cacheDirFor(TemplateSource source) {
    final base = PlatformDirs.instance.configDir;
    return Directory(p.join(base, 'templates', 'cache', source.id));
  }

  List<Map<String, dynamic>> _asJsonList(dynamic response) {
    if (response is! List) return const [];
    return response
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}

BoardTemplate _parseTemplate(
  Map<String, dynamic> json, {
  required TemplateSource source,
  required String sourcePath,
}) {
  final rawParams = json['parameters'] as List?;
  final rawOps = json['operations'] as List?;
  return BoardTemplate(
    id: (json['id'] as String? ?? '').trim(),
    name: json['name'] as String? ?? json['id'] as String? ?? 'Template',
    icon: json['icon'] as String?,
    author: json['author'] as String?,
    description: json['description'] as String?,
    parameters:
        rawParams
            ?.map(
              (e) => TemplateParameter.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList() ??
        const [],
    operations:
        rawOps
            ?.map(
              (e) => TemplateOperation.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList() ??
        const [],
    sourceId: source.id,
    sourcePath: sourcePath,
  );
}

/// Converts a YAML document into regular Dart JSON-like structures.
///
/// This is necessary because `package:yaml` returns `YamlMap`/`YamlList`
/// instances that do not round-trip through `jsonEncode`.
dynamic _yamlToJson(dynamic yaml) {
  if (yaml is YamlMap) {
    return <String, dynamic>{
      for (final entry in yaml.entries)
        entry.key.toString(): _yamlToJson(entry.value),
    };
  }
  if (yaml is YamlList) {
    return yaml.nodes.map(_yamlToJson).toList();
  }
  if (yaml is YamlScalar) {
    return yaml.value;
  }
  return yaml;
}
