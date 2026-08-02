part of 'yolo_assistant_widget.dart';

/// Mutable per-recording state shared by the
/// [_YoloAssistantWidgetState._stopRecordingAndTranscribe] phase helpers.
class _AsrTranscriptionRun {
  _AsrTranscriptionRun({
    required this.mode,
    required this.startedAt,
    this.resolvedModel,
    this.providerName,
  });

  final String mode;
  final String startedAt;
  final Stopwatch stopwatch = Stopwatch()..start();
  String? resolvedModel;
  String? providerName;
  String? tempPath;
  String status = 'ok';
  int transcriptChars = 0;
  String? error;
  bool shouldSend = false;
}

/// Phase helpers for [_YoloAssistantWidgetState._stopRecordingAndTranscribe].
///
/// Kept in a separate part file to satisfy the repository per-file line
/// limit. An extension in the same library has full access to the private
/// members of [_YoloAssistantWidgetState], and its methods are callable like
/// instance methods from within the class. Each phase was extracted verbatim
/// from the original method body.
extension _AssistantVoicePhases on _YoloAssistantWidgetState {
  /// Stops the mic capture and returns the buffered audio as WAV bytes
  /// (or `null` when nothing was recorded).
  Future<Uint8List?> _stopMicCaptureAndBuildWav() async {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    // Stop stream recording and collect buffered PCM bytes.
    await _micRecorder.stop();
    await _micStreamSub?.cancel();
    _micStreamSub = null;
    final pcmBytes = _micStreamBytes?.takeBytes();
    _micStreamBytes = null;

    // Build WAV from raw PCM (16-bit mono 16 kHz).
    return pcmBytes != null && pcmBytes.isNotEmpty
        ? _YoloAssistantWidgetState._buildWavFromPcm(pcmBytes)
        : null;
  }

  /// Computes the ASR mode and resolves the effective ASR model/provider
  /// for debug display, then opens a new transcription run.
  Future<_AsrTranscriptionRun> _beginAsrRun(
    VoiceSettings voiceSettings,
  ) async {
    final asrMode =
        !voiceSettings.useCloudAsr
            ? 'local'
            : voiceSettings.useChatModelForCloudAsr
            ? 'direct_audio'
            : 'cloud';
    // Resolve the effective ASR model for debug display (mirrors CloudAsrService logic).
    String? asrResolvedModel;
    String? asrProviderName;
    if (voiceSettings.useCloudAsr) {
      if (!voiceSettings.useChatModelForCloudAsr &&
          voiceSettings.cloudAsrModel?.trim().isNotEmpty == true) {
        asrResolvedModel = voiceSettings.cloudAsrModel!.trim();
      }
      // Load config to get provider name + fallback model.
      final explicitId =
          voiceSettings.useChatModelForCloudAsr
              ? null
              : voiceSettings.cloudAsrConfigId?.trim();
      final asrCfg =
          (explicitId != null && explicitId.isNotEmpty
              ? await CloudLlmSettingsService.instance.loadConfigById(
                explicitId,
              )
              : null) ??
          await CloudLlmSettingsService.instance.loadActiveConfig();
      asrResolvedModel ??= asrCfg?.model.trim();
      asrProviderName = asrCfg?.name;
    }
    return _AsrTranscriptionRun(
      mode: asrMode,
      startedAt: DateTime.now().toIso8601String(),
      resolvedModel: asrResolvedModel,
      providerName: asrProviderName,
    );
  }

  /// Runs the ASR dispatch (direct audio / cloud / local), recording the
  /// outcome on [run]. Errors are shown in a dialog, never rethrown.
  Future<void> _runAsrTranscription(
    Uint8List? wavBytes,
    VoiceSettings voiceSettings,
    bool sendAfterTranscription,
    _AsrTranscriptionRun run,
  ) async {
    try {
      if (wavBytes == null || wavBytes.isEmpty) {
        run.status = 'no_audio';
        return;
      }

      if (voiceSettings.useCloudAsr && voiceSettings.useChatModelForCloudAsr) {
        await _transcribeViaDirectAudio(
          wavBytes,
          voiceSettings,
          sendAfterTranscription,
          run,
        );
      } else if (voiceSettings.useCloudAsr) {
        await _transcribeViaCloudAsr(
          wavBytes,
          voiceSettings,
          sendAfterTranscription,
          run,
        );
      } else {
        await _transcribeViaLocalAsr(
          wavBytes,
          tempPath: run.tempPath,
          sendAfterTranscription: sendAfterTranscription,
          run: run,
        );
      }
    } catch (e) {
      run.status = 'error';
      run.error = '$e';
      if (!mounted) return;
      await _showCopyableErrorDialog(
        title: 'ASR error',
        message: 'ASR failed:\n$e',
      );
    }
  }

  /// ── Direct audio → chat model: attach audio as message content ──────────
  Future<void> _transcribeViaDirectAudio(
    Uint8List wavBytes,
    VoiceSettings voiceSettings,
    bool sendAfterTranscription,
    _AsrTranscriptionRun run,
  ) async {
    // Optionally convert WAV → MP3 to reduce payload size.
    var audioBytes = wavBytes;
    var audioFormat = 'wav';
    int? conversionMs;
    if (voiceSettings.convertWavToMp3) {
      try {
        final convSw = Stopwatch()..start();
        final tmpWav =
            '${Directory.systemTemp.path}/yoloit_direct_${DateTime.now().millisecondsSinceEpoch}.wav';
        final tmpMp3 = tmpWav.replaceAll('.wav', '.mp3');
        await File(tmpWav).writeAsBytes(wavBytes, flush: true);
        final result = await Process.run('ffmpeg', [
          '-i',
          tmpWav,
          '-codec:a',
          'libmp3lame',
          '-qscale:a',
          '4',
          '-y',
          tmpMp3,
        ]);
        convSw.stop();
        conversionMs = convSw.elapsedMilliseconds;
        if (result.exitCode == 0 && File(tmpMp3).existsSync()) {
          audioBytes = await File(tmpMp3).readAsBytes();
          audioFormat = 'mp3';
        }
        // Clean up temp files
        try {
          File(tmpWav).deleteSync();
        } catch (_) {}
        try {
          File(tmpMp3).deleteSync();
        } catch (_) {}
      } on ProcessException {
        // ffmpeg not available — fall back to WAV
      }
    }
    _pendingAudioContent = [
      {
        'type': 'input_audio',
        'input_audio': {
          'data': base64Encode(audioBytes),
          'format': audioFormat,
        },
      },
    ];
    if (conversionMs != null) {
      _pendingAsrConversionMs = conversionMs;
    }
    if (!mounted) return;
    _syncOverlayState(hiddenOverride: _voiceOverlayHidden);
    run.shouldSend = sendAfterTranscription;
    run.status = 'ok';
    run.transcriptChars = -1; // sentinel: audio sent directly
  }

  /// ── Cloud ASR: transcribe with ASR model, then put text in field ────────
  Future<void> _transcribeViaCloudAsr(
    Uint8List wavBytes,
    VoiceSettings voiceSettings,
    bool sendAfterTranscription,
    _AsrTranscriptionRun run,
  ) async {
    final transcript = await _cloudAsrService.transcribeFromBytes(
      audioBytes: wavBytes,
      voiceSettings: voiceSettings,
    );
    _appendTranscriptToInput(transcript, sendAfterTranscription, run);
  }

  /// ── Local ASR: needs a file on disk — write WAV once ────────────────────
  Future<void> _transcribeViaLocalAsr(
    Uint8List wavBytes, {
    required String? tempPath,
    required bool sendAfterTranscription,
    required _AsrTranscriptionRun run,
  }) async {
    if (tempPath != null) {
      await File(tempPath).writeAsBytes(wavBytes, flush: true);
    }
    final transcript = await LocalAiModelsService.instance
        .transcribeWithSelectedAsr(tempPath ?? '');
    _appendTranscriptToInput(transcript, sendAfterTranscription, run);
  }

  /// Appends the transcript to the input field and marks the run as ready
  /// to send when the transcript is non-empty.
  void _appendTranscriptToInput(
    String transcript,
    bool sendAfterTranscription,
    _AsrTranscriptionRun run,
  ) {
    if (!mounted) return;
    final text = transcript.trim();
    run.transcriptChars = text.length;
    if (text.isNotEmpty) {
      final current = _inputController.text.trim();
      _inputController.text =
          current.isEmpty ? text : '$current ${text.trim()}';
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
      _syncOverlayState(hiddenOverride: _voiceOverlayHidden);
      run.shouldSend = sendAfterTranscription;
    }
  }

  /// Records ASR debug info, saves the sample for benchmarking, deletes the
  /// temp file and resets the transcribing UI state.
  Future<void> _finalizeAsrRun(
    _AsrTranscriptionRun run,
    Uint8List? wavBytes,
  ) async {
    run.stopwatch.stop();
    final completedAt = DateTime.now().toIso8601String();
    _pendingAsrDebug = {
      'mode': run.mode,
      'status': run.status,
      'startedAt': run.startedAt,
      'completedAt': completedAt,
      'durationMs': run.stopwatch.elapsedMilliseconds,
      'transcriptChars': run.transcriptChars,
      if (run.resolvedModel != null) 'model': run.resolvedModel,
      if (run.providerName != null) 'provider': run.providerName,
      if (run.error != null) 'error': run.error,
    };
    // Save a persistent copy for ASR benchmarking.
    if (wavBytes != null && wavBytes.isNotEmpty) {
      try {
        await _saveAsrSample(run, wavBytes, completedAt);
      } on Exception {
        // Best-effort — never block the main flow.
      }
    }
    // Delete the temp file used for local ASR (if written).
    final tempPath = run.tempPath;
    if (tempPath != null) {
      try {
        final f = File(tempPath);
        if (f.existsSync()) await f.delete();
      } on FileSystemException {
        // ignore
      }
    }
    if (mounted) {
      setState(() => _isTranscribingMic = false);
      // If we are about to send the message, keep the overlay in 'processing'
      // to avoid a visual bounce: processing → idle → processing.
      _syncOverlayState(
        forcedStatus: run.shouldSend ? 'processing' : null,
        hiddenOverride: _voiceOverlayHidden,
      );
    }
  }

  /// Persists the recorded WAV plus a companion metadata JSON — useful for
  /// replay benchmarks.
  Future<void> _saveAsrSample(
    _AsrTranscriptionRun run,
    Uint8List wavBytes,
    String completedAt,
  ) async {
    final samplesDir = Directory(
      '${PlatformDirs.instance.dataDir}/asr_samples',
    );
    if (!samplesDir.existsSync()) {
      samplesDir.createSync(recursive: true);
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final sampleWav = '${samplesDir.path}/$ts.wav';
    // Reuse already-written temp file if available, otherwise write from bytes.
    final tempPath = run.tempPath;
    if (tempPath != null && File(tempPath).existsSync()) {
      await File(tempPath).copy(sampleWav);
    } else {
      await File(sampleWav).writeAsBytes(wavBytes, flush: true);
    }
    // Companion metadata JSON — useful for replay benchmarks.
    final transcript =
        run.transcriptChars > 0 ? (_inputController.text.trim()) : '';
    final meta = {
      'recordedAt': run.startedAt,
      'completedAt': completedAt,
      'durationMs': run.stopwatch.elapsedMilliseconds,
      'asrMode': run.mode,
      'asrStatus': run.status,
      if (run.resolvedModel != null) 'asrModel': run.resolvedModel,
      if (run.providerName != null) 'asrProvider': run.providerName,
      'transcript': transcript,
      'transcriptChars': run.transcriptChars,
      if (run.error != null) 'error': run.error,
    };
    await File(
      '${samplesDir.path}/$ts.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(meta));
  }

  /// Sends the pending message after a successful transcription when the
  /// caller asked for it and there is content to send.
  Future<void> _maybeSendAfterTranscription(
    _AsrTranscriptionRun run, {
    required bool mirrorToOverlay,
  }) async {
    if (!run.shouldSend || !mounted) return;
    if (_pendingAudioContent == null &&
        _inputController.text.trim().isEmpty) {
      return;
    }
    if (mirrorToOverlay) {
      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (!mounted) return;
    }
    await _sendMessage(mirrorToOverlay: mirrorToOverlay);
  }
}
