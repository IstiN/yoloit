import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

void main() {
  group('AgentSession raw output buffer', () {
    AgentSession newSession() => AgentSession(
      id: 's1',
      type: AgentType.terminal,
      workspacePath: '/tmp',
    );

    test('rawHistory returns appended data verbatim', () {
      final s = newSession();
      s.appendOutput('hello ');
      s.appendOutput('world');
      expect(s.rawHistory(), 'hello world');
    });

    test('caps raw history at 256 KiB keeping the tail', () {
      final s = newSession();
      // 300 KiB in 1 KiB chunks — 44 KiB must be dropped from the front.
      final chunk = 'x' * 1024;
      for (var i = 0; i < 300; i++) {
        s.appendOutput(chunk);
      }
      final history = s.rawHistory();
      expect(history.length, lessThanOrEqualTo(256 * 1024));
      expect(history.endsWith(chunk), isTrue);
    });

    test('rawHistory stays correct across repeated trim/compaction cycles', () {
      final s = newSession();
      // Push well past the 512-chunk compaction threshold while staying
      // under the byte cap per cycle.
      for (var i = 0; i < 2000; i++) {
        s.appendOutput('line-$i\n');
      }
      expect(s.rawHistory(), contains('line-1999\n'));
    });

    test('recentLines keeps only the last 300 lines', () {
      final s = newSession();
      final big = List.generate(400, (i) => 'l$i').join('\n');
      s.appendOutput(big);
      expect(s.recentLines.length, 300);
      expect(s.recentLines.last, 'l399');
    });

    test('strips ANSI from recentLines but keeps raw history intact', () {
      final s = newSession();
      s.appendOutput('\x1b[32mgreen\x1b[0m\n');
      expect(s.recentLines, ['green', '']);
      expect(s.rawHistory(), '\x1b[32mgreen\x1b[0m\n');
    });
  });

  group('AgentSession lazy historyText (bytes-based storage)', () {
    AgentSession newSession() => AgentSession(
      id: 'lazy',
      type: AgentType.terminal,
      workspacePath: '/tmp',
    );

    test(
      'historyText after appendOutputChunksBytes round-trips ASCII bytes',
      () {
        final s = newSession();
        s.appendOutputChunksBytes([
          Uint8List.fromList(utf8.encode('hello ')),
          Uint8List.fromList(utf8.encode('world')),
        ]);
        // Round-trip: historyText == utf8.decode(joined, allowMalformed: true)
        final joined = Uint8List.fromList([
          ...utf8.encode('hello '),
          ...utf8.encode('world'),
        ]);
        expect(s.historyText, 'hello world');
        expect(s.historyText, utf8.decode(joined, allowMalformed: true));
      },
    );

    test(
      'historyText shows U+FFFD at multibyte split across two appends '
      '(matches old per-flush semantics)',
      () {
        final s = newSession();
        // 'é' = 0xC3 0xA9, split across two appends. Each stored chunk
        // decodes independently with allowMalformed, so the lead byte and
        // tail byte both render as U+FFFD — same semantics the old
        // per-flush code had.
        s.appendOutputChunksBytes([Uint8List.fromList([0x61, 0xC3])]); // 'a'+lead
        s.appendOutputChunksBytes([Uint8List.fromList([0xA9, 0x62])]); // tail+'b'
        expect(s.historyText, 'a\uFFFD\uFFFDb');
      },
    );

    test('historyText is computed lazily — cache holds across reads', () {
      final s = newSession();
      var decodeCalls = 0;
      s.utf8DecodeSpyForTesting = (_) => decodeCalls++;

      s.appendOutputChunksBytes([Uint8List.fromList(utf8.encode('first '))]);
      s.appendOutputChunksBytes([Uint8List.fromList(utf8.encode('batch'))]);

      final afterAppends = decodeCalls;
      expect(afterAppends, 0); // appends must NOT decode

      // First read: triggers one decode per stored chunk.
      expect(s.historyText, 'first batch');
      final firstReadCalls = decodeCalls;
      expect(firstReadCalls, greaterThan(0));

      // Subsequent reads with no new appends reuse the cached String —
      // zero additional decode calls.
      expect(s.historyText, 'first batch');
      expect(s.historyText, 'first batch');
      expect(decodeCalls, firstReadCalls);

      // A new append invalidates the cache; the next read re-decodes.
      s.appendOutputChunksBytes([Uint8List.fromList(utf8.encode(' second'))]);
      expect(s.historyText, 'first batch second');
      expect(decodeCalls, greaterThan(firstReadCalls));
    });

    test('historyText invalidates cache on String append too', () {
      final s = newSession();
      var decodeCalls = 0;
      s.utf8DecodeSpyForTesting = (_) => decodeCalls++;

      s.appendOutput('abc');
      expect(decodeCalls, 0);
      expect(s.historyText, 'abc');
      final firstReadCalls = decodeCalls;
      expect(s.historyText, 'abc');
      expect(decodeCalls, firstReadCalls); // no re-decode while cached

      // A new String-via-appendOutput invalidates the cache; the next read
      // re-decodes.
      s.appendOutput('def');
      expect(s.historyText, 'abcdef');
      final secondReadCalls = decodeCalls;
      expect(secondReadCalls, greaterThan(firstReadCalls));
    });

    test(
      'appendOutput(String) and appendOutputChunksBytes(round-trip) history is '
      'identical to all-string appendOutput for plain ASCII',
      () {
        final stringOnly = newSession();
        final bytesOnly = newSession();
        stringOnly.appendOutput('hello ');
        stringOnly.appendOutput('world');
        bytesOnly.appendOutputChunksBytes([
          Uint8List.fromList(utf8.encode('hello ')),
          Uint8List.fromList(utf8.encode('world')),
        ]);
        expect(stringOnly.rawHistory(), bytesOnly.rawHistory());
      },
    );

    test('appendOutputChunksBytes stores bytes without decoding per append',
        () {
      final s = newSession();
      var decodeCalls = 0;
      s.utf8DecodeSpyForTesting = (_) => decodeCalls++;

      // 100 appends, none of which should trigger utf8.decode on the
      // streaming hot path.
      for (var i = 0; i < 100; i++) {
        s.appendOutputChunksBytes([
          Uint8List.fromList(utf8.encode('chunk$i ')),
        ]);
      }
      expect(decodeCalls, 0);

      // The first read decodes all stored chunks once; subsequent reads
      // reuse the cache without additional decodes.
      final h = s.historyText;
      final firstReadCalls = decodeCalls;
      expect(firstReadCalls, greaterThan(0));
      expect(s.historyText, same(h));
      expect(decodeCalls, firstReadCalls); // cache hit
      expect(h.endsWith('chunk99 '), isTrue);
    });

    test('rawHistory() returns text equivalent to historyText', () {
      final s = newSession();
      s.appendOutputChunksBytes([
        Uint8List.fromList([0xC3, 0xA9]), // 'é'
        Uint8List.fromList(utf8.encode(' ok')),
      ]);
      expect(s.rawHistory(), s.historyText);
    });
  });
}
