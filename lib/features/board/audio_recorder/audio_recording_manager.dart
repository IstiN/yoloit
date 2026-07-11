import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:yoloit/features/board/audio_recorder/audio_source.dart';
import 'package:yoloit/features/board/audio_recorder/pcm_wav.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/audio_recorder_plugin.dart';

typedef MicFactory = AudioSource Function();
typedef SinkOpener =
    Future<PcmWavSink> Function(File file, {PcmWavFormat format});
typedef FolderResolver =
    Future<String> Function(AudioRecorderConfig config, String boardId);
typedef Now = DateTime Function();

/// Singleton that owns the lifecycle of audio recordings independently of the
/// panel widget (which may be disposed when the user switches boards).
///
/// It captures the microphone (and, when provided, a system-audio source),
/// mixes the sources into a single 48 kHz / stereo / 16-bit WAV file, and
/// mirrors progress + the resulting recording entry back into the panel state
/// through [BoardCubit], exactly like [TimerManager] does for timers.
///
/// v1 buffers each source in memory and mixes once on [stop]. This keeps the
/// pipeline simple and exact; a chunked streaming mix is a known follow-up for
/// very long (multi-hour) recordings.
class AudioRecordingManager {
  AudioRecordingManager._({
    MicFactory? micFactory,
    SinkOpener? openSink,
    FolderResolver? folderResolver,
    Now? now,
  }) : _micFactory = micFactory ?? (() => RecordMicSource()),
       _openSink = openSink ?? PcmWavSink.create,
       _now = now ?? DateTime.now {
    _resolveFolder = folderResolver ?? _defaultFolderResolver;
  }

  static final AudioRecordingManager instance = AudioRecordingManager._();

  /// Isolated instance for unit tests (no shared singleton state).
  factory AudioRecordingManager.testInstance({
    MicFactory? micFactory,
    SinkOpener? openSink,
    FolderResolver? folderResolver,
    Now? now,
  }) => AudioRecordingManager._(
    micFactory: micFactory,
    openSink: openSink,
    folderResolver: folderResolver,
    now: now,
  );

  final MicFactory _micFactory;
  final SinkOpener _openSink;
  late final FolderResolver _resolveFolder;
  final Now _now;

  BoardCubit? _cubit;
  final Map<String, _Entry> _entries = {};

  void setCubit(BoardCubit cubit) => _cubit = cubit;

  /// Start a recording for [panelId] on [boardId].
  ///
  /// [systemSource] is the system/loopback audio source (Slice 3). When null,
  /// only the microphone is recorded. No-ops if this panel is already
  /// recording.
  Future<void> start({
    required String panelId,
    required String boardId,
    AudioSource? systemSource,
  }) async {
    if (_entries.containsKey(panelId)) return;

    final config = _readConfig(panelId, boardId);
    final folder = await _resolveFolder(config, boardId);
    final file = File('$folder${Platform.pathSeparator}${_fileName()}');
    final sink = await _openSink(file, format: const PcmWavFormat());

    final entry = _Entry(
      panelId: panelId,
      boardId: boardId,
      file: file,
      sink: sink,
      startedAt: _now().millisecondsSinceEpoch,
    );

    if (config.captureMicrophone) {
      final mic = _micFactory();
      entry.micSource = mic;
      final stream = await mic.start();
      // Cancelled in [stop] — stored so recording survives widget dispose.
      // ignore: cancel_subscriptions
      entry.micSub = stream.listen(entry.micBuf.add);
    }

    if (config.captureSystemAudio && systemSource != null) {
      entry.systemSource = systemSource;
      final stream = await systemSource.start();
      // ignore: cancel_subscriptions
      entry.systemSub = stream.listen(entry.systemBuf.add);
    }

    entry.uiTick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _writeProgress(panelId);
    });

    _entries[panelId] = entry;
    _writeProgress(panelId);
  }

  /// Stops the recording for [panelId], finalizes the WAV file and appends a
  /// recording entry to the panel state.
  Future<void> stop(String panelId) async {
    final entry = _entries.remove(panelId);
    if (entry == null) return;

    entry.uiTick?.cancel();
    await entry.micSub?.cancel();
    await entry.systemSub?.cancel();
    await entry.micSource?.stop();
    await entry.systemSource?.stop();

    final micBytes = entry.micBuf.takeBytes();
    final systemBytes = entry.systemBuf.takeBytes();
    final mixed = mixPcm16(micBytes, systemBytes);
    await entry.sink.add(mixed);
    await entry.sink.close();

    _writeFinished(entry, mixed.length);
  }

  bool isRecording(String panelId) => _entries.containsKey(panelId);

  /// Resolve the board that currently owns [panelId], scanning every board so
  /// the CLI (which only hands us a panel) can still drive the native engine.
  /// Returns null when the panel is unknown or no cubit is attached.
  String? boardIdForPanel(String panelId) {
    final cubit = _cubit;
    if (cubit == null) return null;
    for (final board in cubit.state.boards) {
      if (board.panels.any((p) => p.id == panelId)) return board.id;
    }
    return null;
  }

  List<String> get activePanelIds => _entries.keys.toList();

  Future<void> disposeAll() async {
    final ids = _entries.keys.toList();
    for (final id in ids) {
      await stop(id);
    }
  }

  // ── internals ────────────────────────────────────────────────────────────

  AudioRecorderConfig _readConfig(String panelId, String boardId) {
    final panel = _findPanel(panelId, boardId);
    if (panel == null) return const AudioRecorderConfig();
    return AudioRecorderConfig.fromState(panel.state);
  }

  BoardPanelInstance? _findPanel(String panelId, String boardId) {
    final cubit = _cubit;
    if (cubit == null) return null;
    for (final board in cubit.state.boards) {
      if (board.id != boardId) continue;
      for (final panel in board.panels) {
        if (panel.id == panelId) return panel;
      }
    }
    for (final board in cubit.state.boards) {
      for (final panel in board.panels) {
        if (panel.id == panelId) return panel;
      }
    }
    return null;
  }

  Future<String> _defaultFolderResolver(
    AudioRecorderConfig config,
    String boardId,
  ) async {
    final configured = config.saveFolder.trim();
    if (configured.isNotEmpty) return configured;

    final sep = Platform.pathSeparator;
    final cubit = _cubit;
    if (cubit != null) {
      BoardDocument? target;
      for (final board in cubit.state.boards) {
        if (board.id == boardId) {
          target = board;
          break;
        }
      }
      if (target == null) {
        final activeId = cubit.state.activeBoardId;
        for (final board in cubit.state.boards) {
          if (board.id == activeId) {
            target = board;
            break;
          }
        }
      }
      final defaultFolder = target?.defaultFolder ?? '';
      if (defaultFolder.isNotEmpty) {
        return '$defaultFolder${sep}recordings';
      }
    }
    return '${Directory.systemTemp.path}${sep}yoloit_recordings';
  }

  void _writeProgress(String panelId) {
    final cubit = _cubit;
    final entry = _entries[panelId];
    if (cubit == null || entry == null) return;
    final elapsed = _now().millisecondsSinceEpoch - entry.startedAt;
    cubit.updatePanel(
      panelId,
      (p) => p.copyWith(
        state: <String, dynamic>{
          ...p.state,
          'isRecording': true,
          'currentFile': entry.file.path,
          'startedAt': entry.startedAt,
          'elapsedMs': elapsed,
        },
      ),
      boardId: entry.boardId,
    );
  }

  void _writeFinished(_Entry entry, int mixedBytes) {
    final cubit = _cubit;
    if (cubit == null) return;
    final now = _now().millisecondsSinceEpoch;
    final durationMs = entry.sink.duration.inMilliseconds;
    cubit.updatePanel(
      entry.panelId,
      (p) {
        final existing =
            (p.state['recordings'] as List?)
                ?.map(
                  (e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
                )
                .toList() ??
            <Map<String, dynamic>>[];
        final recording = <String, dynamic>{
          'id': 'rec-$now',
          'path': entry.file.path,
          'name': entry.file.uri.pathSegments.last,
          'durationMs': durationMs,
          'sizeBytes': mixedBytes + 44,
          'createdAt': now,
          'format': 'wav',
        };
        return p.copyWith(
          state: <String, dynamic>{
            ...p.state,
            'isRecording': false,
            'currentFile': null,
            'elapsedMs': 0,
            'recordings': <Map<String, dynamic>>[...existing, recording],
          },
        );
      },
      boardId: entry.boardId,
    );
  }

  String _fileName() {
    final t = _now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
    return 'recording-$stamp.wav';
  }
}

class _Entry {
  _Entry({
    required this.panelId,
    required this.boardId,
    required this.file,
    required this.sink,
    required this.startedAt,
  });

  final String panelId;
  final String boardId;
  final File file;
  final PcmWavSink sink;
  final int startedAt;

  final BytesBuilder micBuf = BytesBuilder(copy: false);
  final BytesBuilder systemBuf = BytesBuilder(copy: false);

  AudioSource? micSource;
  AudioSource? systemSource;
  StreamSubscription<Uint8List>? micSub; // ignore: cancel_subscriptions
  StreamSubscription<Uint8List>? systemSub; // ignore: cancel_subscriptions
  Timer? uiTick;
}
