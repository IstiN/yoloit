import 'package:yoloit/features/board/audio_recorder/transcription_service.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';

/// dart:io platforms resolve the local transcription backend to the MLX models
/// service. Imported conditionally so web builds never pull in the FFI engine.
LocalTranscriber createDefaultLocalTranscriber() =>
    LocalAiModelsService.instance;
