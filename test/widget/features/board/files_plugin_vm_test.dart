import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/files_plugin_vm.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';

void main() {
  const plugin = FilesPlugin();

  tearDown(() {
    FilesPlugin.debugPickFiles = null;
  });

  test('typeId is board.files', () {
    expect(plugin.typeId, 'board.files');
    expect(plugin.initialState['files'], isA<List<dynamic>>());
  });

  group('add files', () {
    Future<_FilesHarness> pumpFiles(
      WidgetTester tester, {
      List<Map<String, dynamic>>? files,
    }) async {
      final harness = _FilesHarness({'files': files ?? <Map<String, dynamic>>[]});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 320,
              child: _FilesHost(harness: harness),
            ),
          ),
        ),
      );
      await tester.pump();
      return harness;
    }

    List<Map<String, dynamic>> filesOf(_FilesHarness harness) {
      return (harness.state['files'] as List).cast<Map<String, dynamic>>();
    }

    testWidgets('shows an empty-state placeholder without files', (
      tester,
    ) async {
      await pumpFiles(tester);
      expect(find.text('No files added yet'), findsOneWidget);
      expect(find.text('0 files'), findsOneWidget);
    });

    testWidgets('a cancelled picker leaves the list untouched', (tester) async {
      final harness = await pumpFiles(tester);
      FilesPlugin.debugPickFiles = (_) async => null;

      await tester.tap(find.text('Add Files'));
      await tester.pump();
      await tester.pump();

      expect(filesOf(harness), isEmpty);
      expect(find.text('No files added yet'), findsOneWidget);
    });

    testWidgets('an empty picker result leaves the list untouched', (
      tester,
    ) async {
      final harness = await pumpFiles(tester);
      FilesPlugin.debugPickFiles = (_) async => <BoardFileSelection>[];

      await tester.tap(find.text('Add Files'));
      await tester.pump();
      await tester.pump();

      expect(filesOf(harness), isEmpty);
    });

    testWidgets('deduplicates paths and stores new entries', (tester) async {
      final harness = await pumpFiles(
        tester,
        files: [
          {'id': 'existing', 'path': '/tmp/a.txt', 'name': 'a.txt'},
        ],
      );
      FilesPlugin.debugPickFiles =
          (_) async => const [
            BoardFileSelection(path: '/tmp/a.txt', name: 'a.txt'),
            BoardFileSelection(path: '/tmp/b.png', name: 'b.png'),
          ];

      await tester.tap(find.text('Add Files'));
      await tester.pump();
      await tester.pump();

      final files = filesOf(harness);
      expect(files, hasLength(2));
      expect(files.map((f) => f['path']), ['/tmp/a.txt', '/tmp/b.png']);
      expect(files.last['name'], 'b.png');
      expect(files.last['addedAt'], isA<String>());

      expect(find.text('2 files'), findsOneWidget);
      expect(find.text('b.png'), findsOneWidget);
    });

    testWidgets('a picker with only duplicates is a no-op', (tester) async {
      final harness = await pumpFiles(
        tester,
        files: [
          {'id': 'existing', 'path': '/tmp/a.txt', 'name': 'a.txt'},
        ],
      );
      FilesPlugin.debugPickFiles =
          (_) async => const [
            BoardFileSelection(path: '/tmp/a.txt', name: 'a.txt'),
          ];

      await tester.tap(find.text('Add Files'));
      await tester.pump();
      await tester.pump();

      expect(filesOf(harness), hasLength(1));
      expect(filesOf(harness).single['id'], 'existing');
    });
  });
}

class _FilesHarness {
  _FilesHarness(this.state);

  Map<String, dynamic> state;
}

class _FilesHost extends StatefulWidget {
  const _FilesHost({required this.harness});

  final _FilesHarness harness;

  @override
  State<_FilesHost> createState() => _FilesHostState();
}

class _FilesHostState extends State<_FilesHost> {
  @override
  Widget build(BuildContext context) {
    final panel = BoardPanelInstance(
      id: 'files-1',
      type: 'board.files',
      title: 'Files',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 360, height: 320),
      state: widget.harness.state,
    );
    return const FilesPlugin().buildContent(
      context,
      panel,
      BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onShowEditor: () {},
        onUpdateState: (next) {
          setState(() => widget.harness.state = next);
        },
      ),
    );
  }
}
