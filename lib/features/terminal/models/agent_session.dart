import 'package:equatable/equatable.dart';
import 'package:xterm/xterm.dart';
import 'package:yoloit/features/terminal/data/terminal_output_bus.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

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
  final List<String> _rawChunks = [];
  int _rawChunksStart = 0;
  int _rawLength = 0;

  static const _maxRecentLines = 300;
  static const _maxRawBytes = 256 * 1024; // 256 KiB raw ANSI history

  /// Append raw PTY data: stores the chunk by reference and trims the
  /// rolling raw buffer. The plain-text line view ([recentLines]) is built
  /// lazily on read — nothing is split or stripped here.
  void appendOutput(String rawData) {
    _rawChunks.add(rawData);
    _rawLength += rawData.length;
    _trimRawChunks();
    _outputVersion++;

    // Push RAW bytes (with ANSI) so remote web guests can render via xterm.
    TerminalOutputBus.instance.write(id, rawData);
  }

  /// Batch variant of [appendOutput]: stores each chunk by reference (no
  /// join/copy) and pushes the same chunks to the output bus in order.
  void appendOutputChunks(List<String> chunks) {
    if (chunks.isEmpty) return;
    for (final chunk in chunks) {
      _rawChunks.add(chunk);
      _rawLength += chunk.length;
    }
    _trimRawChunks();
    _outputVersion++;

    for (final chunk in chunks) {
      TerminalOutputBus.instance.write(id, chunk);
    }
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
  /// segments, scanning chunks backwards and copying only that tail.
  String _rawTailForLines(int maxLines) {
    if (_rawChunksStart >= _rawChunks.length) return '';
    var newlines = 0;
    for (var i = _rawChunks.length - 1; i >= _rawChunksStart; i--) {
      final chunk = _rawChunks[i];
      var pos = chunk.length;
      while (pos > 0) {
        final idx = chunk.lastIndexOf('\n', pos - 1);
        if (idx < 0) break;
        newlines++;
        if (newlines >= maxLines) {
          return _joinRawFrom(i, idx + 1);
        }
        pos = idx;
      }
    }
    return _joinRawFrom(_rawChunksStart, 0);
  }

  String _joinRawFrom(int chunkIndex, int offset) {
    if (chunkIndex == _rawChunks.length - 1) {
      return _rawChunks[chunkIndex].substring(offset);
    }
    final buf = StringBuffer(_rawChunks[chunkIndex].substring(offset));
    for (var i = chunkIndex + 1; i < _rawChunks.length; i++) {
      buf.write(_rawChunks[i]);
    }
    return buf.toString();
  }

  /// Returns accumulated raw PTY bytes since the session started (capped).
  /// Used to replay history to newly-connected web guests.
  String rawHistory() {
    if (_rawChunksStart == 0 && _rawChunks.length == 1) {
      return _rawChunks.first;
    }
    final buf = StringBuffer();
    for (var i = _rawChunksStart; i < _rawChunks.length; i++) {
      buf.write(_rawChunks[i]);
    }
    return buf.toString();
  }

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
