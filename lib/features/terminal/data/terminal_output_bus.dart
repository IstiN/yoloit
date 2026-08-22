import 'dart:async';

/// Singleton bus that carries raw PTY output for all terminal sessions.
/// CollaborationCubit subscribes to this to stream terminal data to browser guests.
class TerminalOutputBus {
  TerminalOutputBus._();
  static final instance = TerminalOutputBus._();

  /// (sessionId, rawData) pairs. rawData contains raw PTY bytes with ANSI
  /// sequences intact — web guests pipe this into their xterm Terminal.
  final StreamController<(String, String)> _ctrl =
      StreamController.broadcast();

  Stream<(String, String)> get stream => _ctrl.stream;

  void write(String sessionId, String data) {
    if (!_ctrl.isClosed) _ctrl.add((sessionId, data));
  }

  void dispose() => _ctrl.close();
}

// Patterns are compiled once: stripAnsi runs on every batched PTY flush
// (~20 times/sec per active session), and constructing RegExp objects on
// each call showed up as allocation churn feeding the concurrent GC marker.
final _csiPattern = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
final _oscPattern = RegExp(r'\x1B\].*?(?:\x07|\x1B\\)');
final _charsetPattern = RegExp(r'\x1B[()* +][A-Za-z0-9]');
final _fePattern = RegExp(r'\x1B[@-Z\\-_]');
final _loneEscPattern = RegExp(r'\x1B[^\x1B\n]?');

// Strips ANSI/VT100 escape sequences including CSI, OSC, character-set
// designations (ESC ( B etc.) and two-byte Fe sequences.
String stripAnsi(String s) {
  // Fast path: no ESC byte at all — return the input untouched.
  if (!s.contains('\x1B')) return s;
  return s
      // CSI sequences: ESC [ ... final-byte
      .replaceAll(_csiPattern, '')
      // OSC sequences: ESC ] ... ST  (ST = BEL or ESC \)
      .replaceAll(_oscPattern, '')
      // Character-set designations: ESC ( X  ESC ) X  ESC * X  ESC + X
      .replaceAll(_charsetPattern, '')
      // Two-byte Fe sequences: ESC followed by 0x40–0x5F (except [, ], etc.)
      .replaceAll(_fePattern, '')
      // Catch-all: any remaining lone ESC followed by a non-space printable char
      .replaceAll(_loneEscPattern, '');
}
