import 'package:yoloit/features/board/audio_recorder/transcription_service.dart';

/// Web builds have no FFI-based local MLX engine. This is only invoked when a
/// local-mode transcription is actually requested — the recorder panel itself
/// is desktop-only, so in practice it is never reached on web.
LocalTranscriber createDefaultLocalTranscriber() =>
    throw UnsupportedError(
      'Local ASR is not supported on this platform. Enable cloud ASR instead.',
    );
