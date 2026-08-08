import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/workspaces/data/agent_workspace_dir_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String workspaceId;
  late String agentId;

  setUp(() {
    workspaceId = 'test_ws_${DateTime.now().millisecondsSinceEpoch}';
    agentId = 'agent_${DateTime.now().millisecondsSinceEpoch}';
  });

  tearDown(() async {
    await AgentWorkspaceDirService.instance.deleteAgentDir(workspaceId, agentId);
    final wsDir = Directory(
      p.dirname(p.dirname(AgentWorkspaceDirService.instance.dirForAgent(workspaceId, agentId))),
    );
    if (await wsDir.exists()) await wsDir.delete(recursive: true);
  });

  group('AgentWorkspaceDirService', () {
    test('dirForAgent returns path containing workspaceId, agentId, and agents segment', () {
      final path = AgentWorkspaceDirService.instance.dirForAgent(workspaceId, agentId);

      expect(path, contains(workspaceId));
      expect(path, contains(agentId));
      expect(path, contains('agents'));
    });

    test('dirForAgent path has correct structure with agents between workspaceId and agentId', () {
      final path = AgentWorkspaceDirService.instance.dirForAgent(workspaceId, agentId);
      final segments = p.split(path);

      final agentsIdx = segments.indexOf('agents');
      expect(agentsIdx, greaterThan(-1));

      final wsIdx = segments.indexOf(workspaceId);
      expect(wsIdx, greaterThan(-1));
      expect(wsIdx, lessThan(agentsIdx));

      final agentIdx = segments.indexOf(agentId);
      expect(agentIdx, equals(agentsIdx + 1));
    });

    test('createAgentDir creates the directory', () async {
      final dirPath = await AgentWorkspaceDirService.instance.createAgentDir(
        workspaceId,
        agentId,
        {},
      );

      expect(await Directory(dirPath).exists(), isTrue);
    });

    test('createAgentDir returns the agent dir path', () async {
      final dirPath = await AgentWorkspaceDirService.instance.createAgentDir(
        workspaceId,
        agentId,
        {},
      );

      final expectedPath = AgentWorkspaceDirService.instance.dirForAgent(workspaceId, agentId);
      expect(dirPath, equals(expectedPath));
    });

    test('createAgentDir creates correct symlinks — one per entry, linkName = basename of repoPath', () async {
      final targetPath = Directory.systemTemp.path;
      final worktreeContexts = {
        '/path/to/my-repo': targetPath,
        '/another/path/other-repo': targetPath,
      };

      final dirPath = await AgentWorkspaceDirService.instance.createAgentDir(
        workspaceId,
        agentId,
        worktreeContexts,
      );

      final link1 = Link(p.join(dirPath, 'my-repo'));
      final link2 = Link(p.join(dirPath, 'other-repo'));

      expect(await link1.exists(), isTrue);
      expect(await link1.target(), equals(targetPath));
      expect(await link2.exists(), isTrue);
      expect(await link2.target(), equals(targetPath));
    });

    test('createAgentDir creates symlink using basename of the repo path as link name', () async {
      final targetPath = Directory.systemTemp.path;
      final repoPath = '/some/deep/path/my-project';

      final dirPath = await AgentWorkspaceDirService.instance.createAgentDir(
        workspaceId,
        agentId,
        {repoPath: targetPath},
      );

      final link = Link(p.join(dirPath, 'my-project'));
      expect(await link.exists(), isTrue);
      expect(await link.target(), equals(targetPath));

      // Ensure no other unexpected link names were created from the full path
      final linkWithFullPath = Link(p.join(dirPath, 'some'));
      expect(await linkWithFullPath.exists(), isFalse);
    });

    test('createAgentDir overwrites existing symlinks on re-call', () async {
      final target1 = Directory.systemTemp.path;
      // Use a different existing path as the second target
      final target2 = p.join(Directory.systemTemp.path, '..') ;
      final target2Resolved = Directory(target2).resolveSymbolicLinksSync();

      final repoPath = '/some/repo';

      // First creation
      await AgentWorkspaceDirService.instance.createAgentDir(
        workspaceId,
        agentId,
        {repoPath: target1},
      );

      final dirPath = AgentWorkspaceDirService.instance.dirForAgent(workspaceId, agentId);
      final link = Link(p.join(dirPath, 'repo'));
      expect(await link.target(), equals(target1));

      // Second creation with different target — should overwrite
      await AgentWorkspaceDirService.instance.createAgentDir(
        workspaceId,
        agentId,
        {repoPath: target2Resolved},
      );

      expect(await link.exists(), isTrue);
      expect(await link.target(), equals(target2Resolved));
    });

    test('deleteAgentDir removes the directory', () async {
      await AgentWorkspaceDirService.instance.createAgentDir(workspaceId, agentId, {});
      final dirPath = AgentWorkspaceDirService.instance.dirForAgent(workspaceId, agentId);

      expect(await Directory(dirPath).exists(), isTrue);

      await AgentWorkspaceDirService.instance.deleteAgentDir(workspaceId, agentId);

      expect(await Directory(dirPath).exists(), isFalse);
    });

    test('deleteAgentDir is a no-op when directory does not exist', () async {
      // Should not throw even if the dir doesn't exist
      await expectLater(
        AgentWorkspaceDirService.instance.deleteAgentDir(workspaceId, agentId),
        completes,
      );
    });
  });

  group('AgentWorkspaceDirService.readWorktreeContexts', () {
    late Directory tempHome;
    late Directory worktree;
    late Directory otherWorktree;

    setUp(() {
      // Point the config dir at a temp home so the service builds agent dirs
      // inside the fixture instead of the real user config.
      tempHome = Directory.systemTemp.createTempSync('aws_dirs_test');
      PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: tempHome.path));
      worktree = Directory(p.join(tempHome.path, 'worktree'))
        ..createSync();
      otherWorktree = Directory(p.join(tempHome.path, 'other-worktree'))
        ..createSync();
    });

    tearDown(() {
      PlatformDirs.setInstance(const MacosPlatformDirs());
      if (tempHome.existsSync()) tempHome.deleteSync(recursive: true);
    });

    test('returns null when the agent directory does not exist', () async {
      final result = await AgentWorkspaceDirService.instance
          .readWorktreeContexts('no-ws', 'no-agent', const ['/repos/myrepo']);
      expect(result, isNull);
    });

    test('returns null when the agent directory has no links', () async {
      await AgentWorkspaceDirService.instance.createAgentDir(
        workspaceId,
        agentId,
        const {},
      );
      final result = await AgentWorkspaceDirService.instance
          .readWorktreeContexts(workspaceId, agentId, const ['/repos/myrepo']);
      expect(result, isNull);
    });

    test('maps the original repo path to an existing worktree target',
        () async {
      final resolvedWorktree = worktree.resolveSymbolicLinksSync();
      await AgentWorkspaceDirService.instance.createAgentDir(
        workspaceId,
        agentId,
        {'/repos/myrepo': resolvedWorktree},
      );

      final result = await AgentWorkspaceDirService.instance
          .readWorktreeContexts(workspaceId, agentId, const ['/repos/myrepo']);

      expect(result, isNotNull);
      expect(result!['/repos/myrepo'], resolvedWorktree);
    });

    test('skips links whose basename matches no workspace path', () async {
      final resolvedWorktree = worktree.resolveSymbolicLinksSync();
      await AgentWorkspaceDirService.instance.createAgentDir(
        workspaceId,
        agentId,
        {'/repos/myrepo': resolvedWorktree},
      );

      final result = await AgentWorkspaceDirService.instance
          .readWorktreeContexts(workspaceId, agentId, const ['/repos/other']);

      expect(result, isNull);
    });

    test('skips links pointing back at the original workspace path', () async {
      // Recreate the "repo" as a real directory so the link target resolves.
      final repo = Directory(p.join(tempHome.path, 'myrepo'))..createSync();
      final resolvedRepo = repo.resolveSymbolicLinksSync();
      await AgentWorkspaceDirService.instance.createAgentDir(
        workspaceId,
        agentId,
        {resolvedRepo: resolvedRepo},
      );

      final result = await AgentWorkspaceDirService.instance
          .readWorktreeContexts(workspaceId, agentId, [resolvedRepo]);

      expect(result, isNull);
    });

    test('skips links whose worktree target no longer exists', () async {
      final resolvedWorktree = worktree.resolveSymbolicLinksSync();
      await AgentWorkspaceDirService.instance.createAgentDir(
        workspaceId,
        agentId,
        {'/repos/myrepo': resolvedWorktree},
      );
      worktree.deleteSync(recursive: true);

      final result = await AgentWorkspaceDirService.instance
          .readWorktreeContexts(workspaceId, agentId, const ['/repos/myrepo']);

      expect(result, isNull);
    });

    test('collects multiple worktree links and ignores non-link entries',
        () async {
      final resolvedWorktree = worktree.resolveSymbolicLinksSync();
      final resolvedOther = otherWorktree.resolveSymbolicLinksSync();
      await AgentWorkspaceDirService.instance.createAgentDir(
        workspaceId,
        agentId,
        {
          '/repos/myrepo': resolvedWorktree,
          '/repos/otherrepo': resolvedOther,
        },
      );
      // A plain file inside the agent dir must be ignored by the scan.
      final agentDir =
          AgentWorkspaceDirService.instance.dirForAgent(workspaceId, agentId);
      File(p.join(agentDir, 'notes.txt')).writeAsStringSync('x');

      final result = await AgentWorkspaceDirService.instance
          .readWorktreeContexts(
        workspaceId,
        agentId,
        const ['/repos/myrepo', '/repos/otherrepo'],
      );

      expect(result, isNotNull);
      expect(result!.length, 2);
      expect(result['/repos/myrepo'], resolvedWorktree);
      expect(result['/repos/otherrepo'], resolvedOther);
    });
  });
}
