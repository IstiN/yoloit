import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:yoloit/features/templates/data/template_loader.dart';
import 'package:yoloit/features/templates/data/template_sources_service.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

/// Central entry point for discovering and applying board templates.
class BoardTemplateService {
  BoardTemplateService({
    TemplateSourcesService? sourcesService,
    Map<TemplateSourceType, TemplateLoader>? loaders,
  }) : _sourcesService = sourcesService ?? TemplateSourcesService.instance,
       _loaders = loaders ?? const {
         TemplateSourceType.local: LocalTemplateLoader(),
         TemplateSourceType.github: GitHubTemplateLoader(),
       };

  static final instance = BoardTemplateService();

  final TemplateSourcesService _sourcesService;
  final Map<TemplateSourceType, TemplateLoader> _loaders;

  List<BoardTemplate>? _cache;
  Future<List<BoardTemplate>>? _loadInFlight;

  /// Loads templates from all enabled sources, merging results and deduping by
  /// template id. Later sources win over earlier ones.
  Future<List<BoardTemplate>> loadAll({bool force = false}) async {
    if (!force && _cache != null) return _cache!;
    if (_loadInFlight != null) return _loadInFlight!;
    return _loadInFlight = _loadAllUncached().then((templates) {
      _cache = List.unmodifiable(templates);
      _loadInFlight = null;
      return _cache!;
    }, onError: (Object error, StackTrace stackTrace) {
      _loadInFlight = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<List<BoardTemplate>> _loadAllUncached() async {
    final sources = await _sourcesService.loadAll();
    final byId = <String, BoardTemplate>{};
    for (final source in sources.where((s) => s.enabled)) {
      final loader = _loaders[source.type];
      if (loader == null) continue;
      try {
        final templates = await loader.load(source);
        for (final template in templates) {
          if (template.id.trim().isEmpty) continue;
          byId[template.id] = template;
        }
      } catch (e) {
        assert(() {
          debugPrint(
            '[BoardTemplateService] failed to load source ${source.id}: $e',
          );
          return true;
        }());
      }
    }
    return byId.values.toList();
  }

  /// Refreshes remote sources and invalidates the in-memory cache.
  Future<List<BoardTemplate>> sync() async {
    final sources = await _sourcesService.loadAll();
    for (final source in sources.where((s) => s.enabled)) {
      final loader = _loaders[source.type];
      if (loader == null) continue;
      try {
        await loader.sync(source);
      } catch (e) {
        assert(() {
          debugPrint(
            '[BoardTemplateService] failed to sync source ${source.id}: $e',
          );
          return true;
        }());
      }
    }
    return loadAll(force: true);
  }

  /// Resolves a template by its id across all sources.
  Future<BoardTemplate?> resolveById(String id) async {
    final templates = await loadAll();
    return templates.where((t) => t.id == id).firstOrNull;
  }

  /// Validates user-provided parameter values against the template schema.
  ///
  /// Returns a map of parameter name → error message. An empty map means the
  /// values are valid.
  Map<String, String> validateParameters(
    BoardTemplate template,
    Map<String, dynamic> values,
  ) {
    final errors = <String, String>{};
    for (final param in template.parameters) {
      final error = _validateParameter(param, values[param.name]);
      if (error != null) {
        errors[param.name] = error;
      }
    }
    return errors;
  }

  /// Validates a single parameter value. Returns the error message, or null
  /// when the value is valid.
  String? _validateParameter(TemplateParameter param, dynamic value) {
    final hasValue = value != null && value.toString().isNotEmpty;
    if (param.required && !hasValue) {
      return 'Required';
    }
    if (!hasValue) return null;
    return _choiceError(param, value) ?? _validationError(param, value);
  }

  String? _validationError(TemplateParameter param, dynamic value) {
    final validation = param.validation;
    if (validation == null) return null;
    final text = value.toString();
    if (validation.minLength != null && text.length < validation.minLength!) {
      return 'Minimum length is ${validation.minLength}';
    }
    if (validation.maxLength != null && text.length > validation.maxLength!) {
      return 'Maximum length is ${validation.maxLength}';
    }
    if (validation.pattern != null &&
        validation.pattern!.isNotEmpty &&
        !RegExp(validation.pattern!).hasMatch(text)) {
      return 'Invalid format';
    }
    return null;
  }

  String? _choiceError(TemplateParameter param, dynamic value) {
    if (param.type != TemplateParameterType.choice || param.options == null) {
      return null;
    }
    final allowed = param.options!.map((o) => o.value).toSet();
    if (!allowed.contains(value.toString())) {
      return 'Invalid option';
    }
    return null;
  }

  /// Builds the effective parameter map by filling in defaults for missing
  /// values and coercing types.
  Map<String, dynamic> buildEffectiveParameters(
    BoardTemplate template,
    Map<String, dynamic> values,
  ) {
    final result = <String, dynamic>{};
    for (final param in template.parameters) {
      var value = values[param.name];
      if (value == null || value.toString().isEmpty) {
        value = param.defaultValue;
      }
      result[param.name] = _coerceValue(value, param.type);
    }
    return result;
  }

  /// Interpolates template parameters into the template operations and filters
  /// out operations whose condition evaluates to false.
  ///
  /// The returned maps are valid `board:apply` operations.
  List<Map<String, dynamic>> buildOperations(
    BoardTemplate template,
    Map<String, dynamic> parameters,
  ) {
    final effective = buildEffectiveParameters(template, parameters);
    final result = <Map<String, dynamic>>[];
    for (final operation in template.operations) {
      if (operation.condition != null) {
        final conditionValue = _interpolate(
          operation.condition!,
          effective,
        );
        if (!_isTruthy(conditionValue)) continue;
      }
      result.add(
        _interpolateMap(operation.payload, effective)
            .cast<String, dynamic>(),
      );
    }
    return result;
  }

  dynamic _coerceValue(dynamic value, TemplateParameterType type) {
    if (value == null) return null;
    switch (type) {
      case TemplateParameterType.boolean:
        if (value is bool) return value;
        return value.toString().toLowerCase() == 'true';
      case TemplateParameterType.choice:
      case TemplateParameterType.string:
      case TemplateParameterType.text:
      case TemplateParameterType.path:
      case TemplateParameterType.color:
        return value.toString();
    }
  }

  bool _isTruthy(dynamic value) {
    if (value is bool) return value;
    final text = value.toString().trim().toLowerCase();
    return text == 'true' || text == 'yes' || text == '1';
  }

  dynamic _interpolate(dynamic value, Map<String, dynamic> parameters) {
    if (value is String) {
      return _interpolateString(value, parameters);
    }
    if (value is Map) {
      return _interpolateMap(value, parameters);
    }
    if (value is List) {
      return value.map((item) => _interpolate(item, parameters)).toList();
    }
    return value;
  }

  String _interpolateString(String value, Map<String, dynamic> parameters) {
    return value.replaceAllMapped(
      RegExp(r'\{\{\s*(\w+)\s*\}\}'),
      (match) {
        final key = match.group(1)!;
        final paramValue = parameters[key];
        return paramValue?.toString() ?? '';
      },
    );
  }

  Map<String, dynamic> _interpolateMap(
    Map<dynamic, dynamic> map,
    Map<String, dynamic> parameters,
  ) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = entry.key.toString();
      result[key] = _interpolate(entry.value, parameters);
    }
    return result;
  }
}

/// Thrown when a template cannot be applied because parameter validation
/// fails.
class TemplateParameterException implements Exception {
  const TemplateParameterException(this.errors);

  final Map<String, String> errors;

  @override
  String toString() => 'TemplateParameterException: ${jsonEncode(errors)}';
}
