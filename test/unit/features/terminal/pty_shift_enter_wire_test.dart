// Contract test for the Shift+Enter wire — yoloit side of
// IstiN/flutter_agent_harness#77 (https://github.com/IstiN/yoloit/issues/15).
//
// Pins what a child process ACTUALLY receives through the real write path
// (TerminalBackendService.write → PtyService.write → Pty.write) when the
// terminal maps Shift+Enter:
//
//   yoloit delivers ESC CR into a PTY started with DEFAULT termios.
//   With ICRNL on (the POSIX default) the kernel line discipline rewrites
//   it to ESC LF, so the child may observe either wire:
//     ESC CR (\x1b\x0d) — raw-mode PTY / ICRNL off
//     ESC LF (\x1b\x0a) — default-termios PTY (ICRNL on)
//   Decoding BOTH wires is the terminal client's duty (fa ≥ the #77 fix
//   decodes both).
//
// Goes red if:
//   - the shortcut wire changes (e.g. someone switches to the Kitty keyboard
//     protocol CSI 13;2u — see the doc on terminalKeyEventShortcut), or
//   - the PTY layer starts forcing raw mode (stty must still report `icrnl`).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/terminal/data/pty_wrapper.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';
import 'package:yoloit/features/terminal/data/terminal_backend_service.dart';
import 'package:yoloit/features/terminal/ui/terminal_shortcuts.dart';

/// Waits until [buffer] contains [marker], returning the accumulated output.
Future<String> _waitFor(
  StringBuffer buffer,
  String marker, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final out = buffer.toString();
    if (out.contains(marker)) return out;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('Timed out waiting for "$marker". Output so far:\n${buffer.toString()}');
}

/// Text between the LAST [start] marker and the first [end] after it.
///
/// The shell echoes typed commands back (with the literal markers wrapped in
/// quotes so the echo never matches), so the last [start] is the one the
/// probe actually printed.
String _region(String output, String start, String end) {
  final from = output.lastIndexOf(start);
  expect(from, greaterThanOrEqualTo(0), reason: 'marker "$start" never printed');
  final to = output.indexOf(end, from + start.length);
  expect(to, greaterThanOrEqualTo(0), reason: 'marker "$end" never printed');
  return output.substring(from + start.length, to);
}

/// Hex byte values hex-dumped in [region] (`od -An -tx1` output).
///
/// Strips CR (ONLCR translation) and any stray ANSI CSI sequences first, so
/// terminal noise cannot inject hex-like tokens.
List<int> _hexBytes(String region) {
  final cleaned = region
      .replaceAll('\r', '')
      .replaceAll(RegExp('\x1b\\[[0-9;]*[A-Za-z]'), '');
  return RegExp('[0-9a-f]{2}')
      .allMatches(cleaned)
      .map((m) => int.parse(m.group(0)!, radix: 16))
      .toList();
}

void main() {
  // `flutter test` does not build the flutter_pty FFI framework for the host
  // tester, so route Pty.start to the pty2 backend (libc @Native — loads in
  // plain tests). Both backends implement the same Pty facade and neither
  // touches termios, so the kernel-level contract below is backend-agnostic.
  setUp(() => Pty.debugUsePty2Override = true);
  tearDown(() => Pty.debugUsePty2Override = null);

  test(
    'Shift+Enter wire through the real PTY: ESC CR, kernel may show ESC LF',
    () async {
      if (Platform.isWindows) {
        // ConPTY has no Unix termios/ICRNL; the contract below is Unix-only.
        return;
      }

      final workspace = await Directory.systemTemp.createTemp(
        'yoloit_pty_wire',
      );
      addTearDown(() => workspace.delete(recursive: true));
      const sessionId = 'shift-enter-wire-contract';

      final service = TerminalBackendService.instance;
      // Real local backend → PtyService.launch → Pty.start with default
      // termios (no raw mode) — exactly what the app does for a shell panel.
      final process = await service.launch(
        sessionId: sessionId,
        workspacePath: workspace.path,
        backendOverride: LocalPtyTerminalBackend(),
        // dumb terminal + empty prompts keep shell startup noise out of the
        // byte probe (extraEnv wins over the _buildEnv defaults).
        extraEnv: {'TERM': 'dumb', 'PS1': '', 'PS2': ''},
      );
      addTearDown(() => service.kill(sessionId));

      final output = StringBuffer();
      final sub = process.output.listen(output.write);
      addTearDown(sub.cancel);

      // 1) Drive the REAL shortcut mapping — never hardcode the wire here.
      final shortcut = terminalKeyEventShortcut(
        LogicalKeyboardKey.enter,
        isShift: true,
        isCmd: false,
        isCtrl: false,
        isAlt: false,
        awaitingApproval: false,
      );
      expect(shortcut, isA<TerminalPtyShortcut>());
      final wire = (shortcut! as TerminalPtyShortcut).sequence;
      expect(
        wire,
        '\x1b\r',
        reason: 'the Shift+Enter wire must stay ESC CR (NOT the Kitty '
            'CSI 13;2u) — clients decode the ESC CR / ESC LF pair',
      );

      // 2) Arm the byte probe BEFORE feeding the wire: `head` consumes
      //    exactly 2 bytes and `od` hex-dumps what the child received.
      //    The '' concatenation keeps the sentinel literals out of the
      //    shell's echo of the command itself.
      service.write(
        sessionId,
        "printf '__YOL_''A__'; head -c 2 | od -An -tx1; "
        "printf '__YOL_''B__'\n",
      );
      await _waitFor(output, '__YOL_A__'); // probe armed, head reads stdin

      // 3) Feed the wire under test through the REAL write path.
      service.write(sessionId, wire);

      final buffer = await _waitFor(output, '__YOL_B__');
      final bytes = _hexBytes(_region(buffer.toString(), '__YOL_A__', '__YOL_B__'));
      expect(
        bytes,
        anyOf(equals([0x1b, 0x0d]), equals([0x1b, 0x0a])),
        reason: 'the child must see ESC CR (raw/ICRNL-off PTY) or ESC LF '
            '(default-termios PTY, ICRNL on) — the two-wire contract on '
            '_shiftEnterRule; got ${bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}',
      );

      // 4) Pin DEFAULT termios: ICRNL must stay on (it is what turns the ESC
      //    CR wire into ESC LF for the child). Forcing raw mode here would
      //    silently change which wire clients observe.
      service.write(sessionId, "stty -a; printf '__YOL_''C__'\n");
      final sttyOut = await _waitFor(output, '__YOL_C__');
      final tokens = sttyOut.split(RegExp(r'[\s;]+'));
      expect(
        tokens,
        isNot(contains('-icrnl')),
        reason: 'PTY must keep default termios (ICRNL on) — forcing raw mode '
            'changes the wire the client sees; see the two-wire contract on '
            '_shiftEnterRule',
      );
      expect(tokens, contains('icrnl'));
    },
  );
}
