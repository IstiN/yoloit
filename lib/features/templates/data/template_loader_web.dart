import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import 'package:yoloit/features/templates/data/template_loader_base.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

/// Loads built-in board templates from Flutter assets.
///
/// The web cannot enumerate asset directories, so the list of template ids is
/// bundled explicitly. Each id maps to `yoloit/templates/{id}/template.yaml`.
class LocalTemplateLoader extends TemplateLoader {
  const LocalTemplateLoader();

  static const _templateIds = <String>[
    'brainstorm',
    'customer_journey_map',
    'fitness_progress',
    'flutter_project',
    'habit_tracker',
    'home_notes',
    'impact_effort_matrix',
    'okr_planning',
    'personal_expenses',
    'product_roadmap',
    'retrospective',
    'sales_dashboard',
    'sprint_planning',
    'trip_planner',
    'user_story_map',
    'weekly_review',
  ];

  @override
  Future<List<BoardTemplate>> load(TemplateSource source) async {
    final localPath = source.localPath ?? 'yoloit/templates';
    final templates = <BoardTemplate>[];
    for (final id in _templateIds) {
      final assetPath = '$localPath/$id/template.yaml';
      try {
        final template = await _loadTemplateAsset(assetPath, source);
        if (template != null) templates.add(template);
      } catch (e) {
        assert(() {
          debugPrint('[LocalTemplateLoader] failed to load $assetPath: $e');
          return true;
        }());
      }
    }
    return templates;
  }

  @override
  Future<void> sync(TemplateSource source) async {
    // Built-in assets do not need syncing.
  }

  Future<BoardTemplate?> _loadTemplateAsset(
    String assetPath,
    TemplateSource source,
  ) async {
    final raw = await rootBundle.loadString(assetPath);
    final json = yamlToJson(loadYaml(raw));
    if (json is! Map<String, dynamic>) return null;
    return parseTemplate(json, source: source, sourcePath: assetPath);
  }
}

/// No-op GitHub loader for the web.
///
/// The GitHub Contents API does not support CORS from a browser origin, so
/// remote template sources are disabled on the web. The built-in asset
/// templates provide the same default experience.
class GitHubTemplateLoader extends TemplateLoader {
  const GitHubTemplateLoader();

  @override
  Future<List<BoardTemplate>> load(TemplateSource source) async => const [];

  @override
  Future<void> sync(TemplateSource source) async {}
}
