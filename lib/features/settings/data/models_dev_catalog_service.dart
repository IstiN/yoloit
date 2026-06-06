import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/utils/http_utils.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models.dev Catalog Service
//
// Fetches https://models.dev/api.json and caches it locally.
// Same strategy as opencode itself:
//   1. Return cached in-memory copy if available (refreshed every 60 min).
//   2. Try disk cache (TTL: 5 min for freshness check, but always readable).
//   3. Fetch from models.dev on first load or forced refresh.
//
// Free detection: model.cost.input == 0 && model.cost.output == 0
// Model ID format for opencode CLI: "{providerId}/{modelId}"
// ─────────────────────────────────────────────────────────────────────────────

class ModelsDevModel {
  const ModelsDevModel({
    required this.id,
    required this.name,
    required this.providerId,
    required this.providerName,
    this.inputCost,
    this.outputCost,
    this.contextWindow,
    this.family,
    this.reasoning = false,
    this.attachment = false,
  });

  final String id;
  final String name;
  final String providerId;
  final String providerName;
  final double? inputCost;
  final double? outputCost;
  final int? contextWindow;
  final String? family;
  final bool reasoning;
  final bool attachment;

  bool get isFree => inputCost == 0 && outputCost == 0;

  /// Model ID in opencode CLI format: "{providerId}/{modelId}"
  String get opencodeModelId => '$providerId/$id';

  ChatModelInfo toChatModelInfo({bool isDefault = false}) => ChatModelInfo(
        id: opencodeModelId,
        displayName: name,
        costMultiplier: isFree ? 0 : null,
        isDefault: isDefault,
        inputCostPerMillion: inputCost,
        outputCostPerMillion: outputCost,
        contextWindow: contextWindow,
        providerGroup: providerName,
      );
}

class ModelsDevCatalogService {
  ModelsDevCatalogService._();
  static final instance = ModelsDevCatalogService._();

  static const _apiUrl = 'https://models.dev/api.json';
  static const _fetchTimeout = Duration(seconds: 10);
  static const _cacheTtl = Duration(minutes: 5);
  static const _memoryRefreshInterval = Duration(minutes: 60);

  // In-memory cache
  List<ModelsDevModel>? _models;
  DateTime? _lastMemoryRefresh;

  bool get isLoaded => _models != null;

  @visibleForTesting
  void resetForTesting() {
    _models = null;
    _lastMemoryRefresh = null;
  }

  String get _cachePath =>
      p.join(PlatformDirs.instance.configDir, 'models_dev.json');

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Load and return all models. Uses in-memory cache within refresh interval.
  Future<List<ModelsDevModel>> loadAll({bool force = false}) async {
    final now = DateTime.now();
    final memoryAge = _lastMemoryRefresh == null
        ? null
        : now.difference(_lastMemoryRefresh!);

    if (!force &&
        _models != null &&
        memoryAge != null &&
        memoryAge < _memoryRefreshInterval) {
      return _models!;
    }

    final raw = await _fetchOrLoad(force: force);
    if (raw == null) {
      return _models ?? const [];
    }

    _models = _parse(raw);
    _lastMemoryRefresh = now;
    return _models!;
  }

  /// Returns only models for the given provider (e.g. "opencode").
  Future<List<ModelsDevModel>> modelsForProvider(
    String providerId, {
    bool force = false,
  }) async {
    final all = await loadAll(force: force);
    return all.where((m) => m.providerId == providerId).toList();
  }

  /// Returns [ChatModelInfo] list for opencode provider.
  /// Free models first, then paid sorted by input cost asc.
  Future<List<ChatModelInfo>> opencodeModelsAsChatModelInfo({
    bool force = false,
  }) async {
    final models = await modelsForProvider('opencode', force: force);
    if (models.isEmpty) return kOpencodeModels;

    final free = models.where((m) => m.isFree).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final paid = models.where((m) => !m.isFree).toList()
      ..sort((a, b) => (a.inputCost ?? 0).compareTo(b.inputCost ?? 0));

    final sorted = [...free, ...paid];

    // Mark the first free model (or first overall) as default
    return sorted.indexed.map((entry) {
      final (idx, m) = entry;
      return m.toChatModelInfo(isDefault: idx == 0);
    }).toList();
  }

  /// Returns [ChatModelInfo] list combining:
  /// - FREE opencode provider models (always available without a key)
  /// - ALL models from [configuredProviderIds] (user has keys for these)
  ///
  /// Free models first, then paid grouped by provider.
  Future<List<ChatModelInfo>> opencodeModelsWithAuth({
    required List<String> configuredProviderIds,
    bool force = false,
  }) async {
    final all = await loadAll(force: force);
    if (all.isEmpty) return kOpencodeModels;

    // Free opencode models — available to everyone without a key
    final freeOpencode = all
        .where((m) => m.providerId == 'opencode' && m.isFree)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    // All models from providers the user has configured
    final fromConfigured = <ModelsDevModel>[];
    for (final pid in configuredProviderIds) {
      if (pid == 'opencode') continue; // handled separately above
      final providerModels = all.where((m) => m.providerId == pid).toList()
        ..sort((a, b) {
          // free first within provider, then by cost
          if (a.isFree != b.isFree) return a.isFree ? -1 : 1;
          return (a.inputCost ?? 0).compareTo(b.inputCost ?? 0);
        });
      fromConfigured.addAll(providerModels);
    }

    final combined = [...freeOpencode, ...fromConfigured];
    if (combined.isEmpty) return kOpencodeModels;

    return combined.indexed.map((entry) {
      final (idx, m) = entry;
      return m.toChatModelInfo(isDefault: idx == 0);
    }).toList();
  }

  // ── Fetch / load ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _fetchOrLoad({bool force = false}) async {
    if (!force && await _isCacheFresh()) {
      final cached = await _loadCache();
      if (cached != null) return cached;
    }

    final fetched = await _fetchRemote();
    if (fetched != null) {
      await _saveCache(fetched);
      return fetched;
    }

    // Fallback to stale cache
    return _loadCache();
  }

  Future<bool> _isCacheFresh() async {
    try {
      final file = File(_cachePath);
      if (!await file.exists()) return false;
      final stat = await file.stat();
      return DateTime.now().difference(stat.modified) < _cacheTtl;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _fetchRemote() async {
    return fetchJson(url: _apiUrl, timeout: _fetchTimeout);
  }

  Future<Map<String, dynamic>?> _loadCache() async {
    try {
      final file = File(_cachePath);
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(Map<String, dynamic> data) async {
    try {
      final file = File(_cachePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  // ── Parse ───────────────────────────────────────────────────────────────────

  List<ModelsDevModel> _parse(Map<String, dynamic> data) {
    final result = <ModelsDevModel>[];
    for (final entry in data.entries) {
      final providerId = entry.key;
      final providerData = entry.value as Map<String, dynamic>?;
      if (providerData == null) continue;

      final providerName =
          providerData['name'] as String? ?? providerId;
      final models =
          providerData['models'] as Map<String, dynamic>? ?? {};

      for (final modelEntry in models.entries) {
        final modelId = modelEntry.key;
        final modelData = modelEntry.value as Map<String, dynamic>?;
        if (modelData == null) continue;

        final cost = modelData['cost'] as Map<String, dynamic>?;
        final limit = modelData['limit'] as Map<String, dynamic>?;

        result.add(ModelsDevModel(
          id: modelId,
          name: modelData['name'] as String? ?? modelId,
          providerId: providerId,
          providerName: providerName,
          inputCost: (cost?['input'] as num?)?.toDouble(),
          outputCost: (cost?['output'] as num?)?.toDouble(),
          contextWindow: (limit?['context'] as num?)?.toInt(),
          family: modelData['family'] as String?,
          reasoning: modelData['reasoning'] as bool? ?? false,
          attachment: modelData['attachment'] as bool? ?? false,
        ));
      }
    }
    return result;
  }
}
