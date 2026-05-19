import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Provider model catalog entry
// ─────────────────────────────────────────────────────────────────────────────

class ProviderCatalog {
  const ProviderCatalog({
    required this.id,
    required this.displayName,
    required this.models,
  });

  final String id;
  final String displayName;
  final List<ChatModelInfo> models;

  factory ProviderCatalog.fromJson(Map<String, dynamic> j) {
    final rawModels = j['models'] as List? ?? [];
    return ProviderCatalog(
      id: j['id'] as String,
      displayName: j['displayName'] as String,
      models:
          rawModels
              .map(
                (e) => ChatModelInfo.fromJson(e as Map<String, dynamic>),
              )
              .toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Catalog service
// ─────────────────────────────────────────────────────────────────────────────

/// Loads the provider/model catalog from GitHub raw (no fallback to hardcode).
///
/// Strategy:
///   1. Fetch from GitHub raw on `main` (always up-to-date).
///   2. Cache successfully fetched catalog at ~/.config/yoloit/provider_models.json
///   3. On failure, try local cache.
///   4. If no cache, fall back to bundled asset in the app (same JSON committed to repo).
///   5. No silent defaults — if everything fails an error is surfaced.
///
/// Remote URL: https://raw.githubusercontent.com/IstiN/yoloit/main/assets/config/provider_models.json
class ProviderModelCatalogService {
  ProviderModelCatalogService._();
  static final instance = ProviderModelCatalogService._();

  static const _remoteUrl =
      'https://raw.githubusercontent.com/IstiN/yoloit/main/assets/config/provider_models.json';

  static const _assetPath = 'assets/config/provider_models.json';

  static const _fetchTimeout = Duration(seconds: 8);

  final Map<String, ProviderCatalog> _catalogs = {};
  // user custom models per provider, stored separately
  final Map<String, List<ChatModelInfo>> _customModels = {};

  bool _loaded = false;
  String? _loadError;
  bool _loadedFromRemote = false;

  bool get isLoaded => _loaded;
  String? get loadError => _loadError;
  bool get loadedFromRemote => _loadedFromRemote;

  String get _cachePath =>
      p.join(PlatformDirs.instance.configDir, 'provider_models.json');

  String get _customModelsPath =>
      p.join(PlatformDirs.instance.configDir, 'provider_models_custom.json');

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Loads catalogs. Idempotent — subsequent calls are no-ops unless [force].
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    _loadError = null;

    await _loadCustomModels();

    final json = await _fetchCatalogJson();
    if (json == null) {
      // Try cache
      final cached = await _loadCache();
      if (cached != null) {
        _parseCatalogs(cached);
        _loaded = true;
        _loadedFromRemote = false;
        return;
      }
      // Try bundled asset
      final asset = await _loadAsset();
      if (asset != null) {
        _parseCatalogs(asset);
        _loaded = true;
        _loadedFromRemote = false;
        return;
      }
      _loadError = 'Failed to load provider model catalog: network unavailable and no local cache.';
      _loaded = false;
      return;
    }

    _parseCatalogs(json);
    _loaded = true;
    _loadedFromRemote = true;
    await _saveCache(json);
  }

  /// Returns available models for [providerId] = remote catalog + user custom models.
  /// Returns `null` (not empty list) if catalog has not loaded successfully.
  List<ChatModelInfo>? modelsForProvider(String providerId) {
    if (!_loaded) return null;
    final catalog = _catalogs[providerId];
    final base = catalog?.models ?? [];
    final custom = _customModels[providerId] ?? [];
    return [...base, ...custom];
  }

  /// Returns effective default model id for [providerId].
  String? defaultModelForProvider(String providerId) {
    final models = modelsForProvider(providerId);
    if (models == null || models.isEmpty) return null;
    return models.firstWhere(
      (m) => m.isDefault,
      orElse: () => models.first,
    ).id;
  }

  /// All known provider ids from the catalog.
  List<String> get providerIds => _catalogs.keys.toList();

  List<ProviderCatalog> get allCatalogs =>
      _catalogs.values.toList();

  // ── Custom model management ─────────────────────────────────────────────────

  Future<void> addCustomModel(String providerId, ChatModelInfo model) async {
    _customModels.putIfAbsent(providerId, () => []);
    _customModels[providerId]!.removeWhere((m) => m.id == model.id);
    _customModels[providerId]!.add(model);
    await _saveCustomModels();
  }

  Future<void> removeCustomModel(String providerId, String modelId) async {
    _customModels[providerId]?.removeWhere((m) => m.id == modelId);
    await _saveCustomModels();
  }

  Map<String, List<ChatModelInfo>> get customModels =>
      Map.unmodifiable(_customModels);

  List<ChatModelInfo> customModelsForProvider(String providerId) =>
      List.unmodifiable(_customModels[providerId] ?? []);

  // ── Parse ───────────────────────────────────────────────────────────────────

  void _parseCatalogs(Map<String, dynamic> json) {
    _catalogs.clear();
    final providers = json['providers'] as List? ?? [];
    for (final p in providers) {
      final catalog = ProviderCatalog.fromJson(p as Map<String, dynamic>);
      _catalogs[catalog.id] = catalog;
    }
  }

  // ── Fetch ───────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _fetchCatalogJson() async {
    final client = HttpClient();
    client.connectionTimeout = _fetchTimeout;
    try {
      final req = await client.getUrl(Uri.parse(_remoteUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'YoLoIT');
      final resp = await req.close().timeout(_fetchTimeout);
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join().timeout(_fetchTimeout);
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // ── Cache ───────────────────────────────────────────────────────────────────

  Future<void> _saveCache(Map<String, dynamic> json) async {
    try {
      final file = File(_cachePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(json));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _loadCache() async {
    try {
      final file = File(_cachePath);
      if (!await file.exists()) return null;
      final body = await file.readAsString();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── Bundled asset ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _loadAsset() async {
    try {
      final body = await rootBundle.loadString(_assetPath);
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── Custom models persistence ───────────────────────────────────────────────

  Future<void> _saveCustomModels() async {
    try {
      final file = File(_customModelsPath);
      await file.parent.create(recursive: true);
      final data = _customModels.map(
        (providerId, models) => MapEntry(
          providerId,
          models.map((m) => m.toJson()).toList(),
        ),
      );
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _loadCustomModels() async {
    try {
      final file = File(_customModelsPath);
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _customModels.clear();
      raw.forEach((providerId, models) {
        _customModels[providerId] = (models as List)
            .map((e) => ChatModelInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (_) {}
  }
}
