import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/assistant/assistant_message_utils.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardPanelInstance _panel(String id, String title, {int zIndex = 0}) {
  return BoardPanelInstance(
    id: id,
    type: 'board.note.markdown',
    title: title,
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
    zIndex: zIndex,
  );
}

void main() {
  group('resolveOutgoingMessageContent', () {
    test('audio content uses the mic placeholder for both texts', () {
      final result = resolveOutgoingMessageContent(
        rawText: '',
        hasAudioContent: true,
        mirrorToOverlay: false,
      );
      expect(result.text, '🎤 Voice message');
      expect(result.displayContent, '🎤 Voice message');
    });

    test('mirrorToOverlay prepends the ASR transcription prefix', () {
      final result = resolveOutgoingMessageContent(
        rawText: 'hello board',
        hasAudioContent: false,
        mirrorToOverlay: true,
      );
      expect(
        result.text,
        '[Voice message — transcribed via speech recognition, '
        'may contain recognition errors]\nhello board',
      );
      expect(result.displayContent, result.text);
    });

    test('plain text send keeps the raw text', () {
      final result = resolveOutgoingMessageContent(
        rawText: 'just text',
        hasAudioContent: false,
        mirrorToOverlay: false,
      );
      expect(result.text, 'just text');
      expect(result.displayContent, 'just text');
    });
  });

  group('upsertOverlayToolLogEntry', () {
    test('replaces the last running entry in place', () {
      final logs = ['✅ panels', '⏳ running: note', '⏳ running: panel:create'];
      upsertOverlayToolLogEntry(logs, '✅ panel:create');
      expect(logs, ['✅ panels', '⏳ running: note', '✅ panel:create']);
    });

    test('appends when no running entry exists', () {
      final logs = ['✅ panels'];
      upsertOverlayToolLogEntry(logs, '❌ note');
      expect(logs, ['✅ panels', '❌ note']);
    });
  });

  group('recordPendingToolStarts', () {
    test('stores the start under name, call id and cli command', () {
      final pending = <String, String>{};
      recordPendingToolStarts(
        pending,
        toolName: 'yoloit_note',
        toolCallId: 'call-1',
        cliCommand: 'note',
      );
      expect(pending.keys, containsAll(['yoloit_note', 'call-1', 'note']));
      expect(pending['yoloit_note'], isNotEmpty);
      // Same timestamp for all keys.
      expect(pending['yoloit_note'], pending['call-1']);
      expect(pending['call-1'], pending['note']);
    });

    test('skips the cli command key when null', () {
      final pending = <String, String>{};
      recordPendingToolStarts(
        pending,
        toolName: 'custom_tool',
        toolCallId: 'call-2',
        cliCommand: null,
      );
      expect(pending.keys, unorderedEquals(['custom_tool', 'call-2']));
    });
  });

  group('cloudModelDebugInfo', () {
    test('maps config fields to debug keys', () {
      expect(
        cloudModelDebugInfo(
          model: 'gpt-x',
          providerName: 'openrouter',
          baseUrl: 'https://example.test/v1',
        ),
        {
          'modelId': 'gpt-x',
          'modelProvider': 'openrouter',
          'modelBaseUrl': 'https://example.test/v1',
        },
      );
    });
  });

  group('computeAssistantOverlayStatus', () {
    test('forced status wins over everything', () {
      expect(
        computeAssistantOverlayStatus(
          forcedStatus: 'output',
          isRecordingMic: true,
          isTranscribingMic: true,
          isGeneratingReply: true,
          receivedAssistantToken: true,
          draft: 'x',
        ),
        'output',
      );
    });

    test('recording has the highest derived priority', () {
      expect(
        computeAssistantOverlayStatus(
          isRecordingMic: true,
          isTranscribingMic: true,
          isGeneratingReply: true,
          receivedAssistantToken: false,
          draft: 'x',
        ),
        'listening',
      );
    });

    test('transcribing beats generating', () {
      expect(
        computeAssistantOverlayStatus(
          isRecordingMic: false,
          isTranscribingMic: true,
          isGeneratingReply: true,
          receivedAssistantToken: false,
          draft: '',
        ),
        'processing',
      );
    });

    test('generating depends on whether a token was received', () {
      expect(
        computeAssistantOverlayStatus(
          isRecordingMic: false,
          isTranscribingMic: false,
          isGeneratingReply: true,
          receivedAssistantToken: true,
          draft: '',
        ),
        'responding',
      );
      expect(
        computeAssistantOverlayStatus(
          isRecordingMic: false,
          isTranscribingMic: false,
          isGeneratingReply: true,
          receivedAssistantToken: false,
          draft: '',
        ),
        'thinking',
      );
    });

    test('non-empty draft is ready, otherwise idle', () {
      expect(
        computeAssistantOverlayStatus(
          isRecordingMic: false,
          isTranscribingMic: false,
          isGeneratingReply: false,
          receivedAssistantToken: false,
          draft: 'typed',
        ),
        'ready',
      );
      expect(
        computeAssistantOverlayStatus(
          isRecordingMic: false,
          isTranscribingMic: false,
          isGeneratingReply: false,
          receivedAssistantToken: false,
          draft: '',
        ),
        'idle',
      );
    });
  });

  group('assistantDisplayContent', () {
    test('strips the voice prefix from user messages', () {
      expect(
        assistantDisplayContent(
          isUser: true,
          content: '[Voice message — transcribed]\nshow me panels',
        ),
        'show me panels',
      );
    });

    test('keeps assistant and plain user content untouched', () {
      expect(
        assistantDisplayContent(
          isUser: false,
          content: '[Voice message — transcribed]\nanswer',
        ),
        '[Voice message — transcribed]\nanswer',
      );
      expect(
        assistantDisplayContent(isUser: true, content: 'plain question'),
        'plain question',
      );
    });
  });

  group('deriveAssistantSessionName', () {
    test('uses the first user message, flattened to one line', () {
      expect(
        deriveAssistantSessionName([
          {'role': 'assistant', 'content': 'ignored'},
          {'role': 'user', 'content': '  first line\nsecond line  '},
        ]),
        'first line second line',
      );
    });

    test('truncates names longer than 60 chars', () {
      final long = 'a' * 70;
      final name = deriveAssistantSessionName([
        {'role': 'user', 'content': long},
      ]);
      expect(name, 'a' * 60);
    });

    test('falls back to a default when there is no user text', () {
      expect(
        deriveAssistantSessionName([
          {'role': 'assistant', 'content': 'hi'},
        ]),
        'Yolo session',
      );
      expect(
        deriveAssistantSessionName([
          {'role': 'user', 'content': '   '},
        ]),
        'Yolo session',
      );
    });
  });

  group('availableBoardsSummary', () {
    test('marks the current board and lists one line per board', () {
      final boards = [
        const BoardDocument(id: 'b1', name: 'Alpha'),
        const BoardDocument(id: 'b2', name: 'Beta'),
      ];
      expect(
        availableBoardsSummary(boards, 'b2'),
        '- Alpha [b1]\n- Beta [b2] (current)',
      );
    });

    test('no marker when there is no current board', () {
      final boards = [const BoardDocument(id: 'b1', name: 'Alpha')];
      expect(availableBoardsSummary(boards, null), '- Alpha [b1]');
    });
  });

  group('boardPanelsSummary', () {
    test('returns empty string without a board', () {
      expect(boardPanelsSummary(null), '');
    });

    test('sorts panels by descending z-index', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Alpha',
        panels: [
          _panel('p1', 'Low', zIndex: 1),
          _panel('p2', 'High', zIndex: 9),
          _panel('p3', 'Mid', zIndex: 5),
        ],
      );
      expect(
        boardPanelsSummary(board),
        '- High [board.note.markdown] (p2)\n'
        '- Mid [board.note.markdown] (p3)\n'
        '- Low [board.note.markdown] (p1)',
      );
    });
  });

  group('estimateTokenCount', () {
    test('empty or blank text is zero tokens', () {
      expect(estimateTokenCount(''), 0);
      expect(estimateTokenCount('   '), 0);
    });

    test('estimates roughly 4 chars per token, rounding up', () {
      expect(estimateTokenCount('abcd'), 1);
      expect(estimateTokenCount('abcde'), 2);
      expect(estimateTokenCount('  abcdefgh  '), 2);
    });
  });

  group('formatAssistantError', () {
    test('explains the local runtime mismatch', () {
      final message = formatAssistantError(
        Exception('missing symbol flm_dispatch_json in runtime'),
      );
      expect(message, contains('Local model runtime mismatch'));
      expect(message, contains('flm_dispatch_json'));
    });

    test('wraps generic errors with an Error prefix', () {
      expect(formatAssistantError(StateError('boom')), contains('Error:'));
      expect(formatAssistantError('plain failure'), 'Error: plain failure');
    });
  });

  group('resolveAsrMode', () {
    test('local when cloud ASR is disabled', () {
      expect(
        resolveAsrMode(useCloudAsr: false, useChatModelForCloudAsr: false),
        'local',
      );
      expect(
        resolveAsrMode(useCloudAsr: false, useChatModelForCloudAsr: true),
        'local',
      );
    });

    test('direct_audio when cloud ASR uses the chat model', () {
      expect(
        resolveAsrMode(useCloudAsr: true, useChatModelForCloudAsr: true),
        'direct_audio',
      );
    });

    test('cloud otherwise', () {
      expect(
        resolveAsrMode(useCloudAsr: true, useChatModelForCloudAsr: false),
        'cloud',
      );
    });
  });

  group('mergeTranscriptIntoInput', () {
    test('uses the transcript alone when the field is empty', () {
      expect(mergeTranscriptIntoInput('   ', 'hello'), 'hello');
    });

    test('appends the transcript after the current text', () {
      expect(mergeTranscriptIntoInput('draft', '  hello  '), 'draft hello');
    });
  });

  group('buildAsrDebugInfo', () {
    test('includes only the set optional fields', () {
      final info = buildAsrDebugInfo(
        mode: 'cloud',
        status: 'ok',
        startedAt: 't0',
        completedAt: 't1',
        durationMs: 42,
        transcriptChars: 7,
        resolvedModel: 'chirp-3',
      );
      expect(info['mode'], 'cloud');
      expect(info['durationMs'], 42);
      expect(info['model'], 'chirp-3');
      expect(info.containsKey('provider'), isFalse);
      expect(info.containsKey('error'), isFalse);
    });

    test('records provider and error when present', () {
      final info = buildAsrDebugInfo(
        mode: 'local',
        status: 'error',
        startedAt: 't0',
        completedAt: 't1',
        durationMs: 5,
        transcriptChars: 0,
        providerName: 'mlx',
        error: 'boom',
      );
      expect(info['provider'], 'mlx');
      expect(info['error'], 'boom');
    });
  });

  group('buildAsrSampleMetadata', () {
    test('builds the full metadata payload', () {
      final meta = buildAsrSampleMetadata(
        recordedAt: 't0',
        completedAt: 't1',
        durationMs: 10,
        asrMode: 'direct_audio',
        asrStatus: 'ok',
        resolvedModel: 'gpt-audio',
        providerName: 'openrouter',
        transcript: 'some words',
        transcriptChars: 10,
      );
      expect(meta, {
        'recordedAt': 't0',
        'completedAt': 't1',
        'durationMs': 10,
        'asrMode': 'direct_audio',
        'asrStatus': 'ok',
        'asrModel': 'gpt-audio',
        'asrProvider': 'openrouter',
        'transcript': 'some words',
        'transcriptChars': 10,
      });
    });

    test('omits optional keys and keeps error when set', () {
      final meta = buildAsrSampleMetadata(
        recordedAt: 't0',
        completedAt: 't1',
        durationMs: 3,
        asrMode: 'local',
        asrStatus: 'error',
        transcript: '',
        transcriptChars: 0,
        error: 'asr failed',
      );
      expect(meta.containsKey('asrModel'), isFalse);
      expect(meta.containsKey('asrProvider'), isFalse);
      expect(meta['error'], 'asr failed');
    });
  });

  group('buildWavFromPcm', () {
    test('writes a valid 44-byte RIFF/WAVE header around the PCM data', () {
      final pcm = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final wav = buildWavFromPcm(pcm);
      expect(wav.length, 44 + pcm.length);
      // RIFF/WAVE magic.
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');

      final header = ByteData.sublistView(wav, 0, 44);
      expect(header.getUint32(4, Endian.little), 36 + pcm.length);
      expect(header.getUint32(16, Endian.little), 16);
      expect(header.getUint16(20, Endian.little), 1); // PCM
      expect(header.getUint16(22, Endian.little), 1); // mono
      expect(header.getUint32(24, Endian.little), 16000);
      expect(header.getUint32(28, Endian.little), 32000); // byte rate
      expect(header.getUint16(32, Endian.little), 2); // block align
      expect(header.getUint16(34, Endian.little), 16); // bits per sample
      expect(header.getUint32(40, Endian.little), pcm.length);
      // PCM payload copied verbatim.
      expect(wav.sublist(44), pcm);
    });

    test('handles empty PCM input', () {
      final wav = buildWavFromPcm(Uint8List(0));
      expect(wav.length, 44);
      expect(ByteData.sublistView(wav).getUint32(40, Endian.little), 0);
    });
  });
}
