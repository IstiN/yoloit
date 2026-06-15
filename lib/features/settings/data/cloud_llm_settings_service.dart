import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/secure_storage_factory.dart';

part 'cloud_llm_settings_service.g.dart';

/// A configured cloud LLM endpoint (OpenRouter, Google Gemini, OpenAI, etc.).
///
/// All modern cloud LLM APIs follow the OpenAI chat/completions format,
/// so a single provider implementation handles them all — only the base URL,
/// API key, and model ID differ.
@JsonSerializable()
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

  Map<String, dynamic> toJson() => _$CloudLlmConfigToJson(this);

  factory CloudLlmConfig.fromJson(Map<String, dynamic> json) =>
      _$CloudLlmConfigFromJson(json);

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
  ///
  /// Local endpoints (e.g. Ollama on localhost) do not require an API key.
  bool get isValid {
    final url = baseUrl.trim().toLowerCase();
    final isLocalEndpoint =
        url.contains('localhost') ||
        url.contains('127.0.0.1') ||
        url.contains('::1') ||
        url.contains('ollama');
    return
        baseUrl.trim().isNotEmpty &&
        model.trim().isNotEmpty &&
        (isLocalEndpoint || apiKey.trim().isNotEmpty);
  }
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

const _openRouterRecommendedModelIds = <String>[
  'google/gemma-4-31b-it',
  'nvidia/nemotron-nano-12b-v2-vl:free',
  'qwen/qwen3.5-flash-02-23',
  'google/gemma-4-26b-a4b-it',
  'mistralai/mistral-small-3.2-24b-instruct',
  'qwen/qwen3.6-35b-a3b',
  'google/gemini-3-flash-preview',
  'google/gemini-3.1-flash-lite-preview',
  'mistralai/voxtral-small-24b-2507',
  'xiaomi/mimo-v2.5',
  'google/chirp-3',
  'qwen/qwen3-asr-flash-2026-02-10',
  'mistralai/voxtral-mini-transcribe',
  'openai/whisper-large-v3-turbo',
  'openai/whisper-large-v3',
];

const _openRouterDefaultModel = 'google/gemma-4-31b-it';

const kCloudLlmPresets = <CloudLlmPreset>[
  CloudLlmPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    defaultModel: _openRouterDefaultModel,
    extraHeaders: {'HTTP-Referer': 'https://yoloit.app', 'X-Title': 'YoLoIT'},
    models: [
      (id: 'google/gemma-4-31b-it', name: 'Gemma 4 31B'),
      (
        id: 'nvidia/nemotron-nano-12b-v2-vl:free',
        name: 'Nemotron Nano 12B VL (Free)',
      ),
      (id: 'qwen/qwen3.5-flash-02-23', name: 'Qwen 3.5 Flash'),
      (id: 'google/gemma-4-26b-a4b-it', name: 'Gemma 4 26B A4B'),
      (
        id: 'mistralai/mistral-small-3.2-24b-instruct',
        name: 'Mistral Small 3.2 24B',
      ),
      (id: 'qwen/qwen3.6-35b-a3b', name: 'Qwen 3.6 35B A3B'),
      (id: 'google/gemini-3-flash-preview', name: 'Gemini 3 Flash Preview'),
      (
        id: 'google/gemini-3.1-flash-lite-preview',
        name: 'Gemini 3.1 Flash Lite Preview',
      ),
      (
        id: 'mistralai/voxtral-small-24b-2507',
        name: 'Voxtral Small 24B (Audio)',
      ),
      (id: 'xiaomi/mimo-v2.5', name: 'MiMo v2.5'),
      (id: 'google/chirp-3', name: 'Google Chirp 3 (ASR)'),
      (
        id: 'qwen/qwen3-asr-flash-2026-02-10',
        name: 'Qwen 3 ASR Flash (2026-02-10)',
      ),
      (
        id: 'mistralai/voxtral-mini-transcribe',
        name: 'Voxtral Mini Transcribe',
      ),
      (id: 'openai/whisper-large-v3-turbo', name: 'Whisper Large v3 Turbo'),
      (id: 'openai/whisper-large-v3', name: 'Whisper Large v3'),
    ],
  ),
  CloudLlmPreset(
    id: 'ollama-local',
    name: 'Ollama (Local)',
    baseUrl: 'http://localhost:11434/v1',
    defaultModel: 'qwen3:8b',
    models: [
      (id: 'qwen3:8b', name: 'Qwen 3 8B'),
      (id: 'qwen3:32b', name: 'Qwen 3 32B'),
      (id: 'llama3.1:8b', name: 'Llama 3.1 8B'),
      (id: 'mistral:7b', name: 'Mistral 7B'),
      (id: 'gemma3:27b', name: 'Gemma 3 27B'),
      (id: 'deepseek-r1:14b', name: 'DeepSeek R1 14B'),
      (id: 'ministral-3:14b', name: 'Ministral 3 14B'),
    ],
  ),
  CloudLlmPreset(
    id: 'ollama',
    name: 'Ollama',
    baseUrl: 'https://ollama.com/v1',
    defaultModel: 'ministral-3:14b',
    models: [
      (id: 'ministral-3:14b', name: 'Ministral 3 14B'),
      (id: 'qwen3:32b', name: 'Qwen 3 32B'),
      (id: 'qwen3:8b', name: 'Qwen 3 8B'),
      (id: 'llama3.1:8b', name: 'Llama 3.1 8B'),
      (id: 'mistral:7b', name: 'Mistral 7B'),
      (id: 'gemma3:27b', name: 'Gemma 3 27B'),
      (id: 'deepseek-r1:14b', name: 'DeepSeek R1 14B'),
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
  static const _voiceSettingsPrefKey = 'voice_settings_v1';

  final _storage = SecureStorageFactory.create();

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
          .map(
            (e) => CloudLlmConfig.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .map(_normalizeConfig)
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
    final normalized = _normalizeConfig(config);
    final idx = configs.indexWhere((c) => c.id == normalized.id);
    if (idx >= 0) {
      configs[idx] = normalized;
    } else {
      configs.add(normalized);
    }
    await saveConfigs(configs);
  }

  CloudLlmConfig _normalizeConfig(CloudLlmConfig config) {
    if (_openRouterRecommendedModelIds.isEmpty) return config;
    return config;
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
    final value = prefs.getString(_assistantProviderPrefKey);
    if (value == null || value == 'local') {
      await prefs.setString(_assistantProviderPrefKey, 'cloud');
      return 'cloud';
    }
    return value;
  }

  /// Set the assistant provider type.
  Future<void> saveAssistantProviderType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_assistantProviderPrefKey, type);
  }

  Future<VoiceSettings> loadVoiceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_voiceSettingsPrefKey);
    if (raw == null || raw.isEmpty) return const VoiceSettings();
    try {
      final settings = VoiceSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      if (!settings.useCloudAsr) {
        final migrated = settings.copyWith(
          useCloudAsr: true,
          useChatModelForCloudAsr: true,
        );
        await saveVoiceSettings(migrated);
        return migrated;
      }
      return settings;
    } catch (_) {
      return const VoiceSettings();
    }
  }

  Future<void> saveVoiceSettings(VoiceSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_voiceSettingsPrefKey, jsonEncode(settings.toJson()));
  }
}

@JsonSerializable()
class VoiceSettings {
  const VoiceSettings({
    this.useCloudAsr = true,
    this.convertWavToMp3 = false,
    this.useChatModelForCloudAsr = true,
    this.cloudAsrConfigId,
    this.cloudAsrModel,
  });
  final bool useCloudAsr;
  final bool convertWavToMp3;
  final bool useChatModelForCloudAsr;
  final String? cloudAsrConfigId;
  final String? cloudAsrModel;

  VoiceSettings copyWith({
    bool? useCloudAsr,
    bool? convertWavToMp3,
    bool? useChatModelForCloudAsr,
    Object? cloudAsrConfigId = _voiceSentinel,
    Object? cloudAsrModel = _voiceSentinel,
  }) => VoiceSettings(
    useCloudAsr: useCloudAsr ?? this.useCloudAsr,
    convertWavToMp3: convertWavToMp3 ?? this.convertWavToMp3,
    useChatModelForCloudAsr:
        useChatModelForCloudAsr ?? this.useChatModelForCloudAsr,
    cloudAsrConfigId:
        cloudAsrConfigId == _voiceSentinel
            ? this.cloudAsrConfigId
            : cloudAsrConfigId as String?,
    cloudAsrModel:
        cloudAsrModel == _voiceSentinel
            ? this.cloudAsrModel
            : cloudAsrModel as String?,
  );

  Map<String, dynamic> toJson() => _$VoiceSettingsToJson(this);

  factory VoiceSettings.fromJson(Map<String, dynamic> json) =>
      _$VoiceSettingsFromJson(json);
}

const _voiceSentinel = Object();
