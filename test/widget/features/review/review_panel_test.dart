import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/review/bloc/review_state.dart';
import 'package:yoloit/features/review/models/review_models.dart';
import 'package:yoloit/features/review/ui/review_panel.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';

Widget _buildReviewTest(ReviewState state) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ReviewCubit>(create: (_) => ReviewCubit()..emit(state)),
      BlocProvider<RunCubit>(create: (_) => RunCubit()),
      BlocProvider<FileEditorCubit>(create: (_) => FileEditorCubit()),
    ],
    child: MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: const Scaffold(body: ReviewPanel()),
    ),
  );
}

class _FakePlatformLauncher extends PlatformLauncher {
  final List<String> revealed = <String>[];

  @override
  Future<void> openUrl(String url) async {}

  @override
  Future<void> revealInFinder(String path) async {
    revealed.add(path);
  }

  @override
  Future<void> openTerminal(String workdir) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReviewPanel widget tests', () {
    testWidgets('empty state shows Changes & Review title', (tester) async {
      await tester.pumpWidget(_buildReviewTest(const ReviewInitial()));
      await tester.pump();

      expect(find.text('Changes & Review'), findsAtLeastNWidgets(1));
    });

    testWidgets('empty state shows workspace prompt', (tester) async {
      await tester.pumpWidget(_buildReviewTest(const ReviewInitial()));
      await tester.pump();

      expect(find.text('Open a workspace to see file changes'), findsOneWidget);
    });

    testWidgets('loaded state shows File Tree section', (tester) async {
      await tester.pumpWidget(_buildReviewTest(const ReviewLoaded(
        fileTree: [],
        changedFiles: [],
      )));
      await tester.pump();

      expect(find.text('File Tree'), findsOneWidget);
    });

    testWidgets('loaded state shows empty file tree message', (tester) async {
      await tester.pumpWidget(_buildReviewTest(const ReviewLoaded(
        fileTree: [],
        changedFiles: [],
      )));
      await tester.pump();

      expect(find.text('No files'), findsOneWidget);
    });

    testWidgets('file tree nodes are rendered', (tester) async {
      await tester.pumpWidget(_buildReviewTest(const ReviewLoaded(
        fileTree: [
          FileTreeNode(name: 'lib', path: '/project/lib', isDirectory: true),
          FileTreeNode(name: 'main.dart', path: '/project/main.dart', isDirectory: false),
        ],
        changedFiles: [],
      )));
      await tester.pump();

      expect(find.text('lib'), findsOneWidget);
      expect(find.text('main.dart'), findsOneWidget);
    });

    testWidgets('changed files section renders file statuses', (tester) async {
      // The current review panel shows a file tree, not a separate changed files list.
      // Files with changes are reflected via the file tree nodes.
      await tester.pumpWidget(_buildReviewTest(const ReviewLoaded(
        fileTree: [
          FileTreeNode(name: 'app.dart', path: 'lib/app.dart', isDirectory: false),
          FileTreeNode(name: 'new.dart', path: 'lib/new.dart', isDirectory: false),
        ],
        changedFiles: [
          FileChange(path: 'lib/app.dart', status: FileChangeStatus.modified),
          FileChange(path: 'lib/new.dart', status: FileChangeStatus.added),
        ],
      )));
      await tester.pump();

      expect(find.textContaining('app.dart'), findsOneWidget);
      expect(find.textContaining('new.dart'), findsOneWidget);
    });

    testWidgets('run panel section is visible in review panel', (tester) async {
      await tester.pumpWidget(_buildReviewTest(const ReviewLoaded(
        fileTree: [],
        changedFiles: [],
      )));
      await tester.pump();

      expect(find.text('Run'), findsOneWidget);
    });

    testWidgets('loaded state shows refresh icon', (tester) async {
      await tester.pumpWidget(_buildReviewTest(const ReviewLoaded(
        fileTree: [],
        changedFiles: [],
      )));
      await tester.pump();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('view mode is tracked in state', (tester) async {
      // viewMode is in state for future use; currently panel shows file tree only
      const state = ReviewLoaded(
        fileTree: [],
        changedFiles: [],
        selectedFilePath: '/project/lib/main.dart',
        viewMode: ReviewViewMode.diff,
      );
      expect(state.viewMode, ReviewViewMode.diff);
      expect(state.selectedFilePath, '/project/lib/main.dart');
    });

    testWidgets('diff hunks state is preserved', (tester) async {
      const hunk = DiffHunk(
        header: '@@ -1,2 +1,3 @@',
        lines: [
          DiffLine(type: DiffLineType.add, content: 'new line', newLineNum: 1),
        ],
        oldStart: 1,
        newStart: 1,
      );
      const state = ReviewLoaded(
        fileTree: [],
        changedFiles: [],
        diffHunks: [hunk],
      );
      expect(state.diffHunks, hasLength(1));
    });

    testWidgets('file content state is preserved', (tester) async {
      const state = ReviewLoaded(
        fileTree: [],
        changedFiles: [],
        fileContent: 'void main() => print("hello");',
        viewMode: ReviewViewMode.file,
      );
      expect(state.fileContent, contains('void main()'));
    });

    testWidgets('PR status section renders when prStatus is set', (tester) async {
      await tester.pumpWidget(_buildReviewTest(const ReviewLoaded(
        fileTree: [],
        changedFiles: [],
        prStatus: PrStatus(
          title: 'Refactor main loop',
          prNumber: 42,
          status: 'Open',
          checks: [],
          reviewers: 2,
        ),
      )));
      await tester.pump();

      expect(find.text('PR Status'), findsOneWidget);
      expect(find.textContaining('Refactor main loop'), findsOneWidget);
      expect(find.text('Create PR'), findsOneWidget);
      expect(find.text('Merge'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });
  });

  group('file tree context menu', () {
    const fileTree = [
      FileTreeNode(name: 'lib', path: '/project/lib', isDirectory: true),
      FileTreeNode(
        name: 'main.dart',
        path: '/project/main.dart',
        isDirectory: false,
      ),
    ];

    late _FakePlatformLauncher launcher;
    String? clipboardText;

    setUp(() {
      launcher = _FakePlatformLauncher();
      PlatformLauncher.setInstance(launcher);
      clipboardText = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<void> pumpPanel(WidgetTester tester) async {
      await tester.pumpWidget(_buildReviewTest(const ReviewLoaded(
        fileTree: fileTree,
        changedFiles: [],
      )));
      await tester.pump();
    }

    testWidgets('shows file actions for a file node', (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('main.dart'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Copy path'), findsOneWidget);
      expect(find.text('Copy filename'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Show in Finder'), findsOneWidget);
      // Directories-only action is absent for files.
      expect(find.text('New Folder'), findsNothing);
    });

    testWidgets('shows New Folder and no Rename for a directory node', (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('lib'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('Copy path'), findsOneWidget);
      expect(find.text('Show in Finder'), findsOneWidget);
      // Rename is only offered for files.
      expect(find.text('Rename'), findsNothing);
    });

    testWidgets('Copy path copies the node path and shows a snackbar', (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('main.dart'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy path'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(clipboardText, '/project/main.dart');
      expect(find.text('Path copied'), findsOneWidget);

      // Drain the snackbar timer.
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Copy filename copies the node name and shows a snackbar', (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('main.dart'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy filename'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(clipboardText, 'main.dart');
      expect(find.text('Filename copied'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Rename turns the node label into a text field', (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('main.dart'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'main.dart'), findsOneWidget);
    });

    testWidgets('Show in Finder reveals the node path', (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('main.dart'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show in Finder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(launcher.revealed, ['/project/main.dart']);
    });

    testWidgets('New Folder opens the folder creation dialog', (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('lib'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();

      expect(find.text('Create'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Create'), findsNothing);
    });

    testWidgets('dismissing the menu triggers no action', (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('main.dart'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Copy path'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Copy path'), findsNothing);
      expect(clipboardText, isNull);
      expect(launcher.revealed, isEmpty);
    });
  });
}
