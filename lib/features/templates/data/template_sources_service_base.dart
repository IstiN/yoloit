import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

/// Parses a JSON string into a list of [TemplateSource] objects.
List<TemplateSource> parseSourcesJson(String raw) {
  final decoded = jsonDecode(raw) as List<dynamic>;
  return decoded
      .map(
        (e) => TemplateSource.fromJson(
          Map<String, dynamic>.from(e as Map),
        ),
      )
      .toList();
}

/// Serializes a list of [TemplateSource] objects to a JSON string.
String encodeSourcesJson(List<TemplateSource> sources) {
  return jsonEncode(sources.map((s) => s.toJson()).toList());
}

/// Logs a source-service error in debug builds only.
void debugLogSourceError(String message, Object error) {
  assert(() {
    debugPrint('$message: $error');
    return true;
  }());
}

/// Replaces an existing source or appends a new one.
List<TemplateSource> upsertSource(
  List<TemplateSource> sources,
  TemplateSource source,
) {
  final index = sources.indexWhere((s) => s.id == source.id);
  if (index >= 0) {
    final updated = [...sources];
    updated[index] = source;
    return updated;
  }
  return [...sources, source];
}

/// Removes the source with the given [id].
List<TemplateSource> removeSource(List<TemplateSource> sources, String id) {
  return sources.where((s) => s.id != id).toList();
}

/// Ensures [defaultSource] is present and optionally prepends [builtInSource]
/// when it is non-null and not already present.
List<TemplateSource> ensureBuiltinSources(
  List<TemplateSource> sources, {
  required TemplateSource defaultSource,
  required TemplateSource? builtInSource,
}) {
  var result = sources;
  if (!result.any((s) => s.id == defaultSource.id)) {
    result = [defaultSource, ...result];
  }
  if (builtInSource != null &&
      !result.any((s) => s.id == builtInSource.id)) {
    result = [builtInSource, ...result];
  }
  return result;
}

/// Default GitHub owner/repo/branch/path for bundled template sources.
const String kDefaultGithubOwner = 'IstiN';
const String kDefaultGithubRepo = 'yoloit';
const String kDefaultGithubBranch = 'main';
const String kDefaultGithubPath = 'yoloit/templates';

/// Builds the default GitHub-backed template source.
TemplateSource buildDefaultSource() {
  return const TemplateSource(
    id: 'yoloit-github',
    type: TemplateSourceType.github,
    githubOwner: kDefaultGithubOwner,
    githubRepo: kDefaultGithubRepo,
    githubBranch: kDefaultGithubBranch,
    githubPath: kDefaultGithubPath,
  );
}
