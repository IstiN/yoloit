import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

void main() {
  group('ChatMessage', () {
    group('serialization (toJson / fromJson)', () {
      test('round-trips all fields', () {
        final msg = ChatMessage(
          id: 'msg-1',
          role: ChatRole.user,
          content: 'hello world',
          timestamp: DateTime(2026, 5, 11, 12, 0, 0),
          attachments: ['/tmp/img.png', '/tmp/doc.pdf'],
        );

        final json = msg.toJson();
        final restored = ChatMessage.fromJson(json);

        expect(restored.id, msg.id);
        expect(restored.role, msg.role);
        expect(restored.content, msg.content);
        expect(restored.timestamp, msg.timestamp);
        expect(restored.attachments, msg.attachments);
      });

      test('attachments serialized when non-empty', () {
        final msg = ChatMessage(
          id: 'x',
          role: ChatRole.user,
          content: 'text',
          attachments: ['/a/b.png'],
        );
        final json = msg.toJson();
        expect(json.containsKey('attachments'), isTrue);
        expect(json['attachments'], ['/a/b.png']);
      });

      test('attachments omitted from json when empty', () {
        final msg = ChatMessage(
          id: 'x',
          role: ChatRole.user,
          content: 'text',
        );
        final json = msg.toJson();
        expect(json.containsKey('attachments'), isFalse);
      });

      test('fromJson with no attachments key returns empty list', () {
        final json = {'id': 'y', 'role': 'user', 'content': 'hi'};
        final msg = ChatMessage.fromJson(json);
        expect(msg.attachments, isEmpty);
      });

      test('fromJson with attachments key parses correctly', () {
        final json = {
          'id': 'y',
          'role': 'user',
          'content': 'hi',
          'attachments': ['/tmp/a.png', '/tmp/b.pdf'],
        };
        final msg = ChatMessage.fromJson(json);
        expect(msg.attachments, ['/tmp/a.png', '/tmp/b.pdf']);
      });
    });

    group('copyWith', () {
      final base = ChatMessage(
        id: 'base',
        role: ChatRole.assistant,
        content: 'original',
        attachments: ['/a.png'],
      );

      test('copies with new attachments', () {
        final updated = base.copyWith(attachments: ['/b.png', '/c.pdf']);
        expect(updated.attachments, ['/b.png', '/c.pdf']);
        expect(updated.id, 'base');
      });

      test('preserves attachments when not overridden', () {
        final updated = base.copyWith(content: 'new');
        expect(updated.attachments, ['/a.png']);
      });

      test('copies with empty attachments', () {
        final updated = base.copyWith(attachments: []);
        expect(updated.attachments, isEmpty);
      });
    });

    group('equality (Equatable)', () {
      test('same fields → equal', () {
        final a = ChatMessage(id: '1', role: ChatRole.user, content: 'hi');
        final b = ChatMessage(id: '1', role: ChatRole.user, content: 'hi');
        expect(a, equals(b));
      });

      test('different attachments → not equal', () {
        final a = ChatMessage(
          id: '1',
          role: ChatRole.user,
          content: 'hi',
          attachments: ['/a.png'],
        );
        final b = ChatMessage(
          id: '1',
          role: ChatRole.user,
          content: 'hi',
          attachments: ['/b.png'],
        );
        expect(a, isNot(equals(b)));
      });

      test('same attachments → equal', () {
        final a = ChatMessage(
          id: '1',
          role: ChatRole.user,
          content: 'hi',
          attachments: ['/a.png'],
        );
        final b = ChatMessage(
          id: '1',
          role: ChatRole.user,
          content: 'hi',
          attachments: ['/a.png'],
        );
        expect(a, equals(b));
      });
    });
  });

  group('_UserBubble path resolution (via _resolve logic)', () {
    // We test the pure logic extracted from _UserBubble._resolve here.
    // The actual widget test is in the widget test folder.

    final pathRe = RegExp(r'^/\S+');

    ({List<String> paths, String text}) resolve(
      String content,
      List<String> attachments,
    ) {
      final tokens = content.split(RegExp(r'\s+'));
      final inlinePaths = tokens.where((t) => pathRe.hasMatch(t)).toList();
      final textOnly =
          tokens.where((t) => !pathRe.hasMatch(t)).join(' ').trim();
      final allPaths = <String>{...attachments, ...inlinePaths}.toList();
      return (paths: allPaths, text: textOnly);
    }

    test('path at end of content is extracted', () {
      final r = resolve(
        'А что тут на картинке? /var/folders/clip.png',
        [],
      );
      expect(r.text, 'А что тут на картинке?');
      expect(r.paths, ['/var/folders/clip.png']);
    });

    test('path at start of content is extracted', () {
      final r = resolve('/var/clip.png а ты видишь картинку?', []);
      expect(r.text, 'а ты видишь картинку?');
      expect(r.paths, ['/var/clip.png']);
    });

    test('explicit attachments merged with inline paths, deduplicated', () {
      final r = resolve(
        'look at /tmp/a.png',
        ['/tmp/a.png', '/tmp/b.pdf'],
      );
      // /tmp/a.png appears in both — deduplication via Set
      expect(r.paths.length, 2);
      expect(r.paths, containsAll(['/tmp/a.png', '/tmp/b.pdf']));
    });

    test('no paths → text unchanged, empty paths', () {
      final r = resolve('just some text', []);
      expect(r.text, 'just some text');
      expect(r.paths, isEmpty);
    });

    test('multiple paths in content', () {
      final r = resolve('/a.png /b.pdf some text', []);
      expect(r.paths, containsAll(['/a.png', '/b.pdf']));
      expect(r.text, 'some text');
    });

    test('only a path in content → empty text', () {
      final r = resolve('/tmp/image.png', []);
      expect(r.text, isEmpty);
      expect(r.paths, ['/tmp/image.png']);
    });

    test('old message format: path in content, empty attachments', () {
      // Simulates message saved before the attachments field was added
      final r = resolve('check this /tmp/screenshot.png please', []);
      expect(r.text, 'check this please');
      expect(r.paths, ['/tmp/screenshot.png']);
    });
  });

  group('ChatTokenUsage', () {
    test('json round-trip', () {
      const usage = ChatTokenUsage(
        outputTokens: 75,
        premiumRequests: 1,
        totalApiDurationMs: 1200,
      );
      final restored = ChatTokenUsage.fromJson(usage.toJson());
      expect(restored.outputTokens, 75);
      expect(restored.premiumRequests, 1);
      expect(restored.totalApiDurationMs, 1200);
    });

    test('default values are zero', () {
      const usage = ChatTokenUsage();
      expect(usage.outputTokens, 0);
      expect(usage.premiumRequests, 0);
    });
  });
}
