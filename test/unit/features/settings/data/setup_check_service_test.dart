import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/settings/data/setup_check_service.dart';

void main() {
  group('SetupCheckService.mergePathForTest', () {
    test('prepends new candidates before existing paths', () {
      final result = SetupCheckService.mergePathForTest(
        '/usr/bin:/bin',
        ['/opt/homebrew/bin', '/usr/local/bin'],
        ':',
      );
      expect(
        result,
        '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin',
      );
    });

    test('does not duplicate existing paths', () {
      final result = SetupCheckService.mergePathForTest(
        '/usr/local/bin:/usr/bin:/bin',
        ['/usr/local/bin', '/opt/bin'],
        ':',
      );
      expect(
        result,
        '/opt/bin:/usr/local/bin:/usr/bin:/bin',
      );
    });

    test('handles empty current path', () {
      final result = SetupCheckService.mergePathForTest(
        '',
        ['/usr/bin', '/bin'],
        ':',
      );
      expect(result, '/usr/bin:/bin');
    });

    test('handles empty candidates', () {
      final result = SetupCheckService.mergePathForTest(
        '/usr/bin:/bin',
        <String>[],
        ':',
      );
      expect(result, '/usr/bin:/bin');
    });

    test('uses semicolon separator on Windows', () {
      final result = SetupCheckService.mergePathForTest(
        r'C:\Windows;C:\Program Files',
        [r'C:\Tools', r'C:\Windows'],
        ';',
      );
      expect(
        result,
        r'C:\Tools;C:\Windows;C:\Program Files',
      );
    });

    test('filters out empty segments', () {
      final result = SetupCheckService.mergePathForTest(
        ':/usr/bin::/bin:',
        ['/opt/bin'],
        ':',
      );
      expect(
        result,
        '/opt/bin:/usr/bin:/bin',
      );
    });
  });

  group('SetupCheckService.extractOutputForTest', () {
    test('returns output when exit code is 0 and output is non-empty', () {
      final result = SetupCheckService.extractOutputForTest(
        ProcessResult(0, 0, '/usr/bin/git\n', ''),
      );
      expect(result, '/usr/bin/git');
    });

    test('returns null when exit code is non-zero', () {
      final result = SetupCheckService.extractOutputForTest(
        ProcessResult(0, 1, '/usr/bin/git\n', ''),
      );
      expect(result, isNull);
    });

    test('returns null when output is empty', () {
      final result = SetupCheckService.extractOutputForTest(
        ProcessResult(0, 0, '', ''),
      );
      expect(result, isNull);
    });

    test('trims whitespace from output', () {
      final result = SetupCheckService.extractOutputForTest(
        ProcessResult(0, 0, '  /usr/bin/git  \n', ''),
      );
      expect(result, '/usr/bin/git');
    });

    test('takes first line when multiple lines', () {
      final result = SetupCheckService.extractOutputForTest(
        ProcessResult(0, 0, '/first\n/second\n', ''),
      );
      expect(result, '/first');
    });
  });

  group('SetupCheckService.cleanVersionForTest', () {
    test('extracts semantic version from string', () {
      expect(
        SetupCheckService.cleanVersionForTest('git version 2.39.0'),
        '2.39.0',
      );
    });

    test('extracts version with patch', () {
      expect(
        SetupCheckService.cleanVersionForTest('node v18.17.1'),
        '18.17.1',
      );
    });

    test('extracts version with more segments', () {
      expect(
        SetupCheckService.cleanVersionForTest('tool 1.2.3.4'),
        '1.2.3.4',
      );
    });

    test('returns raw string when no version found', () {
      expect(
        SetupCheckService.cleanVersionForTest('some text without numbers'),
        'some text without numbers',
      );
    });

    test('truncates long raw strings to 40 chars', () {
      final longString = 'a' * 100;
      expect(
        SetupCheckService.cleanVersionForTest(longString),
        'a' * 40,
      );
    });

    test('does not truncate version match even if long', () {
      expect(
        SetupCheckService.cleanVersionForTest('version 1.2.3.4.5.6.7.8.9.10'),
        '1.2.3.4.5.6.7.8.9.10',
      );
    });

    test('extracts version from stderr-style output', () {
      expect(
        SetupCheckService.cleanVersionForTest('tmux 3.3a'),
        '3.3',
      );
    });

    test('handles version at start of string', () {
      expect(
        SetupCheckService.cleanVersionForTest('2.40.1 (Apple Git-143)'),
        '2.40.1',
      );
    });
  });
}
