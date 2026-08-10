import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/run_configs_plugin.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/runs/bloc/run_state.dart';
import 'package:yoloit/features/runs/ui/run_panel.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';

import '../runs/run_panel_test_harness.dart';

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'p1',
      type: RunConfigsPluginBase.kTypeId,
      title: 'Run Configs',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 600, height: 400),
      state: state,
    );

BoardPanelRenderContext _renderContext({
  void Function(Map<String, dynamic>)? onUpdateState,
  Future<String?> Function(String, Map<String, dynamic>, String)?
  onCreateLinkedPanel,
  String? Function(String, String)? onFindPanelByGroup,
  Future<void> Function(String, String)? onRevealSessionInPanel,
  Future<void> Function(String)? onFocusPanelById,
}) => BoardPanelRenderContext(
  isSelected: false,
  onFocus: () {},
  onDelete: () {},
  onUpdateState: onUpdateState ?? (_) {},
  onShowEditor: () {},
  onCreateLinkedPanel: onCreateLinkedPanel,
  onFindPanelByGroup: onFindPanelByGroup,
  onRevealSessionInPanel: onRevealSessionInPanel,
  onFocusPanelById: onFocusPanelById,
);

/// Pumps [RunConfigsPlugin.buildContent] (or [RunPlugin.buildContent] when
/// [useRunPlugin] is set) wired to a [FakeRunCubit].
Future<void> _pumpPluginContent(
  WidgetTester tester, {
  required BoardPanelInstance panel,
  required FakeRunCubit cubit,
  required BoardPanelRenderContext renderContext,
  bool useRunPlugin = false,
}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<RunCubit>.value(value: cubit),
        BlocProvider<WorkspaceCubit>(create: (_) => WorkspaceCubit()),
      ],
      child: MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: Builder(
            builder:
                (context) =>
                    useRunPlugin
                        ? const RunPlugin().buildContent(
                          context,
                          panel,
                          renderContext,
                        )
                        : const RunConfigsPlugin().buildContent(
                          context,
                          panel,
                          renderContext,
                        ),
          ),
        ),
      ),
    ),
  );
  await pumpRunPanelFrames(tester);
}

void main() {
  const plugin = RunConfigsPlugin();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('typeId is board.run_configs', () {
    expect(plugin.typeId, 'board.run_configs');
    expect(RunConfigsPluginBase.kTypeId, 'board.run_configs');
  });

  test('displayName is Run Configs', () {
    expect(plugin.displayName, 'Run Configs');
  });

  test('icon is play_circle_outline', () {
    expect(plugin.icon, Icons.play_circle_outline);
  });

  test('accentColor is set', () {
    expect(plugin.accentColor, const Color(0xFF22C55E));
  });

  test('defaultSize is 600x400', () {
    expect(plugin.defaultSize, const Size(600, 400));
  });

  test('initialState is empty (state managed by RunBridge)', () {
    final state = plugin.initialState;
    expect(state, isEmpty);
  });

  group('buildContent', () {
    testWidgets('maps panel state onto the RunPanel', (tester) async {
      final panel = _panel(
        state: {
          'group': ' team-a ',
          'activeSessionId': 's1',
          'hiddenSessionIds': ['s2', 42, ' s3 '],
        },
      );
      final cubit = FakeRunCubit(const RunState(workspacePath: '/ws'));
      await _pumpPluginContent(
        tester,
        panel: panel,
        cubit: cubit,
        renderContext: _renderContext(),
      );

      final runPanel = tester.widget<RunPanel>(find.byType(RunPanel));
      expect(runPanel.groupId, 'team-a');
      expect(runPanel.initialAttachedSessionId, 's1');
      expect(runPanel.hiddenSessionIds, ['s2', 's3']);
      expect(runPanel.showGroupControls, isTrue);
      expect(runPanel.showConfigList, isTrue);
      expect(runPanel.showSessionTabs, isTrue);
    });

    testWidgets('falls back to panel id (configs) or default (run)', (
      tester,
    ) async {
      final panel = _panel();
      final cubit = FakeRunCubit(const RunState(workspacePath: '/ws'));

      await _pumpPluginContent(
        tester,
        panel: panel,
        cubit: cubit,
        renderContext: _renderContext(),
      );
      expect(tester.widget<RunPanel>(find.byType(RunPanel)).groupId, 'p1');

      await _pumpPluginContent(
        tester,
        panel: panel,
        cubit: cubit,
        renderContext: _renderContext(),
        useRunPlugin: true,
      );
      final runPanel = tester.widget<RunPanel>(find.byType(RunPanel));
      expect(runPanel.groupId, 'default');
      expect(runPanel.showGroupControls, isFalse);
      expect(runPanel.showConfigList, isFalse);
      expect(runPanel.showSessionTabs, isFalse);
      expect(runPanel.onSendToGroup, isNotNull);
    });

    testWidgets('RunPanel callbacks forward state updates', (tester) async {
      final panel = _panel(
        state: {'group': 'g1', 'hiddenSessionIds': ['s0']},
      );
      final cubit = FakeRunCubit(const RunState(workspacePath: '/ws'));
      final updates = <Map<String, dynamic>>[];
      final created = <String>[];
      await _pumpPluginContent(
        tester,
        panel: panel,
        cubit: cubit,
        renderContext: _renderContext(
          onUpdateState: updates.add,
          onCreateLinkedPanel: (type, state, title) async {
            created.add(
              '$type|$title|${state['group']}|${state['activeSessionId']}',
            );
            return 'new-panel';
          },
        ),
      );
      final runPanel = tester.widget<RunPanel>(find.byType(RunPanel));

      runPanel.onGroupChanged!(' g2 ');
      expect(updates.last['group'], 'g2');

      runPanel.onAttachedSessionChanged!('s9');
      expect(updates.last['activeSessionId'], 's9');

      runPanel.onSessionVisibilityChanged!('s1', true);
      expect(updates.last['hiddenSessionIds'], containsAll(['s0', 's1']));
      runPanel.onSessionVisibilityChanged!('s0', false);
      expect(updates.last['hiddenSessionIds'], isNot(contains('s0')));

      final session = runPanelSession(
        's7',
        runPanelConfig('c7', name: 'Job', group: 'g1'),
      );
      await runPanel.onDetachToPanel!(session);
      expect(created, ['board.run|Run: Job|g1|s7']);
    });

    testWidgets('send-to-group reveals an existing panel or creates one', (
      tester,
    ) async {
      final cubit = FakeRunCubit(const RunState(workspacePath: '/ws'));
      final revealed = <String>[];
      final focused = <String>[];
      final created = <String>[];
      await _pumpPluginContent(
        tester,
        panel: _panel(),
        cubit: cubit,
        useRunPlugin: true,
        renderContext: _renderContext(
          onFindPanelByGroup: (type, group) => group == 'g2' ? 'panel-x' : null,
          onRevealSessionInPanel:
              (panelId, sessionId) async => revealed.add('$panelId:$sessionId'),
          onFocusPanelById: (panelId) async => focused.add(panelId),
          onCreateLinkedPanel: (type, state, title) async {
            created.add(
              '$type|$title|${state['group']}|${state['activeSessionId']}',
            );
            return 'panel-new';
          },
        ),
      );
      final runPanel = tester.widget<RunPanel>(find.byType(RunPanel));
      final session = runPanelSession(
        's1',
        runPanelConfig('c1', name: 'App', group: 'g1'),
      );

      // Existing panel found: reveal + focus, no creation.
      await runPanel.onSendToGroup!(session, 'g2', false);
      expect(revealed, ['panel-x:s1']);
      expect(focused, ['panel-x']);
      expect(created, isEmpty);

      // Unknown group: creates a linked run-configs panel.
      await runPanel.onSendToGroup!(session, 'g3', false);
      expect(created, ['board.run_configs|Run Configs: g3|g3|s1']);

      // createNewPanel forces creation even when a panel exists.
      await runPanel.onSendToGroup!(session, 'g2', true);
      expect(created, hasLength(2));
    });

    testWidgets('send-to-group without panel callbacks is a no-op', (
      tester,
    ) async {
      final cubit = FakeRunCubit(const RunState(workspacePath: '/ws'));
      await _pumpPluginContent(
        tester,
        panel: _panel(),
        cubit: cubit,
        useRunPlugin: true,
        renderContext: _renderContext(),
      );
      final runPanel = tester.widget<RunPanel>(find.byType(RunPanel));
      final session = runPanelSession('s1', runPanelConfig('c1'));

      // Neither find/reveal/focus nor createLinked callbacks are wired, so
      // both branches bail out quietly.
      await runPanel.onSendToGroup!(session, 'g2', false);
      await runPanel.onSendToGroup!(session, 'g2', true);
    });
  });
}
