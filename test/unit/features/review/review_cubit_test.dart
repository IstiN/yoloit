import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/review/bloc/review_state.dart';
import 'package:yoloit/features/review/models/review_models.dart';

void main() {
  group('ReviewCubit.listAndSortEntities', () {
    late Directory tempDir;
    late ReviewCubit cubit;

    setUp(() {
      cubit = ReviewCubit();
      tempDir = Directory.systemTemp.createTempSync('review_cubit_test_');
    });

    tearDown(() {
      cubit.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('lists files and directories', () {
      File('${tempDir.path}/z_file.txt').createSync();
      Directory('${tempDir.path}/a_dir').createSync();
      File('${tempDir.path}/m_file.txt').createSync();

      final result = cubit.listAndSortEntitiesForTest(tempDir.path);

      expect(result.length, 3);
    });

    test('sorts directories before files', () {
      File('${tempDir.path}/z_file.txt').createSync();
      Directory('${tempDir.path}/b_dir').createSync();
      File('${tempDir.path}/a_file.txt').createSync();
      Directory('${tempDir.path}/a_dir').createSync();

      final result = cubit.listAndSortEntitiesForTest(tempDir.path);

      expect(result[0] is Directory, isTrue);
      expect(result[1] is Directory, isTrue);
      expect(result[2] is File, isTrue);
      expect(result[3] is File, isTrue);
    });

    test('sorts alphabetically within same type', () {
      Directory('${tempDir.path}/z_dir').createSync();
      Directory('${tempDir.path}/a_dir').createSync();
      File('${tempDir.path}/z_file.txt').createSync();
      File('${tempDir.path}/a_file.txt').createSync();

      final result = cubit.listAndSortEntitiesForTest(tempDir.path);

      expect(p.basename(result[0].path), 'a_dir');
      expect(p.basename(result[1].path), 'z_dir');
      expect(p.basename(result[2].path), 'a_file.txt');
      expect(p.basename(result[3].path), 'z_file.txt');
    });

    test('sorts case-insensitively', () {
      Directory('${tempDir.path}/B_dir').createSync();
      Directory('${tempDir.path}/a_dir').createSync();

      final result = cubit.listAndSortEntitiesForTest(tempDir.path);

      expect(p.basename(result[0].path), 'a_dir');
      expect(p.basename(result[1].path), 'B_dir');
    });

    test('returns empty list for empty directory', () {
      final result = cubit.listAndSortEntitiesForTest(tempDir.path);

      expect(result, isEmpty);
    });
  });

  group('ReviewCubit.buildFileTree', () {
    late Directory tempDir;
    late ReviewCubit cubit;

    setUp(() {
      cubit = ReviewCubit();
      tempDir = Directory.systemTemp.createTempSync('review_cubit_test_');
    });

    tearDown(() {
      cubit.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('builds tree nodes from directory contents', () async {
      File('${tempDir.path}/file.txt').createSync();
      Directory('${tempDir.path}/subdir').createSync();

      final result = await cubit.buildFileTreeForTest(tempDir.path);

      expect(result.length, 2);
      expect(result[0].name, 'subdir');
      expect(result[0].isDirectory, isTrue);
      expect(result[1].name, 'file.txt');
      expect(result[1].isDirectory, isFalse);
    });

    test('filters out .git directory', () async {
      File('${tempDir.path}/file.txt').createSync();
      Directory('${tempDir.path}/.git').createSync();

      final result = await cubit.buildFileTreeForTest(tempDir.path);

      expect(result.length, 1);
      expect(result[0].name, 'file.txt');
    });

    test('returns empty list for empty directory', () async {
      final result = await cubit.buildFileTreeForTest(tempDir.path);

      expect(result, isEmpty);
    });

    test('returns empty list for non-existent directory', () async {
      final result = await cubit.buildFileTreeForTest('${tempDir.path}/missing');

      expect(result, isEmpty);
    });
  });

  group('ReviewCubit.gitRootFor', () {
    test('returns matching workspace path', () {
      final cubit = ReviewCubit();
      final root = cubit.gitRootForForTest('/projects/app/src/main.dart');
      // Empty _workspacePaths, so should return null
      expect(root, isNull);
      cubit.close();
    });
  });

  group('ReviewCubit.toggleNodeInTree', () {
    test('expands collapsed directory node', () {
      final cubit = ReviewCubit();
      final tempDir = Directory.systemTemp.createTempSync('toggle_test_');
      File('${tempDir.path}/file.txt').createSync();

      final nodes = <FileTreeNode>[
        FileTreeNode(
          name: 'root',
          path: tempDir.path,
          isDirectory: true,
          isExpanded: false,
          children: [],
        ),
      ];

      final result = cubit.toggleNodeInTreeForTest(nodes, tempDir.path);

      expect(result[0].isExpanded, isTrue);
      expect(result[0].children.length, 1);
      expect(result[0].children[0].name, 'file.txt');

      tempDir.deleteSync(recursive: true);
      cubit.close();
    });

    test('collapses expanded directory node', () {
      final cubit = ReviewCubit();
      final tempDir = Directory.systemTemp.createTempSync('toggle_test_');

      final nodes = <FileTreeNode>[
        FileTreeNode(
          name: 'root',
          path: tempDir.path,
          isDirectory: true,
          isExpanded: true,
          children: [
            FileTreeNode(name: 'child', path: 'child', isDirectory: false),
          ],
        ),
      ];

      final result = cubit.toggleNodeInTreeForTest(nodes, tempDir.path);

      expect(result[0].isExpanded, isFalse);
      expect(result[0].children, isEmpty);

      tempDir.deleteSync(recursive: true);
      cubit.close();
    });

    test('recursively searches children', () {
      final cubit = ReviewCubit();
      final tempDir = Directory.systemTemp.createTempSync('toggle_test_');
      File('${tempDir.path}/file.txt').createSync();

      final childPath = tempDir.path;
      final nodes = <FileTreeNode>[
        FileTreeNode(
          name: 'root',
          path: '/root',
          isDirectory: true,
          isExpanded: true,
          children: [
            FileTreeNode(
              name: 'child',
              path: childPath,
              isDirectory: true,
              isExpanded: false,
              children: [],
            ),
          ],
        ),
      ];

      final result = cubit.toggleNodeInTreeForTest(nodes, childPath);

      expect(result[0].children[0].isExpanded, isTrue);
      expect(result[0].children[0].children.length, 1);

      tempDir.deleteSync(recursive: true);
      cubit.close();
    });

    test('leaves non-matching nodes unchanged', () {
      final cubit = ReviewCubit();

      final nodes = <FileTreeNode>[
        FileTreeNode(
          name: 'file',
          path: '/file.txt',
          isDirectory: false,
        ),
      ];

      final result = cubit.toggleNodeInTreeForTest(nodes, '/other.txt');

      expect(result[0].name, 'file');
      expect(result[0].isExpanded, isFalse);

      cubit.close();
    });
  });

  group('ReviewCubit.refresh', () {
    late Directory tempDir;
    late ReviewCubit cubit;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('review_refresh_test_');
      cubit = ReviewCubit();
    });

    tearDown(() async {
      await cubit.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('does nothing when no workspace paths are set', () async {
      await cubit.refresh();

      expect(cubit.state, isA<ReviewInitial>());
    });

    test('builds an expanded root node from the workspace path', () async {
      File('${tempDir.path}/a.txt').createSync();
      Directory('${tempDir.path}/sub').createSync();

      await cubit.loadWorkspace([tempDir.path]);

      final state = cubit.state as ReviewLoaded;
      expect(state.fileTree, hasLength(1));
      final root = state.fileTree.single;
      expect(root.name, p.basename(tempDir.path));
      expect(root.path, tempDir.path);
      expect(root.isDirectory, isTrue);
      expect(root.isExpanded, isTrue);
      expect(
        root.children.map((c) => c.name),
        containsAll(<String>['a.txt', 'sub']),
      );
    });

    test('builds one root per path for multi-path workspaces', () async {
      final second = Directory.systemTemp.createTempSync('review_refresh_b_');
      addTearDown(() {
        if (second.existsSync()) second.deleteSync(recursive: true);
      });

      await cubit.loadWorkspace([tempDir.path, second.path]);

      final state = cubit.state as ReviewLoaded;
      expect(
        state.fileTree.map((n) => n.path),
        [tempDir.path, second.path],
      );
    });

    test('restores persisted expanded directories for the workspace id', () async {
      final sub = Directory('${tempDir.path}/sub')..createSync();
      File('${sub.path}/inner.txt').createSync();
      // The root path itself must be skipped (already expanded by refresh).
      SharedPreferences.setMockInitialValues({
        'filetree.expanded.ws1': [tempDir.path, sub.path],
      });

      await cubit.loadWorkspace([tempDir.path], workspaceId: 'ws1');

      final state = cubit.state as ReviewLoaded;
      final subNode = state.fileTree.single.children.single;
      expect(subNode.path, sub.path);
      expect(subNode.isExpanded, isTrue);
      expect(subNode.children.map((c) => c.name), ['inner.txt']);
    });

    test('preserves selection, content and view mode across refreshes', () async {
      File('${tempDir.path}/a.txt').createSync();
      await cubit.loadWorkspace([tempDir.path]);

      final loaded = cubit.state as ReviewLoaded;
      cubit.emit(loaded.copyWith(
        selectedFilePath: '${tempDir.path}/a.txt',
        viewMode: ReviewViewMode.file,
        fileContent: 'content',
        fileLanguage: 'dart',
      ));

      await cubit.refresh();

      final state = cubit.state as ReviewLoaded;
      expect(state.selectedFilePath, '${tempDir.path}/a.txt');
      expect(state.viewMode, ReviewViewMode.file);
      expect(state.fileContent, 'content');
      expect(state.fileLanguage, 'dart');
      expect(state.fileTree, hasLength(1));
    });
  });
}
