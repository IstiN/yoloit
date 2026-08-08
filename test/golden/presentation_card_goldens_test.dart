import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_factory.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/agent_card.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/workspace_card.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

const _darkBg = Color(0xFF0D1117);

/// Pumps a card inside a dark-themed MaterialApp at the given surface size.
Future<void> _pumpCard(
  WidgetTester tester,
  Widget child, {
  double width = 360,
  double height = 280,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
  addTearDown(() => tester.view.resetDevicePixelRatio());

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: _darkBg),
      home: Scaffold(
        body: SizedBox(width: width, height: height, child: child),
      ),
    ),
  );
  // One extra frame to lay out + build animations to first frame
  await tester.pump(const Duration(milliseconds: 50));
}

/// Builds card from raw JSON (same path as browser guest).
Widget _fromJson(String nodeId, Map<String, dynamic> content) {
  return buildCardFromContent(nodeId, content, CardEventCallbacks());
}

/// Compares a golden file. Animation-safe: does NOT use pumpAndSettle.
Future<void> _golden(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(Scaffold),
    matchesGoldenFile('goldens/$name.png'),
  );
}

// ── Test data ────────────────────────────────────────────────────────────────

const _agentJson = <String, dynamic>{
  'type': 'agent',
  'name': 'copilot-session-1',
  'status': 'live',
  'isRunning': true,
  'isIdle': false,
  'typeName': 'copilot',
  'lastLines': [
    '> Analyzing codebase...',
    '> Found 42 files to process',
    '> Running lint checks...',
    '> All checks passed ✓',
    '> Generating diff...',
  ],
  'repos': [
    {'repo': 'yoloit', 'branch': 'main'},
    {'repo': 'client-app', 'branch': 'feature/auth'},
  ],
};

const _agentIdleJson = <String, dynamic>{
  'type': 'agent',
  'name': 'idle-agent',
  'status': 'idle',
  'isRunning': false,
  'isIdle': true,
  'typeName': 'claude',
  'lastLines': <String>[],
  'repos': <Map<String, dynamic>>[],
};

const _workspaceJson = <String, dynamic>{
  'type': 'workspace',
  'name': 'yoloit-core',
  'path': '/Users/dev/yoloit',
  'paths': ['/Users/dev/yoloit', '/Users/dev/client-app'],
  'color': 0xFF4B9EFF,
};

const _repoJson = <String, dynamic>{
  'type': 'repo',
  'name': 'yoloit',
  'path': '/Users/dev/yoloit',
  'branch': 'main',
};

const _branchJson = <String, dynamic>{
  'type': 'branch',
  'name': 'feature/mindmap-view',
  'repoName': 'yoloit',
  'commitHash': 'a1b2c3d',
};

const _runJson = <String, dynamic>{
  'type': 'run',
  'name': 'flutter test',
  'status': 'running',
  'isRunning': true,
  'lines': [
    {'text': '00:01 +1: test/unit/core_test.dart', 'isError': false},
    {'text': '00:02 +2: test/unit/auth_test.dart', 'isError': false},
    {'text': '00:03 +2 -1: test/unit/widget_test.dart', 'isError': true},
    {'text': 'Expected: <42>', 'isError': true},
    {'text': '  Actual: <41>', 'isError': true},
  ],
};

const _runIdleJson = <String, dynamic>{
  'type': 'run',
  'name': 'build:release',
  'status': 'idle',
  'isRunning': false,
  'lines': <Map<String, dynamic>>[],
};

const _editorJson = <String, dynamic>{
  'type': 'editor',
  'filePath': '/lib/main.dart',
  'language': 'dart',
  'content': '''import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YoLoIT',
      home: const HomePage(),
    );
  }
}''',
  'tabs': [
    {'path': '/lib/main.dart', 'isActive': true},
    {'path': '/lib/app.dart', 'isActive': false},
  ],
};

const _filesJson = <String, dynamic>{
  'type': 'files',
  'repoPath': '/Users/dev/yoloit',
  'files': [
    {'path': 'lib/app.dart', 'status': 'modified', 'addedLines': 45, 'removedLines': 12},
    {'path': 'lib/new_feature.dart', 'status': 'added', 'addedLines': 120, 'removedLines': 0},
    {'path': 'lib/old_code.dart', 'status': 'deleted', 'addedLines': 0, 'removedLines': 85},
    {'path': 'lib/renamed.dart', 'status': 'renamed', 'addedLines': 3, 'removedLines': 3},
  ],
};

const _fileTreeJson = <String, dynamic>{
  'type': 'tree',
  'repoName': 'yoloit',
  'repoPath': '/Users/dev/yoloit',
  'entries': [
    {'name': 'lib', 'path': '/lib', 'isDir': true, 'depth': 0, 'isExpanded': true},
    {'name': 'features', 'path': '/lib/features', 'isDir': true, 'depth': 1, 'isExpanded': true},
    {'name': 'mindmap', 'path': '/lib/features/mindmap', 'isDir': true, 'depth': 2, 'isExpanded': false},
    {'name': 'terminal', 'path': '/lib/features/terminal', 'isDir': true, 'depth': 2, 'isExpanded': false},
    {'name': 'main.dart', 'path': '/lib/main.dart', 'isDir': false, 'depth': 1, 'isExpanded': false},
    {'name': 'test', 'path': '/test', 'isDir': true, 'depth': 0, 'isExpanded': false},
    {'name': 'pubspec.yaml', 'path': '/pubspec.yaml', 'isDir': false, 'depth': 0, 'isExpanded': false},
  ],
};

const _diffJson = <String, dynamic>{
  'type': 'diff',
  'repoName': 'yoloit',
  'repoPath': '/Users/dev/yoloit',
  'hunks': [
    {
      'header': '@@ -10,6 +10,8 @@ class MyApp',
      'lines': [
        {'text': '  Widget build(BuildContext context) {', 'type': 'context'},
        {'text': '    return MaterialApp(', 'type': 'context'},
        {'text': '-      title: "Old Title",', 'type': 'remove'},
        {'text': '+      title: "YoLoIT",', 'type': 'add'},
        {'text': '+      debugShowCheckedModeBanner: false,', 'type': 'add'},
        {'text': '      home: const HomePage(),', 'type': 'context'},
        {'text': '    );', 'type': 'context'},
      ],
    },
  ],
};

const _sessionJson = <String, dynamic>{
  'type': 'session',
  'name': 'copilot-task-42',
  'typeName': 'copilot',
  'status': 'live',
  'isLive': true,
  'isRunning': true,
};

const _sessionIdleJson = <String, dynamic>{
  'type': 'session',
  'name': 'idle-session',
  'typeName': 'claude',
  'status': 'idle',
  'isLive': false,
  'isRunning': false,
};

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── AgentCard ────────────────────────────────────────────────────────────

  group('Golden — AgentCard', () {
    testWidgets('agent_card_running', (tester) async {
      await _pumpCard(tester, _fromJson('agent:sess1', _agentJson), height: 300);
      await _golden(tester, 'agent_card_running');
    });

    testWidgets('agent_card_idle', (tester) async {
      await _pumpCard(tester, _fromJson('agent:sess2', _agentIdleJson), height: 250);
      await _golden(tester, 'agent_card_idle');
    });

    testWidgets('agent_card_direct_widget', (tester) async {
      await _pumpCard(
        tester,
        const AgentCard(
          props: AgentCardProps(
            name: 'direct-agent',
            status: 'live',
            isRunning: true,
            typeName: 'copilot',
            lastLines: ['Building...', 'Done ✓'],
            repos: [RepoBranchInfo(repo: 'core', branch: 'main')],
          ),
        ),
      );
      await _golden(tester, 'agent_card_direct_widget');
    });
  });

  // ── WorkspaceCard ────────────────────────────────────────────────────────

  group('Golden — WorkspaceCard', () {
    testWidgets('workspace_card', (tester) async {
      await _pumpCard(tester, _fromJson('ws:ws1', _workspaceJson), height: 180);
      await _golden(tester, 'workspace_card');
    });

    testWidgets('workspace_card_direct', (tester) async {
      await _pumpCard(
        tester,
        const WorkspaceCard(
          props: WorkspaceCardProps(
            name: 'my-project',
            color: Color(0xFFFF6B85),
            paths: ['/home/user/project'],
          ),
        ),
        height: 160,
      );
      await _golden(tester, 'workspace_card_direct');
    });
  });

  // ── RepoCard / BranchCard ────────────────────────────────────────────────

  group('Golden — RepoCard & BranchCard', () {
    testWidgets('repo_card', (tester) async {
      await _pumpCard(tester, _fromJson('repo:r1', _repoJson), height: 140);
      await _golden(tester, 'repo_card');
    });

    testWidgets('branch_card', (tester) async {
      await _pumpCard(tester, _fromJson('branch:b1', _branchJson), height: 140);
      await _golden(tester, 'branch_card');
    });
  });

  // ── RunCard ──────────────────────────────────────────────────────────────

  group('Golden — RunCard', () {
    testWidgets('run_card_running', (tester) async {
      await _pumpCard(tester, _fromJson('run:r1', _runJson));
      await _golden(tester, 'run_card_running');
    });

    testWidgets('run_card_idle', (tester) async {
      await _pumpCard(tester, _fromJson('run:r2', _runIdleJson), height: 200);
      await _golden(tester, 'run_card_idle');
    });
  });

  // ── EditorCard ───────────────────────────────────────────────────────────

  group('Golden — EditorCard', () {
    testWidgets('editor_card', (tester) async {
      await _pumpCard(tester, _fromJson('editor:e1', _editorJson), height: 400);
      await _golden(tester, 'editor_card');
    });
  });

  // ── FilesCard ────────────────────────────────────────────────────────────

  group('Golden — FilesCard', () {
    testWidgets('files_card', (tester) async {
      await _pumpCard(tester, _fromJson('files:f1', _filesJson));
      await _golden(tester, 'files_card');
    });
  });

  // ── FileTreeCard ─────────────────────────────────────────────────────────

  group('Golden — FileTreeCard', () {
    testWidgets('file_tree_card', (tester) async {
      await _pumpCard(tester, _fromJson('tree:t1', _fileTreeJson), height: 340);
      await _golden(tester, 'file_tree_card');
    });
  });

  // ── DiffCard ─────────────────────────────────────────────────────────────

  group('Golden — DiffCard', () {
    testWidgets('diff_card', (tester) async {
      await _pumpCard(tester, _fromJson('diff:d1', _diffJson), height: 320);
      await _golden(tester, 'diff_card');
    });
  });

  // ── SessionCard ──────────────────────────────────────────────────────────

  group('Golden — SessionCard', () {
    testWidgets('session_card_live', (tester) async {
      await _pumpCard(tester, _fromJson('session:s1', _sessionJson), height: 140);
      await _golden(tester, 'session_card_live');
    });

    testWidgets('session_card_idle', (tester) async {
      await _pumpCard(tester, _fromJson('session:s2', _sessionIdleJson), height: 140);
      await _golden(tester, 'session_card_idle');
    });
  });

  // ── Card factory round-trip: all types in a grid ─────────────────────────

  group('Golden — Card Factory round-trip', () {
    testWidgets('factory_all_types_grid', (tester) async {
      final types = <String, Map<String, dynamic>>{
        'agent:a1':   _agentJson,
        'ws:w1':      _workspaceJson,
        'repo:r1':    _repoJson,
        'branch:b1':  _branchJson,
        'run:r1':     _runJson,
        'session:s1': _sessionJson,
      };

      final callbacks = CardEventCallbacks();
      final cards = types.entries.map((e) {
        return SizedBox(
          width: 340,
          height: 200,
          child: buildCardFromContent(e.key, e.value, callbacks),
        );
      }).toList();

      tester.view.physicalSize = const Size(720, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: _darkBg),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Wrap(spacing: 8, runSpacing: 8, children: cards),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await _golden(tester, 'factory_all_types_grid');
    });
  });
}
