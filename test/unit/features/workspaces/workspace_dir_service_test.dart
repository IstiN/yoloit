import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/workspaces/data/workspace_dir_service.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempHome;
  late Directory repoA;
  late Directory repoB;
  late Directory repoSameName;
  const workspaceId = 'ws_test_1';

  setUp(() async {
    tempHome = await Directory.systemTemp.createTemp('yoloit_ws_dir_');
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: tempHome.path));

    repoA = await Directory(p.join(tempHome.path, 'repos', 'alpha')).create(recursive: true);
    repoB = await Directory(p.join(tempHome.path, 'repos', 'beta')).create(recursive: true);
    repoSameName = await Directory(p.join(tempHome.path, 'other', 'dup')).create(recursive: true);
  });

  tearDown(() async {
    PlatformDirs.setInstance(const MacosPlatformDirs());
    final wsRoot = Directory(
      p.join(tempHome.path, '.config', 'yoloit', 'workspaces'),
    );
    if (await wsRoot.exists()) {
      await wsRoot.delete(recursive: true);
    }
    if (await tempHome.exists()) {
      try {
        await tempHome.delete(recursive: true);
      } catch (_) {}
    }
  });

  Workspace workspace({
    required List<String> paths,
    String id = workspaceId,
  }) {
    return Workspace(id: id, name: 'test', paths: paths);
  }

  Future<Map<String, String>> linkNameToTarget(String wsId) async {
    final dir = Directory(
      WorkspaceDirService.instance.dirForWorkspace(wsId),
    );
    if (!await dir.exists()) return {};
    final out = <String, String>{};
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is Link) {
        out[name] = await entity.target();
      } else {
        final type = await FileSystemEntity.type(entity.path, followLinks: false);
        if (type == FileSystemEntityType.link) {
          out[name] = await Link(entity.path).target();
        }
      }
    }
    return out;
  }

  group('WorkspaceDirService', () {
    test('syncSymlinks creates workspace directory when it does not exist', () async {
      final ws = workspace(paths: [repoA.path]);
      final wsDir = Directory(ws.workspaceDir);
      expect(await wsDir.exists(), isFalse);

      await WorkspaceDirService.instance.syncSymlinks(ws);

      expect(await wsDir.exists(), isTrue);
    });

    test('syncSymlinks creates a symlink for each path', () async {
      final ws = workspace(paths: [repoA.path, repoB.path]);
      await WorkspaceDirService.instance.syncSymlinks(ws);

      final links = await linkNameToTarget(workspaceId);
      expect(links, hasLength(2));
      expect(links.values, containsAll([repoA.path, repoB.path]));
    });

    test('syncSymlinks deduplicates basenames', () async {
      final dup1 = await Directory(p.join(tempHome.path, 'dup1', 'repo')).create(recursive: true);
      final dup2 = await Directory(p.join(tempHome.path, 'dup2', 'repo')).create(recursive: true);
      final ws = workspace(paths: [dup1.path, dup2.path]);

      await WorkspaceDirService.instance.syncSymlinks(ws);

      final links = await linkNameToTarget(workspaceId);
      expect(links.keys, containsAll(['repo', 'repo_2']));
    });

    test('syncSymlinks removes stale link when path is dropped', () async {
      final ws = workspace(paths: [repoA.path, repoB.path]);
      await WorkspaceDirService.instance.syncSymlinks(ws);

      final updated = workspace(paths: [repoA.path]);
      await WorkspaceDirService.instance.syncSymlinks(updated);

      final links = await linkNameToTarget(workspaceId);
      expect(links, hasLength(1));
      expect(links.values.single, repoA.path);
    });

    test('syncSymlinks preserves valid links when one path of two is removed', () async {
      final ws = workspace(paths: [repoA.path, repoB.path]);
      await WorkspaceDirService.instance.syncSymlinks(ws);

      final updated = workspace(paths: [repoB.path]);
      await WorkspaceDirService.instance.syncSymlinks(updated);

      final links = await linkNameToTarget(workspaceId);
      expect(links, hasLength(1));
      expect(links.values.single, repoB.path);
    });

    test('deleteDir removes the workspace directory entirely', () async {
      final ws = workspace(paths: [repoA.path]);
      await WorkspaceDirService.instance.syncSymlinks(ws);
      final wsDir = Directory(ws.workspaceDir);
      expect(await wsDir.exists(), isTrue);

      await WorkspaceDirService.instance.deleteDir(workspaceId);

      expect(await wsDir.exists(), isFalse);
    });

    test('deleteDir on non-existent dir completes without error', () async {
      await expectLater(
        WorkspaceDirService.instance.deleteDir('nonexistent_ws_id'),
        completes,
      );
    });

    test('syncSymlinks uses basename for Windows-style paths', () async {
      final windowsStylePath = r'C:\Users\dev\project';
      final ws = workspace(paths: [windowsStylePath]);
      await WorkspaceDirService.instance.syncSymlinks(ws);

      final links = await linkNameToTarget(workspaceId);
      expect(links, hasLength(1));
      expect(links.keys.single, 'project');
      expect(links.values.single, windowsStylePath);
    });
  });
}
