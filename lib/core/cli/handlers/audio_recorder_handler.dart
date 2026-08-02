import 'dart:async';
import 'dart:io';

import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/audio_recorder/transcription_service.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/audio_recorder_plugin.dart';

/// Signature of an audio-recorder action handler: the CLI arguments plus the
/// panel whose state is being read/updated.
typedef _AudioActionHandler =
    FutureOr<CliActionResult> Function(
      Map<String, dynamic> args,
      BoardPanelInstance panel,
    );

/// CLI handler for Audio Recorder panels (`board.audio_recorder`).
///
/// The handler stays decoupled from the native capture engine: it only returns
/// a `stateUpdate`. The CLI server merges it and a type-specific hook drives
/// [AudioRecordingManager] (start/stop) — exactly like `board.timer` and
/// `board.playlist`.
class AudioRecorderCliHandler extends PanelCliHandler {
  const AudioRecorderCliHandler();

  @override
  String get typeId => 'board.audio_recorder';

  @override
  List<String> get supportedActions => [
    'start',
    'stop',
    'list',
    'get',
    'set-folder',
    'set-config',
    'delete',
    'transcribe',
  ];

  List<dynamic> _recordings(BoardPanelInstance panel) =>
      panel.state['recordings'] as List<dynamic>? ?? <dynamic>[];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {
      'config': AudioRecorderConfig.fromState(panel.state).toJson(),
      'isRecording': panel.state['isRecording'] ?? false,
      'recordings': panel.state['recordings'] ?? <dynamic>[],
      'currentFile': panel.state['currentFile'],
      'elapsedMs': panel.state['elapsedMs'] ?? 0,
      'lastError': panel.state['lastError'],
    };
  }

  Map<String, _AudioActionHandler> get _actionHandlers => {
    'start': _handleStart,
    'stop': _handleStop,
    'list': _handleList,
    'get': _handleGet,
    'set-folder': _handleSetFolder,
    'set-config': _handleSetConfig,
    'delete': _handleDelete,
    'transcribe': _handleTranscribe,
  };

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final handler = _actionHandlers[action];
    if (handler == null) {
      return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
    return handler(args, panel);
  }

  CliActionResult _handleStart(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) => const CliActionResult(
    message: 'Recording started',
    stateUpdate: {'isRecording': true},
  );

  CliActionResult _handleStop(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) => const CliActionResult(
    message: 'Recording stopped',
    stateUpdate: {'isRecording': false},
  );

  CliActionResult _handleList(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final recordings = _recordings(panel);
    return CliActionResult(
      data: {'recordings': recordings, 'total': recordings.length},
    );
  }

  CliActionResult _handleGet(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) => CliActionResult(data: getContent(panel));

  CliActionResult _handleSetFolder(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final folder = args['folder'] as String?;
    if (folder == null) {
      return const CliActionResult(ok: false, message: 'Missing "folder"');
    }
    final updated = AudioRecorderConfig.fromState(
      panel.state,
    ).copyWith(saveFolder: folder);
    return CliActionResult(
      message: 'Save folder set to $folder',
      stateUpdate: {AudioRecorderConfig.configKey: updated.toJson()},
    );
  }

  CliActionResult _handleSetConfig(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final updated = AudioRecorderConfig.fromState(panel.state).copyWith(
      captureSystemAudio: _parseBool(args['captureSystemAudio']),
      captureMicrophone: _parseBool(args['captureMicrophone']),
      format: args.containsKey('format') ? args['format']?.toString() : null,
    );
    return CliActionResult(
      message: 'Config updated',
      stateUpdate: {AudioRecorderConfig.configKey: updated.toJson()},
    );
  }

  CliActionResult _handleDelete(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final id = args['id'] as String?;
    final name = args['name'] as String?;
    if (id == null && name == null) {
      return const CliActionResult(
        ok: false,
        message: 'Missing "id" or "name"',
      );
    }
    final recordings = _recordings(panel)
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    Map<String, dynamic>? removed;
    final remaining = <Map<String, dynamic>>[];
    for (final rec in recordings) {
      final matches =
          (id != null && rec['id'] == id) ||
          (name != null && rec['name'] == name);
      if (matches && removed == null) {
        removed = rec;
      } else {
        remaining.add(rec);
      }
    }
    if (removed == null) {
      return const CliActionResult(ok: false, message: 'Recording not found');
    }
    final path = removed['path'] as String?;
    if (path != null && path.isNotEmpty) {
      // Best-effort: the CLI server only runs on desktop runtimes that
      // have a local filesystem, so importing dart:io here is safe.
      try {
        File(path).deleteSync();
      } catch (_) {
        // Ignore — the entry is removed from state regardless.
      }
    }
    return CliActionResult(
      message: 'Deleted ${removed['name'] ?? removed['id']}',
      stateUpdate: {'recordings': remaining},
    );
  }

  Future<CliActionResult> _handleTranscribe(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final recordings = _recordings(panel)
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (recordings.isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'No recordings to transcribe',
      );
    }
    final id = args['id'] as String?;
    final Map<String, dynamic> recording;
    if (id != null) {
      final matches = recordings.where((r) => r['id'] == id).toList();
      if (matches.isEmpty) {
        return CliActionResult(ok: false, message: 'Recording not found: $id');
      }
      recording = matches.first;
    } else {
      recording = recordings.last;
    }
    final path = recording['path'] as String?;
    if (path == null || path.isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'Recording has no file path',
      );
    }
    final TranscriptResult result;
    try {
      result = await TranscriptionService.current.transcribeFile(
        path,
        mode: args['mode'] as String?,
      );
    } catch (e) {
      return CliActionResult(ok: false, message: 'Transcription failed: $e');
    }
    final sep = Platform.pathSeparator;
    final fileName = path.split(sep).last;
    final baseName = fileName.endsWith('.wav')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;
    final name = recording['name'] as String? ?? baseName;
    final mdPath = '${File(path).parent.path}$sep$baseName.md';
    try {
      File(
        mdPath,
      ).writeAsStringSync('# Transcript — $name\n\n${result.text}\n');
    } catch (e) {
      return CliActionResult(
        ok: false,
        message: 'Failed to write transcript: $e',
      );
    }
    final recordingId = recording['id'] as String? ?? baseName;
    final existing =
        (panel.state['transcripts'] as Map<dynamic, dynamic>?)?.map(
          (key, value) => MapEntry(key.toString(), value),
        ) ??
        <String, dynamic>{};
    final updated = Map<String, dynamic>.from(existing);
    updated[recordingId] = <String, dynamic>{
      'mdPath': mdPath,
      'chars': result.text.length,
      'mode': result.modeUsed,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    return CliActionResult(
      data: <String, dynamic>{
        'mdPath': mdPath,
        'chars': result.text.length,
        'modeUsed': result.modeUsed,
        'recordingId': recordingId,
      },
      stateUpdate: {'transcripts': updated},
      message: 'Transcript saved to $mdPath',
    );
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'start': const CliActionHelp(
      description: 'Start native audio capture on this panel',
      example: 'yoloit audio:start',
    ),
    'stop': const CliActionHelp(
      description: 'Stop the active recording and finalize the file',
      example: 'yoloit audio:stop',
    ),
    'list': const CliActionHelp(
      description: 'List recordings captured by this panel',
      example: 'yoloit audio:list',
    ),
    'get': const CliActionHelp(
      description: 'Show recorder config, state and recordings',
    ),
    'set-folder': const CliActionHelp(
      description: 'Set the folder where recordings are written',
      params: {'folder': 'Absolute path to the output folder'},
      example: 'yoloit audio:set-folder ~/Recordings',
    ),
    'set-config': const CliActionHelp(
      description: 'Update capture toggles and output format',
      params: {
        'captureSystemAudio': 'Capture system/loopback audio (true|false)',
        'captureMicrophone': 'Capture the microphone (true|false)',
        'format': 'Output container, e.g. wav',
      },
    ),
    'delete': const CliActionHelp(
      description: 'Delete a recording entry (and its file) by id or name',
      params: {'id': 'Recording id', 'name': 'Recording file name'},
    ),
    'transcribe': const CliActionHelp(
      description:
          'Transcribe a recording (latest by default) to a Markdown file next to the WAV',
      params: {
        'id': 'Recording id (defaults to the latest recording)',
        'mode': 'ASR mode: local or cloud (defaults to voice settings)',
      },
      example: 'yoloit audio:transcribe --mode local',
    ),
  };

  bool? _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'true':
          return true;
        case 'false':
          return false;
      }
    }
    return null;
  }
}
