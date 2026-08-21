import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/review/bloc/review_state.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/runs/bloc/run_state.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/runs/models/run_session.dart';
import 'package:yoloit/features/skills/bloc/skills_cubit.dart';
import 'package:yoloit/features/skills/bloc/skills_state.dart';
import 'package:yoloit/features/skills/models/skill_entry.dart';
import 'package:yoloit/features/skills/models/skill_store_config.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/data/workspace_secrets_service.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';
import 'package:yoloit/features/workspaces/ui/workspace_panel.dart';

class _MockWorkspaceCubit extends Mock implements WorkspaceCubit {}

class _MockReviewCubit extends Mock implements ReviewCubit {}

class _MockTerminalCubit extends Mock implements TerminalCubit {}

class _MockRunCubit extends Mock implements RunCubit {}

class _MockSkillsCubit extends Mock implements SkillsCubit {}

/// Routes the credential-store file mirror into a temp directory so tests
/// never touch the real user config dir.
class _TempPlatformDirs extends PlatformDirs {
  const _TempPlatformDirs(this._root);

  final String _root;

  @override
  String get configDir => _root;

  @override
  String get dataDir => _root;

  @override
  String? get userHome => null;

  @override
  String get logsDir => _root;

  @override
  String get tempDir => _root;

  @override
  String get skillsDir => '$_root/skills';

  @override
  String get yoloitTempDir => '$_root/tmp';
}

_MockWorkspaceCubit _stubWorkspaceCubit(WorkspaceState state) {
  final cubit = _MockWorkspaceCubit();
  when(() => cubit.state).thenReturn(state);
  when(
    () => cubit.stream,
  ).thenAnswer((_) => const Stream<WorkspaceState>.empty());
  when(() => cubit.setActive(any())).thenAnswer((_) {});
  when(() => cubit.removeWorkspace(any())).thenAnswer((_) async {});
  when(() => cubit.addPathToWorkspace(any(), any())).thenAnswer((_) async {});
  when(() => cubit.updateWorkspace(any())).thenAnswer((_) async {});
  return cubit;
}

_MockReviewCubit _stubReviewCubit() {
  final cubit = _MockReviewCubit();
  when(() => cubit.state).thenReturn(const ReviewInitial());
  when(
    () => cubit.stream,
  ).thenAnswer((_) => const Stream<ReviewState>.empty());
  when(() => cubit.loadWorkspace(any())).thenAnswer((_) async {});
  return cubit;
}

_MockTerminalCubit _stubTerminalCubit([TerminalState? state]) {
  final cubit = _MockTerminalCubit();
  when(
    () => cubit.state,
  ).thenReturn(state ?? const TerminalInitial());
  when(
    () => cubit.stream,
  ).thenAnswer((_) => const Stream<TerminalState>.empty());
  return cubit;
}

_MockRunCubit _stubRunCubit([RunState? state]) {
  final cubit = _MockRunCubit();
  when(() => cubit.state).thenReturn(state ?? const RunState());
  when(() => cubit.stream).thenAnswer((_) => const Stream<RunState>.empty());
  return cubit;
}

_MockSkillsCubit _stubSkillsCubit(SkillsState state) {
  final cubit = _MockSkillsCubit();
  when(() => cubit.state).thenReturn(state);
  when(
    () => cubit.stream,
  ).thenAnswer((_) => const Stream<SkillsState>.empty());
  when(
    () => cubit.setSkillEnabledForWorkspace(
      skillId: any(named: 'skillId'),
      workspace: any(named: 'workspace'),
      enabled: any(named: 'enabled'),
    ),
  ).thenAnswer((inv) async {
    final ws = inv.namedArguments[#workspace] as Workspace;
    final skillId = inv.namedArguments[#skillId] as String;
    final enabled = inv.namedArguments[#enabled] as bool;
    if (enabled && ws.enabledSkills.contains(skillId)) return null;
    return ws.copyWith(
      enabledSkills:
          enabled
              ? [...ws.enabledSkills, skillId]
              : ws.enabledSkills.where((s) => s != skillId).toList(),
    );
  });
  return cubit;
}

Widget _buildPanel({
  required WorkspaceCubit workspaceCubit,
  ReviewCubit? reviewCubit,
  TerminalCubit? terminalCubit,
  RunCubit? runCubit,
  SkillsCubit? skillsCubit,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<WorkspaceCubit>.value(value: workspaceCubit),
      BlocProvider<TerminalCubit>.value(
        value: terminalCubit ?? _stubTerminalCubit(),
      ),
      BlocProvider<ReviewCubit>.value(value: reviewCubit ?? _stubReviewCubit()),
      BlocProvider<RunCubit>.value(value: runCubit ?? _stubRunCubit()),
      BlocProvider<SkillsCubit>.value(
        value: skillsCubit ?? _stubSkillsCubit(const SkillsInitial()),
      ),
    ],
    child: MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: const Scaffold(
        body: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: 260, child: WorkspacePanel()),
        ),
      ),
    ),
  );
}

/// Simulates a mouse hover over [finder] so hover-only controls appear.
/// A single pointer is reused across calls within a test: adding a second
/// pointer without removing the first trips the MouseTracker assertions.
TestGesture? _mouseGesture;

Future<void> _hoverOver(WidgetTester tester, Finder finder) async {
  var gesture = _mouseGesture;
  if (gesture == null) {
    gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer();
    _mouseGesture = gesture;
    addTearDown(() {
      gesture?.removePointer();
      _mouseGesture = null;
    });
  }
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pump();
}

/// Taps the tile's ⋯ button and waits for the popup-menu open animation.
Future<void> _openTileMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More actions'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Waits for [finder] to appear while real (non-fake) async work settles.
/// Must be called inside `tester.runAsync` (the credential store does real
/// dart:io I/O and spawns short-lived `chmod` processes).
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TestFailure('Timed out waiting for $finder');
}

/// Waits for [finder] to disappear. Must be called inside `tester.runAsync`.
Future<void> _waitForGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump();
    if (finder.evaluate().isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TestFailure('Timed out waiting for $finder to disappear');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ws1 = Workspace(id: 'ws_1', name: 'alpha', paths: ['/a/main']);
  const ws2 = Workspace(id: 'ws_2', name: 'beta', paths: ['/b/proj']);
  const ws2Skilled = Workspace(
    id: 'ws_2',
    name: 'beta',
    paths: ['/b/proj'],
    enabledSkills: ['skill_a'],
  );

  setUpAll(() {
    registerFallbackValue(AgentType.terminal);
    registerFallbackValue(const Workspace(id: '', name: '', paths: []));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('workspace secrets dialog', () {
    late Directory configTmp;

    setUp(() {
      // The credential store mirrors secrets to `<configDir>/credentials/` and
      // chmods the files; redirect it to a temp dir for the test.
      configTmp = Directory.systemTemp.createTempSync('ws_secrets_test');
      PlatformDirs.setInstance(_TempPlatformDirs(configTmp.path));
    });

    tearDown(() {
      WorkspaceSecretsService.instance.resetForTesting();
      PlatformDirs.reset();
      if (configTmp.existsSync()) configTmp.deleteSync(recursive: true);
    });

    Future<void> openSecretsDialog(
      WidgetTester tester,
      WorkspaceCubit wsCubit,
    ) async {
      await tester.pumpWidget(_buildPanel(workspaceCubit: wsCubit));
      await tester.pump();
      await _hoverOver(tester, find.text('beta'));
      await _openTileMenu(tester);
      await tester.tap(find.text('Workspace Secrets'));
      await tester.pump();
      await _waitFor(tester, find.text('🔐 Workspace Secrets'));
    }

    testWidgets('add, reveal, delete and save secrets round-trips storage', (
      tester,
    ) async {
      Map<String, String> stored = {};
      await tester.runAsync(() async {
        await WorkspaceSecretsService.instance.save('ws_2', {
          'API_KEY': 'tok123',
        });
        final wsCubit = _stubWorkspaceCubit(
          const WorkspaceLoaded(
            workspaces: [ws1, ws2],
            activeWorkspaceId: 'ws_1',
          ),
        );
        await openSecretsDialog(tester, wsCubit);

        // Existing secret loaded: one key/value row visible.
        await _waitFor(tester, find.text('API_KEY'));
        // Toggle reveal on the existing row.
        await tester.tap(find.byTooltip('Reveal'));
        await tester.pump();

        // Add a new entry and fill it in.
        await tester.tap(find.text('Add secret'));
        await tester.pump();
        final keyFields = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'KEY',
        );
        final valueFields = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'VALUE',
        );
        expect(keyFields, findsNWidgets(2));
        await tester.enterText(keyFields.last, 'NEW_KEY');
        await tester.enterText(valueFields.last, 'new_value');
        await tester.pump();

        // Delete the pre-existing entry.
        await tester.tap(find.byTooltip('Delete').first);
        await tester.pump();

        await tester.tap(find.text('Save'));
        await tester.pump();
        await _waitForGone(tester, find.text('🔐 Workspace Secrets'));
        stored = await WorkspaceSecretsService.instance.load('ws_2');
      });
      expect(stored, {'NEW_KEY': 'new_value'});
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });

    testWidgets('empty workspace shows hint and cancel keeps storage empty', (
      tester,
    ) async {
      Map<String, String> stored = {'sentinel': 'unset'};
      await tester.runAsync(() async {
        final wsCubit = _stubWorkspaceCubit(
          const WorkspaceLoaded(
            workspaces: [ws1, ws2],
            activeWorkspaceId: 'ws_1',
          ),
        );
        await openSecretsDialog(tester, wsCubit);

        await _waitFor(
          tester,
          find.text('No secrets yet. Add a KEY=VALUE pair.'),
        );
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await _waitForGone(tester, find.text('🔐 Workspace Secrets'));
        stored = await WorkspaceSecretsService.instance.load('ws_2');
      });
      expect(stored, isEmpty);
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });
  });

  group('add skill dialog', () {
    const skillA = SkillEntry(
      id: 'skill_a',
      name: 'Skill A',
      description: 'Does A',
      source: 'local',
      sourceType: SkillSourceType.local,
      isInstalled: true,
    );
    const skillB = SkillEntry(
      id: 'skill_b',
      name: 'Skill B',
      description: '',
      source: 'local',
      sourceType: SkillSourceType.local,
      isInstalled: true,
    );

    Future<void> openSkillsDialog(
      WidgetTester tester, {
      required WorkspaceCubit wsCubit,
      required SkillsCubit skillsCubit,
    }) async {
      await tester.pumpWidget(
        _buildPanel(workspaceCubit: wsCubit, skillsCubit: skillsCubit),
      );
      await tester.pump();
      await _hoverOver(tester, find.text('beta'));
      await _openTileMenu(tester);
      await tester.tap(find.text('Add Skill'));
      await tester.pump();
      expect(find.text('Add Skills to Workspace'), findsOneWidget);
    }

    testWidgets('enabling another skill applies both and closes', (
      tester,
    ) async {
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2Skilled],
          activeWorkspaceId: 'ws_1',
        ),
      );
      final skillsCubit = _stubSkillsCubit(
        const SkillsLoaded(
          config: SkillsStoreConfig(stores: []),
          skills: [skillA, skillB],
          workspaces: [ws2Skilled],
        ),
      );
      await openSkillsDialog(tester, wsCubit: wsCubit, skillsCubit: skillsCubit);

      // skill_a already enabled → checked; enable skill_b via its row.
      final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      expect(checkboxes.map((c) => c.value), [true, false]);
      await tester.tap(find.text('Skill B'));
      await tester.pump();

      await tester.tap(find.text('Apply'));
      await tester.pump();
      await tester.pump();

      verify(
        () => skillsCubit.setSkillEnabledForWorkspace(
          skillId: 'skill_a',
          workspace: any(named: 'workspace'),
          enabled: true,
        ),
      ).called(1);
      verify(
        () => skillsCubit.setSkillEnabledForWorkspace(
          skillId: 'skill_b',
          workspace: any(named: 'workspace'),
          enabled: true,
        ),
      ).called(1);
      final captured = verify(
        () => wsCubit.updateWorkspace(captureAny()),
      ).captured;
      expect(
        (captured.single as Workspace).enabledSkills,
        containsAll(['skill_a', 'skill_b']),
      );
      expect(find.text('Add Skills to Workspace'), findsNothing);
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });

    testWidgets('disabling a skill applies the removal', (tester) async {
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2Skilled],
          activeWorkspaceId: 'ws_1',
        ),
      );
      final skillsCubit = _stubSkillsCubit(
        const SkillsLoaded(
          config: SkillsStoreConfig(stores: []),
          skills: [skillA, skillB],
          workspaces: [ws2Skilled],
        ),
      );
      await openSkillsDialog(tester, wsCubit: wsCubit, skillsCubit: skillsCubit);

      await tester.tap(find.text('Skill A'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pump();
      await tester.pump();

      verify(
        () => skillsCubit.setSkillEnabledForWorkspace(
          skillId: 'skill_a',
          workspace: any(named: 'workspace'),
          enabled: false,
        ),
      ).called(1);
      verifyNever(
        () => skillsCubit.setSkillEnabledForWorkspace(
          skillId: 'skill_b',
          workspace: any(named: 'workspace'),
          enabled: any(named: 'enabled'),
        ),
      );
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });

    testWidgets('no installed skills shows guidance text', (tester) async {
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2],
          activeWorkspaceId: 'ws_1',
        ),
      );
      final skillsCubit = _stubSkillsCubit(
        const SkillsLoaded(
          config: SkillsStoreConfig(stores: []),
          skills: [],
          workspaces: [ws2],
        ),
      );
      await openSkillsDialog(tester, wsCubit: wsCubit, skillsCubit: skillsCubit);

      expect(
        find.text(
          'No skills installed yet.\nInstall skills from the Skills panel first.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      verifyNever(() => wsCubit.updateWorkspace(any()));
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });
  });

  group('active sessions panel', () {
    testWidgets('agent session row kills the session on hover action', (
      tester,
    ) async {
      final session = AgentSession(
        id: 's1',
        type: AgentType.copilot,
        workspacePath: '/repo/proj',
        status: AgentStatus.live,
      );
      final terminalCubit = _stubTerminalCubit(
        TerminalLoaded(sessions: const [], activeIndex: 0, allSessions: [session]),
      );
      final wsCubit = _stubWorkspaceCubit(const WorkspaceLoaded(workspaces: []));
      await tester.pumpWidget(
        _buildPanel(workspaceCubit: wsCubit, terminalCubit: terminalCubit),
      );
      await tester.pump();

      expect(find.text('Active Sessions'), findsOneWidget);
      expect(find.text('proj'), findsOneWidget);

      await _hoverOver(tester, find.text('proj'));
      await tester.tap(find.byTooltip('Kill session'));
      await tester.pump();

      verify(() => terminalCubit.closeSession('s1')).called(1);
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });

    testWidgets('run session rows select, stop and remove sessions', (
      tester,
    ) async {
      const running = RunSession(
        id: 'r1',
        config: RunConfig(id: 'rc1', name: 'Run A', command: 'make all'),
        workspacePath: '/repo',
        status: RunStatus.running,
      );
      const failed = RunSession(
        id: 'r2',
        config: RunConfig(id: 'rc2', name: 'Run B', command: 'make test'),
        workspacePath: '/repo',
        status: RunStatus.failed,
      );
      const stopped = RunSession(
        id: 'r3',
        config: RunConfig(id: 'rc3', name: 'Run C', command: 'make clean'),
        workspacePath: '/repo',
        status: RunStatus.stopped,
      );
      final runCubit = _stubRunCubit(
        const RunState(sessions: [running, failed, stopped]),
      );
      final wsCubit = _stubWorkspaceCubit(const WorkspaceLoaded(workspaces: []));
      await tester.pumpWidget(
        _buildPanel(workspaceCubit: wsCubit, runCubit: runCubit),
      );
      await tester.pump();

      // Tapping a row makes it the active session.
      await tester.tap(find.text('Run A'));
      await tester.pump();
      verify(() => runCubit.setActiveSession('r1')).called(1);

      // Running session offers a stop action on hover.
      await _hoverOver(tester, find.text('Run A'));
      await tester.tap(find.byTooltip('Stop run'));
      await tester.pump();
      verify(() => runCubit.stopRun('r1')).called(1);

      // Finished sessions offer a remove action on hover.
      await _hoverOver(tester, find.text('Run B'));
      await tester.tap(find.byTooltip('Remove').first);
      await tester.pump();
      verify(() => runCubit.removeSession('r2')).called(1);
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });

    testWidgets('header toggles the expanded session list', (tester) async {
      final session = AgentSession(
        id: 's1',
        type: AgentType.copilot,
        workspacePath: '/repo/proj',
      );
      final terminalCubit = _stubTerminalCubit(
        TerminalLoaded(sessions: const [], activeIndex: 0, allSessions: [session]),
      );
      final wsCubit = _stubWorkspaceCubit(const WorkspaceLoaded(workspaces: []));
      await tester.pumpWidget(
        _buildPanel(workspaceCubit: wsCubit, terminalCubit: terminalCubit),
      );
      await tester.pump();

      expect(find.text('proj'), findsOneWidget);
      await tester.tap(find.text('Active Sessions'));
      await tester.pump();
      expect(find.text('proj'), findsNothing);
      await tester.tap(find.text('Active Sessions'));
      await tester.pump();
      expect(find.text('proj'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });
  });

  group('active workspace card transition', () {
    testWidgets('switching active workspace fades cards out and back in', (
      tester,
    ) async {
      final wsCubit = WorkspaceCubit();
      wsCubit.emit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2],
          activeWorkspaceId: 'ws_1',
        ),
      );
      await tester.pumpWidget(_buildPanel(workspaceCubit: wsCubit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Switch active: the old card fades out (reverse), then ws_2 fades in.
      wsCubit.emit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2],
          activeWorkspaceId: 'ws_2',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('beta'), findsOneWidget);

      // Switch to ws_1 and immediately back to ws_2 while transitioning:
      // the ws_2 card goes fade-out → fade-in (forward).
      wsCubit.emit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2],
          activeWorkspaceId: 'ws_1',
        ),
      );
      await tester.pump();
      wsCubit.emit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2],
          activeWorkspaceId: 'ws_2',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('beta'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });
  });
}
