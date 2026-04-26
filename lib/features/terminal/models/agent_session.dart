import 'package:equatable/equatable.dart';
import 'package:xterm/xterm.dart';
import 'package:yoloit/features/terminal/data/terminal_output_bus.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

enum AgentStatus { idle, live, error }

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
  }) : terminal = Terminal(maxLines: 10000);

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

  /// Rolling plain-text buffer of recent PTY output (max 300 lines).
  /// NOT included in [props] — mutations don't trigger state rebuilds.
  final List<String> recentLines = [];

  /// Rolling buffer of RAW PTY bytes (with ANSI) — replayed to new remote
  /// guests so they see the full current terminal state, not just new data.
  /// Capped at [_maxRawBytes] to bound memory.
  final StringBuffer _rawBuffer = StringBuffer();

  static const _maxRecentLines = 300;
  static const _maxRawBytes = 256 * 1024; // 256 KiB raw ANSI history

  /// Append raw PTY data: strips ANSI codes, splits into lines, trims buffer.
  void appendOutput(String rawData) {
    final plain = stripAnsi(rawData);
    final incoming = plain.split('\n');
    recentLines.addAll(incoming);
    if (recentLines.length > _maxRecentLines) {
      recentLines.removeRange(0, recentLines.length - _maxRecentLines);
    }

    // Append raw bytes to rolling buffer (trim when over limit).
    _rawBuffer.write(rawData);
    if (_rawBuffer.length > _maxRawBytes) {
      final s = _rawBuffer.toString();
      _rawBuffer.clear();
      _rawBuffer.write(s.substring(s.length - _maxRawBytes));
    }

    // Push RAW bytes (with ANSI) so remote web guests can render via xterm.
    TerminalOutputBus.instance.write(id, rawData);
  }

  /// Returns accumulated raw PTY bytes since the session started (capped).
  /// Used to replay history to newly-connected web guests.
  String rawHistory() => _rawBuffer.toString();

  /// Last [n] non-empty plain-text lines for display in the browser.
  /// Falls back to reading the xterm buffer when the ring buffer is still empty
  /// (e.g., first snapshot right after app start with existing sessions).
  List<String> lastLines([int n = 80]) {
    if (recentLines.isNotEmpty) {
      final nonEmpty = recentLines.where((l) => l.trim().isNotEmpty).toList();
      return nonEmpty.length <= n ? nonEmpty : nonEmpty.sublist(nonEmpty.length - n);
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
