import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// **Copilot CLI implementation** of sub-agent event tailing.
///
/// Watches `~/.copilot/session-state/<session-dir>/events.jsonl` for
/// sub-agent events emitted by the Copilot CLI process identified by [pid].
///
/// To add equivalent support for another provider (OpenCode, Cursor, etc.),
/// create a parallel class that:
///   1. Locates the provider's own event/session file for the given process.
///   2. Parses provider-specific event structures.
///   3. Emits the same [ChatEventType.subagent*] values used here.
/// Then merge the watcher stream into the provider's [sendMessage] controller
/// the same way [CopilotCliProvider] does — the [ChatPanelWidget] remains
/// provider-agnostic since it only reacts to [ChatEventType].
class SubAgentEventWatcher {
  SubAgentEventWatcher({required this.pid});

  final int pid;

  StreamController<ChatEvent>? _controller;
  Timer? _pollTimer;
  Timer? _readTimer;
  RandomAccessFile? _raf;
  StreamSubscription<FileSystemEvent>? _watchSub;
  String? _sessionDir;
  final _lineBuffer = StringBuffer();

  static const _sessionStateSubPath = '.copilot/session-state';

  /// Returns a broadcast stream of sub-agent [ChatEvent]s.
  /// Call [dispose] when the parent process exits.
  Stream<ChatEvent> get events {
    _controller = StreamController<ChatEvent>.broadcast(
      onListen: _startPollingForSession,
    );
    return _controller!.stream;
  }

  // ── Session discovery ──────────────────────────────────────────────────────

  void _startPollingForSession() {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return;

    final stateDir = Directory('$home/$_sessionStateSubPath');
    int attempts = 0;

    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) async {
      if (!(_controller?.hasListener ?? false)) {
        timer.cancel();
        return;
      }
      attempts++;
      if (attempts > 75) {
        // Give up after ~30 s
        timer.cancel();
        return;
      }

      try {
        await for (final entry in stateDir.list(followLinks: false)) {
          if (entry is Directory) {
            final lock = File('${entry.path}/inuse.$pid.lock');
            if (await lock.exists()) {
              timer.cancel();
              _sessionDir = entry.path;
              await _startWatchingEvents('${entry.path}/events.jsonl');
              return;
            }
          }
        }
      } catch (_) {}
    });
  }

  // ── Event tailing ──────────────────────────────────────────────────────────

  Future<void> _startWatchingEvents(String eventsPath) async {
    final eventsFile = File(eventsPath);

    // Wait up to 5 s for events.jsonl to appear
    for (int i = 0; i < 10; i++) {
      if (await eventsFile.exists()) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!await eventsFile.exists()) return;

    try {
      _raf = await eventsFile.open();
      // Seek to end — only new events interest us
      await _raf!.setPosition(await _raf!.length());
    } catch (_) {
      return;
    }

    // File-system watcher for change notifications
    try {
      _watchSub = eventsFile.parent
          .watch(events: FileSystemEvent.modify)
          .listen((_) => _readNewEvents());
    } catch (_) {}

    // Periodic poll as fallback (some OS watchers are unreliable)
    _readTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _readNewEvents(),
    );
  }

  Future<void> _readNewEvents() async {
    if (_raf == null) return;
    try {
      final pos = await _raf!.position();
      final len = await _raf!.length();
      if (len <= pos) return;

      final bytes = await _raf!.read(len - pos);
      final text = utf8.decode(bytes, allowMalformed: true);
      _lineBuffer.write(text);

      final content = _lineBuffer.toString();
      final lines = content.split('\n');
      _lineBuffer.clear();
      _lineBuffer.write(lines.removeLast()); // last may be incomplete

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final json = jsonDecode(trimmed) as Map<String, dynamic>;
          final event = _toSubAgentEvent(json);
          if (event != null && !(_controller?.isClosed ?? true)) {
            _controller!.add(event);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  // ── Event parsing ──────────────────────────────────────────────────────────

  ChatEvent? _toSubAgentEvent(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    final rawData = json['data'] as Map? ?? const {};
    final data = Map<String, dynamic>.from(rawData);
    final agentId = json['agentId'] as String?;
    if (agentId != null) data['agentId'] = agentId;

    final ts = DateTime.tryParse(json['timestamp'] as String? ?? '');
    final id = json['id'] as String?;
    final parentId = json['parentId'] as String?;

    switch (type) {
      case 'subagent.started':
        return ChatEvent(
          type: ChatEventType.subagentStarted,
          rawType: type,
          data: data,
          id: id,
          timestamp: ts,
          parentId: parentId,
        );

      case 'subagent.completed':
        return ChatEvent(
          type: ChatEventType.subagentCompleted,
          rawType: type,
          data: data,
          id: id,
          timestamp: ts,
          parentId: parentId,
        );

      case 'tool.execution_start':
        // Only sub-agent tool calls have parentToolCallId
        if (!data.containsKey('parentToolCallId')) return null;
        return ChatEvent(
          type: ChatEventType.subagentToolStart,
          rawType: type,
          data: data,
          id: id,
          timestamp: ts,
          parentId: parentId,
        );

      case 'tool.execution_complete':
        if (!data.containsKey('parentToolCallId')) return null;
        return ChatEvent(
          type: ChatEventType.subagentToolComplete,
          rawType: type,
          data: data,
          id: id,
          timestamp: ts,
          parentId: parentId,
        );

      case 'assistant.message':
        // Sub-agent assistant messages have an agentId on the top-level JSON
        if (agentId == null) return null;
        return ChatEvent(
          type: ChatEventType.subagentMessage,
          rawType: type,
          data: data,
          id: id,
          timestamp: ts,
          parentId: parentId,
        );

      default:
        return null;
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _pollTimer?.cancel();
    _readTimer?.cancel();
    await _watchSub?.cancel();
    try {
      await _raf?.close();
    } catch (_) {}
    _raf = null;
    if (!(_controller?.isClosed ?? true)) {
      await _controller?.close();
    }
    debugPrint('[SubAgentWatcher] disposed (pid=$pid, session=$_sessionDir)');
  }
}
