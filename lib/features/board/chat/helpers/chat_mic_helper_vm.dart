import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:yoloit/core/platform/microphone_permission_service.dart';
import 'package:yoloit/features/board/chat/cloud_asr_service.dart';
import 'package:yoloit/features/board/chat/helpers/chat_mic_helper_base.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/features/settings/ui/settings_page.dart';

class ChatMicHandlerImpl implements ChatMicHandler {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  bool get isAvailable => true;

  @override
  Future<void> start(
    BuildContext context, {
    required ChatSessionConfig config,
    required void Function({required bool recording, required bool transcribing})
    updateState,
    required Future<void> Function(String title, String message) showError,
  }) async {
    final effectiveAsr = AgentConfigService.instance.effectiveAsr(
      config.provider,
    );
    final useCloudAsr =
        effectiveAsr.mode == 'cloud' &&
        effectiveAsr.configId != null &&
        effectiveAsr.configId!.isNotEmpty;
    if (!useCloudAsr) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Configure a cloud ASR provider in Settings → AI Models.',
            ),
            duration: Duration(seconds: 2),
          ),
        );
        await SettingsPage.show(context, initialCategory: 'AI Models');
      }
      return;
    }

    final nativeGranted =
        await MicrophonePermissionService.instance.ensureGranted();
    if (!nativeGranted) {
      if (context.mounted) {
        await showError(
          'Microphone access required',
          'YoLoIT needs microphone access to record audio for local ASR.',
        );
      }
      return;
    }

    final granted = await _recorder.hasPermission();
    if (!granted) {
      if (context.mounted) {
        await showError(
          'Microphone access required',
          'YoLoIT needs microphone access to record audio for local ASR.',
        );
      }
      return;
    }

    final outputPath =
        '${Directory.systemTemp.path}/yoloit_asr_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: outputPath,
      );
    } on Exception catch (e) {
      final stillNoPermission = !await _recorder.hasPermission();
      if (stillNoPermission) {
        if (context.mounted) {
          await showError(
            'Microphone access required',
            'YoLoIT needs microphone access to record audio for local ASR.',
          );
        }
        return;
      }
      if (context.mounted) {
        await showError(
          'Microphone error',
          'Failed to start microphone:\n$e',
        );
      }
      return;
    }
    updateState(recording: true, transcribing: false);
  }

  @override
  Future<void> stop({
    required ChatSessionConfig config,
    required void Function(String transcript) onTranscript,
    required VoidCallback onFinished,
  }) async {
    final path = await _recorder.stop();

    try {
      if (path == null || path.isEmpty) return;

      final effectiveAsr = AgentConfigService.instance.effectiveAsr(
        config.provider,
      );
      final useCloud =
          effectiveAsr.mode == 'cloud' &&
          effectiveAsr.configId != null &&
          effectiveAsr.configId!.isNotEmpty;

      var transcript = '';
      if (useCloud) {
        final cloudCfg = await CloudLlmSettingsService.instance.loadConfigById(
          effectiveAsr.configId!,
        );
        if (cloudCfg == null) {
          throw StateError(
            'Cloud ASR provider "${effectiveAsr.configId}" not found. '
            'Please check your AI Agents settings.',
          );
        }
        final voiceSettings = VoiceSettings(
          useCloudAsr: true,
          useChatModelForCloudAsr: false,
          cloudAsrConfigId: cloudCfg.id,
          cloudAsrModel:
              effectiveAsr.model?.trim().isNotEmpty == true
                  ? effectiveAsr.model
                  : cloudCfg.model.trim().isNotEmpty
                  ? cloudCfg.model
                  : 'whisper-1',
        );
        transcript = await CloudAsrService().transcribeFromFile(
          audioPath: path,
          voiceSettings: voiceSettings,
        );
      }

      final text = transcript.trim();
      if (text.isNotEmpty) {
        onTranscript(text);
      }
    } catch (e) {
      assert(() {
        debugPrint('[ChatMicHandler] stop error: $e');
        return true;
      }());
    } finally {
      if (path != null && path.isNotEmpty) {
        final f = File(path);
        if (f.existsSync()) {
          try {
            await f.delete();
          } on FileSystemException {
            // ignore cleanup failure for temp recording
          }
        }
      }
      onFinished();
    }
  }

  @override
  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
