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
}
