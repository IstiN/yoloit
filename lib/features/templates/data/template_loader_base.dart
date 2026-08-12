import 'package:yaml/yaml.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

/// Loads board templates from a single source.
abstract class TemplateLoader {
  const TemplateLoader();

  /// Discovers and parses all templates available from this source.
  Future<List<BoardTemplate>> load(TemplateSource source);

  /// For remote sources, refreshes the local cache. Local sources no-op.
  Future<void> sync(TemplateSource source);
}

/// Parses a template from the JSON-like structure produced by [yamlToJson].
BoardTemplate parseTemplate(
  Map<String, dynamic> json, {
  required TemplateSource source,
  required String sourcePath,
}) {
  return BoardTemplate.fromJson(json).copyWith(
    sourceId: source.id,
    sourcePath: sourcePath,
  );
}

/// Converts a YAML document into regular Dart JSON-like structures.
dynamic yamlToJson(dynamic yaml) {
  // Fast path for primitives — skip type checks.
  if (yaml is String || yaml is int || yaml is double || yaml is bool || yaml == null) {
    return yaml;
  }
  if (yaml is YamlMap) {
    final result = <String, dynamic>{};
    for (final entry in yaml.entries) {
      result[entry.key.toString()] = yamlToJson(entry.value);
    }
    return result;
  }
  if (yaml is YamlList) {
    final nodes = yaml.nodes;
    final result = <dynamic>[];
    result.length = nodes.length;
    for (var i = 0; i < nodes.length; i++) {
      result[i] = yamlToJson(nodes[i]);
    }
    return result;
  }
  if (yaml is YamlScalar) {
    return yaml.value;
  }
  return yaml;
}
