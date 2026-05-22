import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A configured cloud LLM endpoint (OpenRouter, Google Gemini, OpenAI, etc.).
///
/// All modern cloud LLM APIs follow the OpenAI chat/completions format,
/// so a single provider implementation handles them all — only the base URL,
/// API key, and model ID differ.
class CloudLlmConfig {
  const CloudLlmConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.extraHeaders = const {},
  });

  /// Unique identifier for this config (e.g. 'openrouter', 'gemini-custom').
  final String id;

  /// Human-readable display name.
  final String name;

  /// API base URL (e.g. 'https://openrouter.ai/api/v1').
  /// The provider appends `/chat/completions`.
  final String baseUrl;

  /// API key / bearer token.
  final String apiKey;

  /// Model ID to use (e.g. 'google/gemini-2.0-flash-001').
  final String model;

  /// Optional extra HTTP headers (e.g. X-Title for OpenRouter).
  final Map<String, String> extraHeaders;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    if (extraHeaders.isNotEmpty) 'extraHeaders': extraHeaders,
  };

  factory CloudLlmConfig.fromJson(Map<String, dynamic> json) {
    return CloudLlmConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? '',
      extraHeaders: json['extraHeaders'] is Map
          ? Map<String, String>.from(json['extraHeaders'] as Map)
          : const {},
    );
  }

  CloudLlmConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    Map<String, String>? extraHeaders,
  }) {
    return CloudLlmConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      extraHeaders: extraHeaders ?? this.extraHeaders,
    );
  }

  /// Whether this config has enough data to make API calls.
  bool get isValid =>
      apiKey.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// Presets — quick-start templates for popular providers
// ─────────────────────────────────────────────────────────────────────────────

class CloudLlmPreset {
  const CloudLlmPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    this.extraHeaders = const {},
    this.models = const [],
  });

  final String id;
  final String name;
  final String baseUrl;
  final String defaultModel;
  final Map<String, String> extraHeaders;
  final List<({String id, String name})> models;

  CloudLlmConfig toConfig(String apiKey) => CloudLlmConfig(
    id: id,
    name: name,
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: defaultModel,
    extraHeaders: extraHeaders,
  );
}

const kCloudLlmPresets = <CloudLlmPreset>[
  CloudLlmPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    defaultModel: 'google/gemini-2.0-flash-001',
    extraHeaders: {
      'HTTP-Referer': 'https://yoloit.app',
      'X-Title': 'YoLoIT',
    },
    models: [
      (id: 'google/gemini-2.0-flash-001', name: 'Gemini 2.0 Flash'),
      (id: 'google/gemini-2.5-flash-preview', name: 'Gemini 2.5 Flash Preview'),
      (id: 'meta-llama/llama-3.1-8b-instruct', name: 'Llama 3.1 8B'),
      (id: 'mistralai/mistral-small-3.1-24b-instruct', name: 'Mistral Small 3.1'),
      (id: 'qwen/qwen-2.5-7b-instruct', name: 'Qwen 2.5 7B'),
      (id: 'deepseek/deepseek-chat-v3-0324', name: 'DeepSeek V3'),
      (id: 'anthropic/claude-sonnet-4', name: 'Claude Sonnet 4'),
    ],
  ),
  CloudLlmPreset(
    id: 'gemini',
    name: 'Google Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    defaultModel: 'gemini-2.0-flash',
    models: [
      (id: 'gemini-2.0-flash', name: 'Gemini 2.0 Flash'),
      (id: 'gemini-2.5-flash-preview-05-20', name: 'Gemini 2.5 Flash Preview'),
      (id: 'gemini-2.0-flash-lite', name: 'Gemini 2.0 Flash Lite'),
    ],
  ),
  CloudLlmPreset(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4.1-mini',
    models: [
      (id: 'gpt-4.1-mini', name: 'GPT-4.1 Mini'),
      (id: 'gpt-4.1', name: 'GPT-4.1'),
      (id: 'gpt-4.1-nano', name: 'GPT-4.1 Nano'),
    ],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Settings service — persists cloud provider configs
// ─────────────────────────────────────────────────────────────────────────────

class CloudLlmSettingsService {
  CloudLlmSettingsService._();

  static final instance = CloudLlmSettingsService._();

  static const _storageKey = 'cloud_llm_configs_v1';
  static const _prefsFallbackKey = 'cloud_llm_configs_fallback_v1';
  static const _activeConfigPrefKey = 'cloud_llm_active_config_v1';
  static const _assistantProviderPrefKey = 'assistant_provider_type_v1';

  static FlutterSecureStorage _buildStorage() {
    if (Platform.isMacOS) {
      return const FlutterSecureStorage(mOptions: MacOsOptions());
    } else if (Platform.isWindows) {
      return const FlutterSecureStorage(
        wOptions: WindowsOptions(useBackwardCompatibility: false),
      );
    } else {
      return const FlutterSecureStorage(lOptions: LinuxOptions());
    }
  }

  final _storage = _buildStorage();

  /// Load all saved cloud provider configs.
  Future<List<CloudLlmConfig>> loadConfigs() async {
    String? raw;
    try {
      raw = await _storage.read(key: _storageKey);
    } on Exception {
      raw = null;
    }
    if (raw == null || raw.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(_prefsFallbackKey);
    }
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => CloudLlmConfig.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Save all cloud provider configs.
  Future<void> saveConfigs(List<CloudLlmConfig> configs) async {
    final encoded = jsonEncode(configs.map((c) => c.toJson()).toList());
    try {
      await _storage.write(key: _storageKey, value: encoded);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsFallbackKey);
    } on Exception {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsFallbackKey, encoded);
    }
  }

  /// Add or update a config (matched by id).
  Future<void> upsertConfig(CloudLlmConfig config) async {
    final configs = await loadConfigs();
    final idx = configs.indexWhere((c) => c.id == config.id);
    if (idx >= 0) {
      configs[idx] = config;
    } else {
      configs.add(config);
    }
    await saveConfigs(configs);
  }

  /// Remove a config by id.
  Future<void> removeConfig(String id) async {
    final configs = await loadConfigs();
    configs.removeWhere((c) => c.id == id);
    await saveConfigs(configs);
  }

  /// Get the active config id for the assistant.
  Future<String?> loadActiveConfigId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeConfigPrefKey);
  }

  /// Set the active config id.
  Future<void> saveActiveConfigId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_activeConfigPrefKey);
    } else {
      await prefs.setString(_activeConfigPrefKey, id);
    }
  }

  /// Get the active config (resolved from id).
  Future<CloudLlmConfig?> loadActiveConfig() async {
    final id = await loadActiveConfigId();
    if (id == null) return null;
    final configs = await loadConfigs();
    try {
      return configs.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get a specific config by ID.
  Future<CloudLlmConfig?> loadConfigById(String id) async {
    final configs = await loadConfigs();
    try {
      return configs.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Whether the assistant should use cloud provider ('cloud') or local ('local').
  Future<String> loadAssistantProviderType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_assistantProviderPrefKey) ?? 'local';
  }

  /// Set the assistant provider type.
  Future<void> saveAssistantProviderType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_assistantProviderPrefKey, type);
  }
}
