import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/review/bloc/review_state.dart';
import 'package:yoloit/features/review/models/review_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReviewCubit', () {
    test('initial state is ReviewInitial', () {
      final cubit = ReviewCubit();
      addTearDown(cubit.close);
      expect(cubit.state, const ReviewInitial());
    });

    blocTest<ReviewCubit, ReviewState>(
      'setViewMode switches view mode',
      build: () => ReviewCubit(),
      seed: () => const ReviewLoaded(fileTree: [], changedFiles: []),
      act: (cubit) => cubit.setViewMode(ReviewViewMode.file),
      expect: () => [
        isA<ReviewLoaded>()
            .having((s) => s.viewMode, 'viewMode', ReviewViewMode.file),
      ],
    );

    blocTest<ReviewCubit, ReviewState>(
      'setViewMode does nothing when not loaded',
      build: () => ReviewCubit(),
      act: (cubit) => cubit.setViewMode(ReviewViewMode.file),
      expect: () => <ReviewState>[],
    );

    blocTest<ReviewCubit, ReviewState>(
      'toggleNode expands and collapses directory',
      build: () => ReviewCubit(),
      seed: () => ReviewLoaded(
        fileTree: [
          FileTreeNode(
            name: 'root',
            path: Directory.systemTemp.path,
            isDirectory: true,
            isExpanded: false,
            children: [],
          ),
        ],
        changedFiles: [],
      ),
      act: (cubit) => cubit.toggleNode(Directory.systemTemp.path),
      expect: () => [
        isA<ReviewLoaded>()
            .having((s) => s.fileTree.first.isExpanded, 'isExpanded', true),
      ],
    );
  });

  group('ReviewCubit file operations', () {
    late Directory tempDir;
    late ReviewCubit cubit;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('review_cubit_test_');
      cubit = ReviewCubit();
      await cubit.loadWorkspace([tempDir.path]);
    });

    tearDown(() async {
      await cubit.close();
      await tempDir.delete(recursive: true);
    });

    test('createFile creates a file', () async {
      await cubit.createFile(tempDir.path, 'test.txt');

      final file = File('${tempDir.path}/test.txt');
      expect(await file.exists(), true);
    });

    test('createFolder creates directory with .gitkeep', () async {
      await cubit.createFolder(tempDir.path, 'newdir');

      final dir = Directory('${tempDir.path}/newdir');
      expect(await dir.exists(), true);
      final gitkeep = File('${tempDir.path}/newdir/.gitkeep');
      expect(await gitkeep.exists(), true);
    });

    test('renameEntry renames a file', () async {
      final oldFile = File('${tempDir.path}/old.txt');
      await oldFile.writeAsString('content');

      await cubit.renameEntry(oldFile.path, 'new.txt');

      expect(await oldFile.exists(), false);
      final newFile = File('${tempDir.path}/new.txt');
      expect(await newFile.exists(), true);
    });

    test('renameEntry renames a directory', () async {
      final oldDir = Directory('${tempDir.path}/olddir');
      await oldDir.create();

      await cubit.renameEntry(oldDir.path, 'newdir');

      expect(await oldDir.exists(), false);
      final newDir = Directory('${tempDir.path}/newdir');
      expect(await newDir.exists(), true);
    });
  });
}
