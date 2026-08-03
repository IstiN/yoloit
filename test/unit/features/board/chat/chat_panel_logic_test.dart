import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_panel_models.dart';
import 'package:yoloit/features/board/chat/helpers/chat_panel_logic.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardPanelInstance _panel(
  String id,
  String type,
  String title, [
  Map<String, dynamic> state = const {},
]) => BoardPanelInstance(
  id: id,
  type: type,
  title: title,
  bounds: const BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
  state: state,
);

void main() {
  group('summarizePanelForYolo', () {
    test('includes title, type and id header for every panel type', () {
      final summary = summarizePanelForYolo(
        _panel('p1', 'board.chat', 'My Chat'),
      );
      expect(summary, contains('- My Chat [board.chat] (id: p1)'));
      expect(summary, contains('AI chat panel'));
    });

    test('markdown panel includes trimmed preview', () {
      final summary = summarizePanelForYolo(
        _panel('n1', 'board.note.markdown', 'Notes', {
          'markdown': '  hello world  ',
        }),
      );
      expect(summary, contains('Markdown preview:\nhello world'));
    });

    test('markdown panel truncates content longer than 500 chars', () {
      final long = 'a' * 600;
      final summary = summarizePanelForYolo(
        _panel('n1', 'board.note.markdown', 'Notes', {'markdown': long}),
      );
      expect(summary, contains('${'a' * 500}…'));
      expect(summary, isNot(contains('a' * 501)));
    });

    test('markdown panel without markdown only shows the header', () {
      final summary = summarizePanelForYolo(
        _panel('n1', 'board.note.markdown', 'Notes'),
      );
      expect(summary, '- Notes [board.note.markdown] (id: n1)');
    });

    test('kanban panel lists non-empty columns with card titles', () {
      final summary = summarizePanelForYolo(
        _panel('k1', 'board.kanban', 'Tasks', {
          'columns': ['Todo', 'Doing', 'Done'],
          'cards': [
            {'title': 'First', 'columnIndex': 0},
            {'title': '', 'columnIndex': 0}, // empty title skipped
            {'title': 'Second', 'columnIndex': 1},
            {'title': 'Orphan', 'columnIndex': 9}, // unknown column skipped
          ],
        }),
      );
      expect(summary, contains('  Todo:\n    - First'));
      expect(summary, contains('  Doing:\n    - Second'));
      // 'Done' column has no cards — skipped entirely.
      expect(summary, isNot(contains('Done:')));
      expect(summary, isNot(contains('Orphan')));
    });

    test('kanban card without columnIndex counts as first column', () {
      final summary = summarizePanelForYolo(
        _panel('k1', 'board.kanban', 'Tasks', {
          'columns': ['Todo'],
          'cards': [
            {'title': 'NoIndex'},
          ],
        }),
      );
      expect(summary, contains('  Todo:\n    - NoIndex'));
    });

    test('file preview panel shows the path when present', () {
      final withPath = summarizePanelForYolo(
        _panel('f1', 'board.file.preview', 'Preview', {'path': '/tmp/a.dart'}),
      );
      expect(withPath, contains('  File: /tmp/a.dart'));

      final withoutPath = summarizePanelForYolo(
        _panel('f1', 'board.file.preview', 'Preview'),
      );
      expect(withoutPath, isNot(contains('File:')));
    });

    test('unknown panel type lists state keys except noisy ones', () {
      final summary = summarizePanelForYolo(
        _panel('t1', 'board.terminal', 'Term', {
          'config': <String, dynamic>{},
          'messages': <dynamic>[],
          'lastUsage': <String, dynamic>{},
          'cwd': '/tmp',
          'shell': 'zsh',
        }),
      );
      expect(summary, contains('  State keys: cwd, shell'));
      expect(summary, isNot(contains('config')));
      expect(summary, isNot(contains('messages')));
    });

    test('unknown panel type without meaningful keys only shows header', () {
      final summary = summarizePanelForYolo(
        _panel('t1', 'board.terminal', 'Term', {'config': <String, dynamic>{}}),
      );
      expect(summary, '- Term [board.terminal] (id: t1)');
    });
  });

  group('injectYoloPanelContext', () {
    final board = BoardDocument(
      id: 'b1',
      name: 'Board',
      panels: [
        _panel('n1', 'board.note.markdown', 'Notes', {'markdown': 'remember'}),
        _panel('k1', 'board.kanban', 'Tasks', {
          'columns': ['Todo'],
          'cards': [
            {'title': 'Ship it', 'columnIndex': 0},
          ],
        }),
      ],
    );

    test('returns text unchanged when there are no mentions', () {
      expect(injectYoloPanelContext('hello there', board), 'hello there');
    });

    test('returns text unchanged when board is null', () {
      expect(injectYoloPanelContext('see [panel:Notes|n1]', null),
          'see [panel:Notes|n1]');
    });

    test('appends summaries for mentioned panels and strips the mention', () {
      final result = injectYoloPanelContext('check [panel:Notes|n1]', board);
      expect(result, startsWith('check\n\nReferenced board panels:\n'));
      expect(result, contains('- Notes [board.note.markdown] (id: n1)'));
      expect(result, contains('Markdown preview:\nremember'));
      expect(result, isNot(contains('[panel:')));
    });

    test('resolves multiple mentions', () {
      final result = injectYoloPanelContext(
        'compare [panel:Notes|n1] and [panel:Tasks|k1]',
        board,
      );
      expect(result, contains('- Notes [board.note.markdown] (id: n1)'));
      expect(result, contains('- Tasks [board.kanban] (id: k1)'));
      expect(result, contains('    - Ship it'));
    });

    test('skips mentions of panels that do not exist on the board', () {
      final result = injectYoloPanelContext('see [panel:Ghost|zzz]', board);
      expect(result, startsWith('see\n\nReferenced board panels:\n'));
      expect(result, isNot(contains('Ghost')));
    });

    test('strips a bare /yolo trigger prefix', () {
      final result = injectYoloPanelContext(
        '/yolo [panel:Notes|n1] what is this?',
        board,
      );
      expect(result, startsWith('what is this?\n\n'));
    });

    test('strips a bare .yolo trigger prefix', () {
      final result = injectYoloPanelContext('.yolo [panel:Notes|n1]', board);
      expect(result, startsWith('See the referenced board panels:'));
    });

    test('uses fallback prompt when only the mention remains', () {
      final result = injectYoloPanelContext('[panel:Notes|n1]', board);
      expect(result, startsWith('See the referenced board panels:'));
      expect(result, contains('- Notes [board.note.markdown] (id: n1)'));
    });
  });

  group('extractChangedFiles', () {
    test('returns empty for non-mutation tool with benign content', () {
      expect(
        extractChangedFiles(
          toolName: 'read_file',
          resultContent: 'showing /tmp/a.dart contents',
        ),
        isEmpty,
      );
    });

    test('detects mutation by tool name', () {
      for (final name in fileMutationToolNames) {
        final files = extractChangedFiles(
          toolName: ' ${name.toUpperCase()} ',
          resultContent: 'done',
        );
        expect(files, isNotNull, reason: name);
      }
      final files = extractChangedFiles(
        toolName: 'edit',
        resultContent: 'Edited /tmp/a.dart successfully',
      );
      expect(files, contains('/tmp/a.dart'));
    });

    test('detects mutation by result content markers', () {
      for (final content in [
        'created file /tmp/new.dart',
        '/tmp/x.dart updated with changes',
        'updated file /tmp/x.dart',
        'deleted file /tmp/old.dart',
      ]) {
        final files = extractChangedFiles(
          toolName: 'shell',
          resultContent: content,
        );
        expect(files, isNotEmpty, reason: content);
      }
    });

    test('extracts and cleans paths from result content', () {
      final files = extractChangedFiles(
        toolName: 'edit',
        resultContent: 'updated file /tmp/a.dart, and /tmp/b.dart. Done!',
      );
      expect(files, ['/tmp/a.dart', '/tmp/b.dart']);
    });

    test('ignores tokens that do not look like absolute paths', () {
      final files = extractChangedFiles(
        toolName: 'edit',
        resultContent: 'updated file /tmp/ok.dart (see notes)',
      );
      expect(files, ['/tmp/ok.dart']);
    });

    test('collects paths from arguments with recognised keys', () {
      final files = extractChangedFiles(
        toolName: 'write_file',
        resultContent: 'ok',
        arguments: {
          'path': '/tmp/from-path.dart',
          'content': '/tmp/not-a-path-key.dart',
          'nested': {
            'destination': '/tmp/dest.dart',
            'items': ['/tmp/listed.dart', 'relative/path.dart'],
          },
        },
      );
      expect(files, contains('/tmp/from-path.dart'));
      expect(files, contains('/tmp/dest.dart'));
      expect(files, contains('/tmp/listed.dart'));
      // 'content' is not a path key, and relative paths are rejected.
      expect(files, isNot(contains('/tmp/not-a-path-key.dart')));
      expect(files, isNot(contains('relative/path.dart')));
    });

    test('deduplicates and sorts results', () {
      final files = extractChangedFiles(
        toolName: 'edit',
        resultContent: 'updated file /tmp/b.dart then /tmp/a.dart',
        arguments: {'path': '/tmp/b.dart'},
      );
      expect(files, ['/tmp/a.dart', '/tmp/b.dart']);
    });
  });

  group('normalizePathToken', () {
    test('returns empty for empty or non-absolute input', () {
      expect(normalizePathToken(''), isEmpty);
      expect(normalizePathToken('relative/path'), isEmpty);
    });

    test('strips trailing quotes and punctuation', () {
      expect(normalizePathToken('/tmp/a.dart`'), '/tmp/a.dart');
      expect(normalizePathToken('/tmp/b.dart"'), '/tmp/b.dart');
      expect(normalizePathToken('/tmp/d.dart...'), '/tmp/d.dart');
      expect(normalizePathToken('/tmp/e.dart)'), '/tmp/e.dart');
    });

    test('returns empty when the raw token starts with a quote', () {
      // The absolute-path guard runs before quote stripping.
      expect(normalizePathToken('`/tmp/a.dart'), isEmpty);
      expect(normalizePathToken('"/tmp/b.dart'), isEmpty);
    });
  });

  group('buildAgentMarkdown', () {
    test('returns empty string for a null state', () {
      expect(buildAgentMarkdown(null), '');
    });

    test('renders header, description and running footer', () {
      final state = SubAgentRunState(
        agentId: 'a1',
        agentName: 'Researcher',
        agentDescription: 'Finds things',
      );
      final md = buildAgentMarkdown(state);
      expect(md, contains('# 🤖 Researcher'));
      expect(md, contains('> Finds things'));
      expect(md, contains('...'));
      expect(md.trimRight().endsWith('*Running…*'), isTrue);
    });

    test('omits description block when empty and marks completion', () {
      final state =
          SubAgentRunState(
              agentId: 'a1',
              agentName: 'Worker',
              agentDescription: '',
            )
            ..isRunning = false;
      final md = buildAgentMarkdown(state);
      expect(md, isNot(contains('> ')));
      expect(md, isNot(contains('...')));
      expect(md.trimRight().endsWith('*Completed.*'), isTrue);
    });

    test('renders every event type with padded timestamps', () {
      final ts = DateTime(2026, 1, 2, 3, 4, 5);
      final state = SubAgentRunState(
        agentId: 'a1',
        agentName: 'Worker',
        agentDescription: '',
      );
      state.events.addAll([
        SubAgentEvent(type: 'tool_start', toolName: 'grep', timestamp: ts),
        SubAgentEvent(
          type: 'tool_complete',
          toolName: 'grep',
          content: '3 matches',
          timestamp: ts,
        ),
        SubAgentEvent(
          type: 'tool_complete',
          toolName: 'read',
          timestamp: ts,
        ),
        SubAgentEvent(type: 'tool_error', toolName: 'edit', timestamp: ts),
        SubAgentEvent(type: 'message', content: 'thinking', timestamp: ts),
        SubAgentEvent(type: 'message', timestamp: ts),
      ]);
      final md = buildAgentMarkdown(state);
      expect(md, contains('03:04:05  ▶ grep'));
      expect(md, contains('03:04:05  ✓ grep  → 3 matches'));
      expect(md, contains('03:04:05  ✓ read\n'));
      expect(md, contains('03:04:05  ✗ edit'));
      expect(md, contains('03:04:05  » thinking'));
      expect(md, contains('03:04:05  » \n'));
    });
  });
}
