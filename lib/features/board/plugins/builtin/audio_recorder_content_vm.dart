import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:yoloit/core/platform/microphone_permission_service.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/platform/system_audio_bridge.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/audio_recorder/audio_recording_manager.dart';
import 'package:yoloit/features/board/audio_recorder/audio_source.dart';
import 'package:yoloit/features/board/audio_recorder/system_audio_source.dart';
import 'package:yoloit/features/board/audio_recorder/transcription_service.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/audio_recorder_plugin.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';

/// Desktop (dart:io) content for the audio recorder panel.
///
/// Wired to [AudioRecordingManager]: the record button starts/stops a real
/// capture that mixes the microphone and (when available) system audio into a
/// single WAV file. Saved recordings can be auditioned inline via media_kit,
/// revealed in the system file manager, or deleted. The web build uses the
/// stub instead.
Widget buildAudioRecorderContent(
  BoardPanelInstance panel,
  BoardPanelRenderContext renderContext,
) =>
    AudioRecorderPanelContent(panel: panel, renderContext: renderContext);

class AudioRecorderPanelContent extends StatefulWidget {
  const AudioRecorderPanelContent({
    required this.panel,
    required this.renderContext,
    super.key,
  });

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<AudioRecorderPanelContent> createState() =>
      _AudioRecorderPanelContentState();

  /// Writes the generated transcript markdown to disk.
  ///
  /// Overridable in tests so the transcribe flow does not perform real
  /// `dart:io` file writes, which leave the headless widget-test isolate
  /// pending. Defaults to a real `File.writeAsString`.
  static Future<void> Function(String path, String contents)
      writeTranscriptFile = _defaultWriteTranscriptFile;

  static Future<void> _defaultWriteTranscriptFile(
    String path,
    String contents,
  ) =>
      File(path).writeAsString(contents).then((_) {});
}

class _AudioRecorderPanelContentState extends State<AudioRecorderPanelContent> {
  bool _busy = false;

  // Inline playback. The player is created lazily (on first play) so the unit
  // tests — which never start playback — do not need a native media_kit init.
  Player? _player;
  final List<StreamSubscription<dynamic>> _playerSubs = [];
  String? _playingId;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  String? _transcribingId;

  AudioRecorderConfig get _config =>
      AudioRecorderConfig.fromState(widget.panel.state);

  bool get _isRecording => widget.panel.state['isRecording'] as bool? ?? false;

  List<Map<String, dynamic>> get _recordings =>
      (widget.panel.state['recordings'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
          .toList() ??
      const [];

  String? get _lastError => widget.panel.state['lastError'] as String?;

  @override
  void dispose() {
    for (final s in _playerSubs) {
      s.cancel();
    }
    _playerSubs.clear();
    _player?.dispose();
    _player = null;
    super.dispose();
  }

  void _writeState(Map<String, dynamic> patch) {
    widget.renderContext.onUpdateState(<String, dynamic>{
      ...widget.panel.state,
      ...patch,
    });
  }

  void _writeConfig(AudioRecorderConfig config) {
    _writeState(<String, dynamic>{AudioRecorderConfig.configKey: config.toJson()});
  }

  void _setError(String? message) {
    _writeState(<String, dynamic>{'lastError': message});
  }

  String? _findBoardId() {
    try {
      final cubit = context.read<BoardCubit>();
      for (final board in cubit.state.boards) {
        if (board.panels.any((p) => p.id == widget.panel.id)) {
          return board.id;
        }
      }
      return cubit.state.activeBoardId;
    } catch (_) {
      return null;
    }
  }

  Future<void> _toggleRecording() async {
    if (_busy) return;
    setState(() => _busy = true);
    _setError(null);
    try {
      final manager = AudioRecordingManager.instance;
      if (_isRecording) {
        await manager.stop(widget.panel.id);
        return;
      }

      final config = _config;
      if (config.captureMicrophone) {
        final granted =
            await MicrophonePermissionService.instance.ensureGranted();
        if (!granted) {
          _setError('Microphone permission is required to record.');
          return;
        }
      }

      AudioSource? systemSource;
      if (config.captureSystemAudio && SystemAudioBridge.instance.isSupported) {
        final ok = await SystemAudioBridge.instance.request();
        if (ok) {
          systemSource = SystemAudioSource();
        } else {
          // System audio denied — record the microphone only and surface a hint.
          _setError(
            'Screen Recording permission denied; recording microphone only.',
          );
        }
      }

      final boardId = _findBoardId();
      if (boardId == null) {
        _setError('Could not determine the board for this panel.');
        return;
      }

      await manager.start(
        panelId: widget.panel.id,
        boardId: boardId,
        systemSource: systemSource,
      );
    } catch (e) {
      _setError('Recording failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFolder() async {
    if (_isRecording) return;
    final current = _config.saveFolder;
    final dir = await BoardFilePicker.pickDirectory(
      context,
      remoteInfo: widget.renderContext.remoteInfo,
      initialPath: current.isEmpty ? null : current,
      title: 'Choose recordings folder',
    );
    if (dir == null) return;
    _writeConfig(_config.copyWith(saveFolder: dir));
  }

  Player _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = Player();
    _player = player;
    _playerSubs.add(
      player.stream.position.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
    );
    _playerSubs.add(
      player.stream.duration.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
    );
    _playerSubs.add(
      player.stream.playing.listen((v) {
        if (mounted) setState(() => _isPlaying = v);
      }),
    );
    _playerSubs.add(
      player.stream.completed.listen((completed) {
        if (completed && mounted) {
          setState(() {
            _isPlaying = false;
            _position = Duration.zero;
          });
        }
      }),
    );
    return player;
  }

  Future<void> _togglePlay(Map<String, dynamic> recording) async {
    final id = recording['id'] as String?;
    final path = recording['path'] as String?;
    if (id == null || path == null) return;
    try {
      final player = _ensurePlayer();
      if (_playingId == id && _isPlaying) {
        player.pause();
        return;
      }
      if (_playingId != id) {
        setState(() {
          _playingId = id;
          _position = Duration.zero;
          _duration = Duration.zero;
        });
        player.open(Media(path), play: true);
      } else {
        player.play();
      }
    } catch (e) {
      _setError('Playback failed: $e');
    }
  }

  void _seek(Duration value) {
    _player?.seek(value);
  }

  Future<void> _reveal(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      await PlatformLauncher.instance.revealInFinder(path);
    } catch (e) {
      _setError('Could not reveal file: $e');
    }
  }

  void _deleteRecording(Map<String, dynamic> recording) {
    final id = recording['id'] as String?;
    if (id == null) return;
    if (_playingId == id) {
      _player?.pause();
      _playingId = null;
    }
    final path = recording['path'] as String?;
    if (path != null && path.isNotEmpty) {
      try {
        File(path).deleteSync();
      } catch (_) {
        // File may already be gone; removing it from the list is still desired.
      }
    }
    final remaining =
        _recordings.where((e) => e['id'] != id).toList(growable: false);
    _writeState(<String, dynamic>{'recordings': remaining});
  }

  Map<String, dynamic> _transcriptsMap() {
    final raw = widget.panel.state['transcripts'];
    if (raw is Map) {
      return raw.map(
        (k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)),
      );
    }
    return <String, dynamic>{};
  }

  String _mdPathFor(String audioPath) {
    final lower = audioPath.toLowerCase();
    if (lower.endsWith('.wav')) {
      return '${audioPath.substring(0, audioPath.length - 4)}.md';
    }
    return '$audioPath.md';
  }

  /// Opens the generated transcript as a preview panel on the board. Falls back
  /// to revealing the file in Finder when the host cannot create panels (e.g.
  /// offscreen previews).
  Future<void> _openTranscriptPanel(String mdPath, String title) async {
    final create = widget.renderContext.onCreateLinkedPanel;
    if (create != null) {
      try {
        await create(
          'board.file.preview',
          <String, dynamic>{'path': mdPath, 'title': title},
          title,
        );
        return;
      } catch (_) {
        // Panel creation failed — fall back to the system file manager.
      }
    }
    try {
      await PlatformLauncher.instance.revealInFinder(mdPath);
    } catch (_) {
      // Best-effort; the file is already written next to the recording.
    }
  }

  Future<void> _transcribe(Map<String, dynamic> recording) async {
    final id = recording['id'] as String?;
    final path = recording['path'] as String?;
    if (id == null || path == null || _transcribingId != null) return;
    setState(() => _transcribingId = id);
    _setError(null);
    try {
      final result = await TranscriptionService.current.transcribeFile(path);
      final text = result.text;
      final name = recording['name'] as String? ?? 'recording';
      final mdPath = _mdPathFor(path);
      await AudioRecorderPanelContent.writeTranscriptFile(
        mdPath,
        '# Transcript — $name\n\n$text\n',
      );
      final transcripts = _transcriptsMap()
        ..[id] = <String, dynamic>{
          'mdPath': mdPath,
          'chars': text.length,
          'mode': result.modeUsed,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        };
      _writeState(<String, dynamic>{'transcripts': transcripts});
      if (mounted) {
        await _openTranscriptPanel(mdPath, '$name.md');
      }
    } catch (e) {
      _setError('Transcription failed: $e');
    } finally {
      if (mounted) setState(() => _transcribingId = null);
    }
  }

  String _elapsedLabel() {
    final ms = widget.panel.state['elapsedMs'] as int? ?? 0;
    return _formatDuration(Duration(milliseconds: ms));
  }

  static String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds.clamp(0, 359999);
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final config = _config;
    final folderLabel =
        config.saveFolder.isEmpty ? 'Board default folder' : config.saveFolder;
    final recordings = _recordings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SaveFolderRow(
          folderLabel: folderLabel,
          enabled: !_isRecording,
          colors: colors,
          onSurface: onSurface,
          onChoose: _pickFolder,
        ),
        const SizedBox(height: 8),
        _SourceToggle(
          key: const ValueKey('toggle-system-audio'),
          label: 'System audio (speakers / headphones)',
          icon: Icons.hearing_rounded,
          value: config.captureSystemAudio,
          enabled: !_isRecording,
          colors: colors,
          onSurface: onSurface,
          onChanged: (v) => _writeConfig(config.copyWith(captureSystemAudio: v)),
        ),
        _SourceToggle(
          key: const ValueKey('toggle-microphone'),
          label: 'Microphone',
          icon: Icons.mic_rounded,
          value: config.captureMicrophone,
          enabled: !_isRecording,
          colors: colors,
          onSurface: onSurface,
          onChanged: (v) => _writeConfig(config.copyWith(captureMicrophone: v)),
        ),
        if (_lastError != null) ...[
          const SizedBox(height: 6),
          Text(
            _lastError!,
            style: TextStyle(fontSize: 11, color: colors.accentRed),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 8),
        if (recordings.isNotEmpty)
          Expanded(
            child: RepaintBoundary(
              child: ListView.separated(
                itemCount: recordings.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final rec = recordings[index];
                  final id = rec['id'] as String? ?? '';
                  final isActive = id == _playingId;
                  return _RecordingRow(
                    recording: rec,
                    isActive: isActive,
                    isPlaying: isActive && _isPlaying,
                    isTranscribing: id == _transcribingId,
                    position: isActive ? _position : Duration.zero,
                    duration: isActive ? _duration : Duration.zero,
                    colors: colors,
                    onSurface: onSurface,
                    formatDuration: _formatDuration,
                    onTogglePlay: () => _togglePlay(rec),
                    onSeek: _seek,
                    onReveal: () => _reveal(rec['path'] as String?),
                    onTranscribe: () => _transcribe(rec),
                    onDelete: () => _deleteRecording(rec),
                  );
                },
              ),
            ),
          )
        else
          const Spacer(),
        if (_isRecording)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _elapsedLabel(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: colors.accentRed,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        const SizedBox(height: 8),
        _RecordButton(
          isRecording: _isRecording,
          busy: _busy,
          colors: colors,
          onSurface: onSurface,
          onPressed: _toggleRecording,
        ),
        const SizedBox(height: 8),
        Text(
          '${recordings.length} recording${recordings.length == 1 ? '' : 's'}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: onSurface.withAlpha(140)),
        ),
      ],
    );
  }
}

class _SaveFolderRow extends StatelessWidget {
  const _SaveFolderRow({
    required this.folderLabel,
    required this.enabled,
    required this.colors,
    required this.onSurface,
    required this.onChoose,
  });

  final String folderLabel;
  final bool enabled;
  final AppColorScheme colors;
  final Color onSurface;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceHighlight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 16, color: colors.accentBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              folderLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: onSurface),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            key: const ValueKey('choose-folder'),
            onTap: enabled ? onChoose : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                'Choose…',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? colors.accentBlue
                      : onSurface.withAlpha(100),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceToggle extends StatelessWidget {
  const _SourceToggle({
    required this.label,
    required this.icon,
    required this.value,
    required this.enabled,
    required this.colors,
    required this.onSurface,
    required this.onChanged,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool value;
  final bool enabled;
  final AppColorScheme colors;
  final Color onSurface;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: onSurface.withAlpha(enabled ? 170 : 80),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: onSurface.withAlpha(enabled ? 255 : 100),
                ),
              ),
            ),
            Switch.adaptive(
              value: value,
              activeThumbColor: colors.accentRed,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingRow extends StatelessWidget {
  const _RecordingRow({
    required this.recording,
    required this.isActive,
    required this.isPlaying,
    required this.isTranscribing,
    required this.position,
    required this.duration,
    required this.colors,
    required this.onSurface,
    required this.formatDuration,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onReveal,
    required this.onTranscribe,
    required this.onDelete,
  });

  final Map<String, dynamic> recording;
  final bool isActive;
  final bool isPlaying;
  final bool isTranscribing;
  final Duration position;
  final Duration duration;
  final AppColorScheme colors;
  final Color onSurface;
  final String Function(Duration) formatDuration;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onReveal;
  final VoidCallback onTranscribe;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final name = recording['name'] as String? ?? 'recording';
    final durationMs = recording['durationMs'] as int? ?? 0;
    final totalMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds
        : durationMs;
    final posMs = position.inMilliseconds.clamp(0, totalMs);
    final showSlider = isActive && totalMs > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isActive
            ? colors.accentBlue.withValues(alpha: 0.10)
            : colors.surfaceHighlight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? colors.accentBlue : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              InkWell(
                key: ValueKey('play-$name'),
                onTap: onTogglePlay,
                borderRadius: BorderRadius.circular(14),
                child: Icon(
                  isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  size: 26,
                  color: colors.accentBlue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: onSurface),
                    ),
                    Text(
                      showSlider
                          ? '${formatDuration(position)} / ${formatDuration(duration)}'
                          : formatDuration(Duration(milliseconds: durationMs)),
                      style: TextStyle(
                        fontSize: 10,
                        color: onSurface.withAlpha(150),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('transcribe-$name'),
                tooltip: 'Transcribe to Markdown',
                onPressed: isTranscribing ? null : onTranscribe,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                icon: isTranscribing
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: onSurface.withAlpha(200),
                        ),
                      )
                    : Icon(Icons.text_snippet_outlined,
                        size: 16, color: colors.accentBlue),
              ),
              IconButton(
                key: ValueKey('reveal-$name'),
                tooltip: 'Reveal in Finder',
                icon: Icon(Icons.open_in_new_rounded,
                    size: 16, color: onSurface.withAlpha(180)),
                onPressed: onReveal,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              ),
              IconButton(
                key: ValueKey('delete-$name'),
                tooltip: 'Delete recording',
                icon: Icon(Icons.delete_outline_rounded,
                    size: 16, color: colors.accentRed),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              ),
            ],
          ),
          if (showSlider)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: posMs.toDouble(),
                max: totalMs.toDouble(),
                onChanged: (v) => onSeek(Duration(milliseconds: v.round())),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.isRecording,
    required this.busy,
    required this.colors,
    required this.onSurface,
    required this.onPressed,
  });

  final bool isRecording;
  final bool busy;
  final AppColorScheme colors;
  final Color onSurface;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = colors.accentRed;
    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: isRecording ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isRecording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
              color: accent,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              isRecording ? 'Stop recording' : 'Start recording',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
