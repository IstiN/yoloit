import 'package:yoloit/features/board/chat/cloud_asr_service.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';

/// Result of a transcription run.
///
/// [modeUsed] is either `'cloud'` or `'local'`, mirroring the
/// `voiceSettings.useCloudAsr` rule used by the assistant voice pipeline.
class TranscriptResult {
  const TranscriptResult({required this.text, required this.modeUsed});

  /// Trimmed transcript text.
  final String text;

  /// The ASR backend that produced the transcript: `'cloud'` or `'local'`.
  final String modeUsed;
}

/// Narrow seam for the cloud ASR collaborator.
///
/// Defined here (and implemented by [CloudAsrService]) so tests can inject a
/// lightweight fake that only provides the method the transcription pipeline
/// actually calls.
abstract class CloudTranscriber {
  Future<String> transcribeFromFile({
    required String audioPath,
    required VoiceSettings voiceSettings,
  });
}

/// Narrow seam for the local (MLX) ASR collaborator.
abstract class LocalTranscriber {
  Future<String> transcribeWithSelectedAsr(
    String audioPath, {
    String? language,
  });
}

/// Narrow seam for reading the user's voice settings.
abstract class VoiceSettingsProvider {
  Future<VoiceSettings> loadVoiceSettings();
}

/// Routes an audio file to the configured ASR backend (cloud or local) and
/// returns the trimmed transcript.
///
/// The service reuses the repo's existing ASR engines — it does not implement
/// any recognition itself. Backend selection mirrors
/// `lib/features/board/assistant/yolo_assistant_widget.dart`: cloud when
/// `voiceSettings.useCloudAsr == true`, otherwise local.
class TranscriptionService {
  TranscriptionService({
    CloudTranscriber? cloud,
    LocalTranscriber? local,
    VoiceSettingsProvider? settings,
  }) : _cloud = cloud ?? CloudAsrService(),
       _local = local ?? LocalAiModelsService.instance,
       _settings = settings ?? CloudLlmSettingsService.instance;

  /// Shared singleton used by production callers (CLI handler, etc.).
  static final TranscriptionService instance = TranscriptionService();

  /// Test-only override. When non-null, [current] returns it instead of the
  /// production singleton so widget tests can inject a fake backend.
  static TranscriptionService? _debugInstance;

  /// The service production callers should use. Returns the test override when
  /// one is installed via [debugSetInstance], otherwise the production
  /// [instance].
  static TranscriptionService get current => _debugInstance ?? instance;

  /// Installs (or clears, when null) a test override for [current].
  static void debugSetInstance(TranscriptionService? service) {
    _debugInstance = service;
  }

  /// Isolated instance for unit tests (no shared singleton state).
  factory TranscriptionService.testInstance({
    CloudTranscriber? cloud,
    LocalTranscriber? local,
    VoiceSettingsProvider? settings,
  }) => TranscriptionService(cloud: cloud, local: local, settings: settings);

  final CloudTranscriber _cloud;
  final LocalTranscriber _local;
  final VoiceSettingsProvider _settings;

  /// Transcribes [audioPath].
  ///
  /// When [mode] is `'cloud'` the cloud backend is used; when it is `'local'`
  /// the local MLX backend is used. When [mode] is omitted the backend is
  /// resolved from voice settings (`useCloudAsr`). [language] is forwarded to
  /// the local backend only.
  ///
  /// Exceptions from the underlying backend propagate unchanged so callers can
  /// map them to user-facing errors.
  Future<TranscriptResult> transcribeFile(
    String audioPath, {
    String? mode,
    String? language,
  }) async {
    final resolved = mode ?? await _resolveMode();
    if (resolved == 'cloud') {
      final vs = await _settings.loadVoiceSettings();
      final text = (await _cloud.transcribeFromFile(
        audioPath: audioPath,
        voiceSettings: vs,
      )).trim();
      return TranscriptResult(text: text, modeUsed: 'cloud');
    }
    final text = (await _local.transcribeWithSelectedAsr(
      audioPath,
      language: language,
    )).trim();
    return TranscriptResult(text: text, modeUsed: 'local');
  }

  Future<String> _resolveMode() async {
    final vs = await _settings.loadVoiceSettings();
    return vs.useCloudAsr ? 'cloud' : 'local';
  }
}
