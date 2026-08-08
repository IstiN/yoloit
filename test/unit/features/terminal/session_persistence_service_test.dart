import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/terminal/data/session_persistence_service.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const workspaceId = 'ws-test';
  const prefsKey = 'terminal_sessions_v2_$workspaceId';

  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmpDir = await Directory.systemTemp.createTemp('session_persist_test_');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  Future<Directory> makeWorkspaceDir(String name) async {
    final dir = Directory('${tmpDir.path}/$name');
    await dir.create(recursive: true);
    return dir;
  }

  group('SessionPersistenceService.load', () {
    test('returns an empty list when nothing is stored', () async {
      final result = await SessionPersistenceService.instance.load(workspaceId);
      expect(result, isEmpty);
    });

    test('returns an empty list for malformed JSON', () async {
      SharedPreferences.setMockInitialValues({prefsKey: 'not-json{{{'});
      final result = await SessionPersistenceService.instance.load(workspaceId);
      expect(result, isEmpty);
    });

    test('restores a saved session whose workspace path exists', () async {
      final ws = await makeWorkspaceDir('project-a');
      SharedPreferences.setMockInitialValues({
        prefsKey: jsonEncode([
          {
            'id': 's1',
            'type': 'claude',
            'workspacePath': ws.path,
            'workspaceId': workspaceId,
            'customName': 'My Agent',
          },
        ]),
      });

      final result = await SessionPersistenceService.instance.load(workspaceId);

      expect(result, hasLength(1));
      final saved = result.single;
      expect(saved.id, 's1');
      expect(saved.type, AgentType.claude);
      expect(saved.workspacePath, ws.path);
      expect(saved.workspaceId, workspaceId);
      expect(saved.customName, 'My Agent');
      expect(saved.worktreeContexts, isNull);
    });

    test('falls back to the requested workspaceId when not stored', () async {
      final ws = await makeWorkspaceDir('project-b');
      SharedPreferences.setMockInitialValues({
        prefsKey: jsonEncode([
          {'id': 's2', 'type': 'terminal', 'workspacePath': ws.path},
        ]),
      });

      final result = await SessionPersistenceService.instance.load(workspaceId);

      expect(result, hasLength(1));
      expect(result.single.workspaceId, workspaceId);
      expect(result.single.customName, isNull);
    });

    test('skips entries with an unknown agent type', () async {
      final ws = await makeWorkspaceDir('project-c');
      SharedPreferences.setMockInitialValues({
        prefsKey: jsonEncode([
          {'id': 'bad', 'type': 'no-such-agent', 'workspacePath': ws.path},
          {'id': 'good', 'type': 'copilot', 'workspacePath': ws.path},
        ]),
      });

      final result = await SessionPersistenceService.instance.load(workspaceId);

      expect(result, hasLength(1));
      expect(result.single.id, 'good');
      expect(result.single.type, AgentType.copilot);
    });

    test('skips entries whose workspace path no longer exists', () async {
      final ws = await makeWorkspaceDir('project-d');
      final missing = '${tmpDir.path}/deleted-dir';
      SharedPreferences.setMockInitialValues({
        prefsKey: jsonEncode([
          {'id': 'gone', 'type': 'claude', 'workspacePath': missing},
          {'id': 'alive', 'type': 'claude', 'workspacePath': ws.path},
        ]),
      });

      final result = await SessionPersistenceService.instance.load(workspaceId);

      expect(result, hasLength(1));
      expect(result.single.id, 'alive');
    });

    test('restores worktreeContexts and filters stale worktree paths',
        () async {
      final ws = await makeWorkspaceDir('project-e');
      final worktree = await makeWorkspaceDir('worktree-1');
      SharedPreferences.setMockInitialValues({
        prefsKey: jsonEncode([
          {
            'id': 's3',
            'type': 'gemini',
            'workspacePath': ws.path,
            'worktreeContexts': {
              '/repo/a': worktree.path,
              '/repo/b': '${tmpDir.path}/stale-worktree',
            },
          },
        ]),
      });

      final result = await SessionPersistenceService.instance.load(workspaceId);

      expect(result, hasLength(1));
      expect(result.single.worktreeContexts, {'/repo/a': worktree.path});
    });

    test('drops worktreeContexts entirely when every path is stale', () async {
      final ws = await makeWorkspaceDir('project-f');
      SharedPreferences.setMockInitialValues({
        prefsKey: jsonEncode([
          {
            'id': 's4',
            'type': 'cursor',
            'workspacePath': ws.path,
            'worktreeContexts': {'/repo/a': '${tmpDir.path}/stale-only'},
          },
        ]),
      });

      final result = await SessionPersistenceService.instance.load(workspaceId);

      expect(result, hasLength(1));
      expect(result.single.worktreeContexts, isNull);
    });
  });

  group('SessionPersistenceService.save + load round trip', () {
    test('persists session metadata and restores it', () async {
      final ws = await makeWorkspaceDir('project-rt');
      final session = AgentSession(
        id: 'rt-1',
        type: AgentType.pi,
        workspacePath: ws.path,
        customName: 'Round Trip',
      );

      await SessionPersistenceService.instance.save([session], workspaceId);
      final result = await SessionPersistenceService.instance.load(workspaceId);

      expect(result, hasLength(1));
      final saved = result.single;
      expect(saved.id, 'rt-1');
      expect(saved.type, AgentType.pi);
      expect(saved.workspacePath, ws.path);
      expect(saved.workspaceId, workspaceId);
      expect(saved.customName, 'Round Trip');
    });

    test('clearWorkspace removes stored sessions', () async {
      final ws = await makeWorkspaceDir('project-clr');
      final session = AgentSession(
        id: 'clr-1',
        type: AgentType.terminal,
        workspacePath: ws.path,
      );

      await SessionPersistenceService.instance.save([session], workspaceId);
      await SessionPersistenceService.instance.clearWorkspace(workspaceId);

      final result = await SessionPersistenceService.instance.load(workspaceId);
      expect(result, isEmpty);
    });
  });
}
