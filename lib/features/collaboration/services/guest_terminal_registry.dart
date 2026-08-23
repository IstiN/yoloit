import 'package:yoxterm/xterm.dart';

/// Guest-side registry of live xterm [Terminal] instances keyed by agent-node id.
///
/// When the host streams raw PTY bytes over the `terminal.output` sync message,
/// the guest writes them to the corresponding [Terminal] here. The agent card
/// widget renders via [TerminalView] bound to this terminal so the guest gets
/// proper ANSI colors, box-drawing, scrollback and cursor handling — exactly
/// like the native client.
class GuestTerminalRegistry {
  GuestTerminalRegistry._();
  static final instance = GuestTerminalRegistry._();

  final Map<String, Terminal> _terminals = {};
  final Map<String, List<String>> _pendingWrites = {};
  final Map<String, void Function(String)> _inputHandlers = {};

  /// Get or create the [Terminal] for a given node id. Creates a terminal
  /// with generous scrollback (10k lines) to match the native experience.
  Terminal terminalFor(String nodeId) {
    final existing = _terminals[nodeId];
    if (existing != null) return existing;

    final t = Terminal(maxLines: 10000);
    // Route user keystrokes back to the host.
    t.onOutput = (data) {
      final handler = _inputHandlers[nodeId];
      if (handler != null) handler(data);
    };
    _terminals[nodeId] = t;

    // Flush any bytes that arrived before the terminal was built.
    final pending = _pendingWrites.remove(nodeId);
    if (pending != null) {
      for (final chunk in pending) {
        t.write(chunk);
      }
    }
    return t;
  }

  /// Feed raw PTY bytes (with ANSI escapes intact) to the terminal for [nodeId].
  /// If the terminal hasn't been built yet (card not mounted), buffer the data.
  void writeOutput(String nodeId, String data) {
    final t = _terminals[nodeId];
    if (t != null) {
      t.write(data);
    } else {
      (_pendingWrites[nodeId] ??= []).add(data);
      // Cap buffered data to avoid unbounded memory growth.
      final buf = _pendingWrites[nodeId]!;
      if (buf.length > 200) buf.removeRange(0, buf.length - 200);
    }
  }

  /// Register an input callback for a terminal node. Called with the raw
  /// key sequence produced by xterm (e.g. "\r" for Enter, "\x1b[A" for Up).
  void setInputHandler(String nodeId, void Function(String) handler) {
    _inputHandlers[nodeId] = handler;
  }

  void removeInputHandler(String nodeId) {
    _inputHandlers.remove(nodeId);
  }

  /// Dispose a terminal when its node is removed from the canvas.
  void dispose(String nodeId) {
    _terminals.remove(nodeId);
    _pendingWrites.remove(nodeId);
    _inputHandlers.remove(nodeId);
  }

  void clear() {
    _terminals.clear();
    _pendingWrites.clear();
    _inputHandlers.clear();
  }
}
