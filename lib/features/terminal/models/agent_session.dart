import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:yoloit/features/terminal/data/terminal_output_bus.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoxterm/xterm.dart';

enum AgentStatus { idle, live, error }

// ignore: must_be_immutable
class AgentSession extends Equatable {
  AgentSession({
    required this.id,
    required this.type,
    required this.workspacePath,
    this.workspaceId,
    this.status = AgentStatus.idle,
    this.sessionId,
    this.customName,
    this.worktreeContexts,
    this.hookPhase,
  }) : terminal = Terminal(maxLines: 2000);

  // Private constructor that preserves an existing terminal instance.
  AgentSession._preserve({
    required this.id,
    required this.type,
    required this.workspacePath,
    required this.terminal,
    this.workspaceId,
    this.status = AgentStatus.idle,
    this.sessionId,
    this.customName,
    this.worktreeContexts,
    this.hookPhase,
  });

  final String id;
  final AgentType type;
  final String workspacePath;
  /// ID of the parent workspace — used to re-inject secrets on restore.
  final String? workspaceId;
  final AgentStatus status;
  final String? sessionId;
  final String? customName;
  final Terminal terminal;
  /// Maps repoPath → selectedWorktreePath. Null = default workspace dir.
  final Map<String, String>? worktreeContexts;

  /// Fine-grained phase from Copilot hook events.
  /// null = idle (session alive, agent not actively working).
  final AgentPhase? hookPhase;

  /// Rolling plain-text view of recent PTY output (max 300 lines).
  /// NOT included in [props] — mutations don't trigger state rebuilds.
  ///
  /// Computed LAZILY from [_rawChunks]: splitting every flushed batch into
  /// line Strings allocated millions of short-lived objects per second under
  /// output floods. Instead we scan the retained raw chunks backwards for
  /// '\n' boundaries and substring only the tail that can contain the last
  /// [_maxRecentLines] lines, then strip ANSI and split just that tail.
  /// ANSI/VT100 escape sequences never contain '\n', so line boundaries in
  /// the raw buffer match the plain-text ones exactly.
  List<String> get recentLines {
    if (_recentLinesVersion == _outputVersion && _recentLinesCache != null) {
      return _recentLinesCache!;
    }
    final tail = _rawTailForLines(_maxRecentLines);
    final lines = tail.isEmpty ? <String>[] : stripAnsi(tail).split('\n');
    _recentLinesVersion = _outputVersion;
    _recentLinesCache = lines;
    return lines;
  }

  /// Bumped on every output append; invalidates the lazy [recentLines] and
  /// [lastLines] views.
  int _outputVersion = 0;
  int _recentLinesVersion = -1;
  List<String>? _recentLinesCache;

  /// Last known scroll offset of the terminal view.
  /// NOT included in [props] — persisted across widget rebuilds.
  double scrollOffset = 0.0;

  /// Rolling buffer of RAW PTY bytes (with ANSI) — replayed to new remote
  /// guests so they see the full current terminal state, not just new data.
  /// Capped at [_maxRawBytes] to bound memory.
  ///
  /// Stored as a chunk list with a running length instead of a single
  /// StringBuffer: trimming a StringBuffer requires toString()+substring on
  /// the whole ~256 KiB on EVERY flush once the cap is reached, which was a
  /// major source of GC churn while typing. Trimming here only advances an
  /// offset; compaction is amortized (once per 512 dropped chunks).
  ///
  /// The list holds RAW UTF-8 [Uint8List]s; text never lives in this list.
  /// [historyText] decodes lazily on read with caching by [_outputVersion].
  final List<Uint8List> _rawChunks = [];
  int _rawChunksStart = 0;
  int _rawLength = 0;

  /// Lazily-decoded text view of [_rawChunks]. Built once per
  /// [_outputVersion] change; subsequent reads reuse [historyTextCache].
  int _historyTextVersion = -1;
  String? historyTextCache;

  static const _maxRecentLines = 300;
  static const _maxRawBytes = 256 * 1024; // 256 KiB raw ANSI history

  /// Lazily-decoded history text. Decoded per-append from the stored byte
  /// chunks using [utf8.decode] with `allowMalformed: true`. This matches
  /// the OLD per-flush decode semantics — so a multibyte sequence split
  /// across two appends renders U+FFFD at the split edge, the same way the
  /// old per-flush decoder did.
  ///
  /// Decoded once per [_outputVersion] change; subsequent reads reuse the
  /// cache. While typing, no decoder runs at all — the cache only fills
  /// when a consumer (e.g. the `terminal output` CLI command, the
  /// collaboration guest, or the run panel) actually reads history.
  String get historyText {
    if (_historyTextVersion == _outputVersion && historyTextCache != null) {
      return historyTextCache!;
    }
    final buf = StringBuffer();
    for (var i = _rawChunksStart; i < _rawChunks.length; i++) {
      buf.write(_decodeRaw(_rawChunks[i]));
    }
    final text = buf.toString();
    _historyTextVersion = _outputVersion;
    historyTextCache = text;
    return text;
  }

  /// Test seam: count of [utf8.decode] invocations made on behalf of
  /// [historyText]. Incremented once per cached chunk per read; resets when
  /// the cache is invalidated (i.e. on every new append).
  @visibleForTesting
  int utf8DecodeCallsForTesting = 0;

  /// Test seam: attach a side-effect to [utf8.decode] inside [historyText].
  /// Used by tests to verify caching; not invoked in production.
  @visibleForTesting
  void Function(Uint8List bytes)? utf8DecodeSpyForTesting;

  /// Append raw PTY data as already-decoded text: kept for backends whose
  /// output stream is `Stream<String>` (e.g. pty2). Encodes the text to
  /// UTF-8 bytes and stores them — no separate `String` list is kept, so
  /// there is no second copy of the data in memory.
  void appendOutput(String rawData) {
    final bytes = Uint8List.fromList(utf8.encode(rawData));
    _rawChunks.add(bytes);
    _rawLength += bytes.length;
    _trimRawChunks();
    _outputVersion++;

    // Push the (already-decoded) text so remote web guests can render via
    // xterm — guests need the text form, not the raw bytes.
    TerminalOutputBus.instance.write(id, rawData);
  }

  /// Batch variant of [appendOutput]: encodes each chunk and stores the
  /// resulting bytes (no join/copy of the input chunks). Pushes the same
  /// decoded chunks to the output bus in order.
  ///
  /// Kept for the String-output backend path. Prefer
  /// [appendOutputChunksBytes] on the byte-output path — it stores raw
  /// bytes without any UTF-8 decode, eliminating the per-flush decode that
  /// the byte path used to do for history storage.
  void appendOutputChunks(List<String> chunks) {
    if (chunks.isEmpty) return;
    for (final chunk in chunks) {
      final bytes = Uint8List.fromList(utf8.encode(chunk));
      _rawChunks.add(bytes);
      _rawLength += bytes.length;
    }
    _trimRawChunks();
    _outputVersion++;

    for (final chunk in chunks) {
      TerminalOutputBus.instance.write(id, chunk);
    }
  }

  /// Byte-output backend path: stores raw UTF-8 chunks without decoding.
  /// Mirrors [appendOutputChunks] semantics but skips the per-flush
  /// `utf8.decode` — the CLI / collaboration / UI consumers of history only
  /// decode when they actually read [historyText].
  void appendOutputChunksBytes(List<Uint8List> chunks) {
    if (chunks.isEmpty) return;
    for (final chunk in chunks) {
      _rawChunks.add(chunk);
      _rawLength += chunk.length;
    }
    _trimRawChunks();
    _outputVersion++;
  }

  String _decodeRaw(Uint8List bytes) {
    final spy = utf8DecodeSpyForTesting;
    if (spy != null) spy(bytes);
    utf8DecodeCallsForTesting++;
    return utf8.decode(bytes, allowMalformed: true);
  }

  void _trimRawChunks() {
    while (_rawLength > _maxRawBytes &&
        _rawChunksStart < _rawChunks.length - 1) {
      _rawLength -= _rawChunks[_rawChunksStart].length;
      _rawChunksStart++;
    }
    if (_rawChunksStart >= 512) {
      _rawChunks.removeRange(0, _rawChunksStart);
      _rawChunksStart = 0;
    }
  }

  /// Returns the raw tail holding at most [maxLines] '\n'-separated
  /// segments from the lazily-decoded [historyText]. The cached history
  /// text already exists by the time this is called from [lastLines], so
  /// the substring scan costs nothing extra.
  String _rawTailForLines(int maxLines) {
    final history = historyText;
    if (history.isEmpty) return '';
    var newlines = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      if (history.codeUnitAt(i) != 0x0A) continue;
      newlines++;
      if (newlines >= maxLines) {
        return history.substring(i + 1);
      }
    }
    return history;
  }

  /// Returns accumulated raw PTY bytes since the session started (capped),
  /// decoded from [_rawChunks] with the same per-chunk `allowMalformed`
  /// semantics as [historyText].
  ///
  /// Used to replay history to newly-connected web guests.
  String rawHistory() => historyText;

  /// Last [n] non-empty plain-text lines for display in the browser.
  /// Falls back to reading the xterm buffer when the ring buffer is still empty
  /// (e.g., first snapshot right after app start with existing sessions).
  ///
  /// Results are cached: repeated calls with the same [n] and no intervening
  /// output return the cached list without re-iterating.
  int _lastLinesVersion = -1;
  int _lastLinesN = -1;
  List<String>? _lastLinesCache;

  List<String> lastLines([int n = 80]) {
    final recent = recentLines;
    if (recent.isNotEmpty) {
      // Cache hit: same n, no output appended since the last computation.
      if (_lastLinesN == n &&
          _lastLinesVersion == _outputVersion &&
          _lastLinesCache != null) {
        return _lastLinesCache!;
      }
      _lastLinesN = n;
      _lastLinesVersion = _outputVersion;
      final nonEmpty = recent.where((l) => l.trim().isNotEmpty).toList();
      _lastLinesCache = nonEmpty.length <= n
          ? nonEmpty
          : nonEmpty.sublist(nonEmpty.length - n);
      return _lastLinesCache!;
    }
    // Fallback: read only the current visible screen rows (no scrollback).
    // Using getText() on the full buffer causes duplicates when the terminal
    // app (e.g. Copilot CLI) redraws the screen — the scrollback retains the
    // previous draw AND the current one.
    try {
      final buf = terminal.buffer;
      final startRow = buf.scrollBack;  // first visible row
      final lines = <String>[];
      if (startRow < buf.lines.length) {
        for (int row = startRow; row < buf.lines.length; row++) {
          final text = stripAnsi(buf.lines[row].getText()).trimRight();
          if (text.trim().isNotEmpty) lines.add(text);
        }
      }
      if (lines.isEmpty) {
        // Fallback if visible screen was blank: use full buffer, last n lines.
        final raw = buf.getText();
        final allLines = raw.split('\n')
            .map(stripAnsi)
            .where((l) => l.trim().isNotEmpty)
            .toList();
        return allLines.length <= n ? allLines : allLines.sublist(allLines.length - n);
      }
      return lines.length <= n ? lines : lines.sublist(lines.length - n);
    } catch (_) {
      return const [];
    }
  }

  AgentSession copyWith({
    AgentStatus? status,
    String? sessionId,
    String? customName,
    bool clearCustomName = false,
    Map<String, String>? worktreeContexts,
    AgentPhase? hookPhase,
    bool clearHookPhase = false,
  }) {
    return AgentSession._preserve(
      id: id,
      type: type,
      workspacePath: workspacePath,
      workspaceId: workspaceId,
      terminal: terminal,
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
      customName: clearCustomName ? null : (customName ?? this.customName),
      worktreeContexts: worktreeContexts ?? this.worktreeContexts,
      hookPhase: clearHookPhase ? null : (hookPhase ?? this.hookPhase),
    );
  }

  String get displayName => customName?.isNotEmpty == true ? customName! : type.displayName;

  @override
  List<Object?> get props => [id, type.name, workspacePath, status, sessionId, customName, hookPhase, worktreeContexts];
}
