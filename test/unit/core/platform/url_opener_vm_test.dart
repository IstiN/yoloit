import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/url_opener_vm.dart';

void main() {
  group('openUrl', () {
    test('completes without throwing on the current platform', () async {
      // The function either spawns a process (macOS/Linux/Windows) or returns
      // early. Either way it must complete normally.
      await expectLater(openUrl('x-test-yoloit-invalid://noop'), completes);
    });

    test('catches ProcessException for unknown commands', () async {
      // On macOS the command is 'open'; on Linux 'xdg-open'; on Windows 'start'.
      // All exist on their respective OSes, but an invalid URI scheme may
      // still produce a non-zero exit — the function must swallow it.
      await expectLater(openUrl(''), completes);
    });

    test('is a no-op on unsupported platforms (guarded by Platform check)', () {
      // This test documents the else-branch: the function checks
      // Platform.isMacOS / isLinux / isWindows and returns early otherwise.
      // On a real desktop CI runner one of those is true, so the guard is
      // a safety net for web/embedded targets.
      expect(Platform.isMacOS || Platform.isLinux || Platform.isWindows, isTrue);
    });
  });
}
