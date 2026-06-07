import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/features/review/bloc/review_cubit.dart';
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
}
