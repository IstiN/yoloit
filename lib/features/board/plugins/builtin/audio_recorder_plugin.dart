import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

import 'package:yoloit/features/board/plugins/builtin/audio_recorder_content_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/plugins/builtin/audio_recorder_content_stub.dart' as content;

final _audioRecorderDefaultColors = AppColorScheme.fromAccent(Colors.redAccent);

/// Persistent configuration for the audio recorder panel.
///
/// Stored under `panel.state['config']` so it survives board reloads and is
/// editable both from the panel UI and from the CLI.
class AudioRecorderConfig {
  const AudioRecorderConfig({
    this.saveFolder = '',
    this.captureSystemAudio = true,
    this.captureMicrophone = true,
    this.format = 'wav',
  });

  /// Key under which the config is nested inside the panel state map.
  static const String configKey = 'config';

  /// Absolute path to the folder where recordings are written. Empty means
  /// "use the board default folder".
  final String saveFolder;

  /// Whether to capture the system/output (loopback) audio — i.e. what plays
  /// through the speakers or headphones during a call.
  final bool captureSystemAudio;

  /// Whether to capture the microphone input alongside the system audio.
  final bool captureMicrophone;

  /// Output container/codec. Only `wav` is supported by the current engine;
  /// `mp3` is reserved for a follow-up slice.
  final String format;

  factory AudioRecorderConfig.fromState(Map<String, dynamic> state) {
    final raw = state[configKey];
    if (raw is Map) {
      return AudioRecorderConfig.fromJson(Map<String, dynamic>.from(raw));
    }
    return const AudioRecorderConfig();
  }

  factory AudioRecorderConfig.fromJson(Map<String, dynamic> json) =>
      AudioRecorderConfig(
        saveFolder: json['saveFolder'] as String? ?? '',
        captureSystemAudio: json['captureSystemAudio'] as bool? ?? true,
        captureMicrophone: json['captureMicrophone'] as bool? ?? true,
        format: json['format'] as String? ?? 'wav',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'saveFolder': saveFolder,
    'captureSystemAudio': captureSystemAudio,
    'captureMicrophone': captureMicrophone,
    'format': format,
  };

  AudioRecorderConfig copyWith({
    String? saveFolder,
    bool? captureSystemAudio,
    bool? captureMicrophone,
    String? format,
  }) => AudioRecorderConfig(
    saveFolder: saveFolder ?? this.saveFolder,
    captureSystemAudio: captureSystemAudio ?? this.captureSystemAudio,
    captureMicrophone: captureMicrophone ?? this.captureMicrophone,
    format: format ?? this.format,
  );
}

/// Built-in panel that records system (loopback) audio and the microphone into
/// a single file and lists the captured recordings for playback.
class AudioRecorderPlugin extends BoardPanelPlugin {
  const AudioRecorderPlugin();

  // Keep a literal string here so `scripts/check_panel_write_coverage.py`
  // discovers the type id (it scans `builtin/*_plugin.dart` for `kTypeId`).
  static const String kTypeId = 'board.audio_recorder';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Audio Recorder';

  @override
  IconData get icon => Icons.mic_rounded;

  @override
  Color get accentColor => _audioRecorderDefaultColors.accentRed;

  @override
  Size get defaultSize => const Size(380, 460);

  @override
  Map<String, dynamic> get initialState => <String, dynamic>{
    AudioRecorderConfig.configKey: const AudioRecorderConfig().toJson(),
    'isRecording': false,
    'recordings': <Map<String, dynamic>>[],
  };

  /// Capture needs the local filesystem (to write files) and native media
  /// playback (to audition recordings via media_kit). The registry hides the
  /// panel from the catalog on runtimes that lack either.
  @override
  Set<PlatformCapability> get requiredCapabilities => const {
    PlatformCapability.filesystem,
    PlatformCapability.nativeMediaPlayback,
  };

  /// The recording UI touches native audio APIs; offscreen previews render the
  /// generic placeholder instead.
  @override
  bool get supportsHeadlessRender => false;

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) => content.buildAudioRecorderContent(panel, renderContext);
}
