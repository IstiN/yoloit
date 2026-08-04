import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/runs/bloc/run_state.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/runs/models/run_session.dart';
import 'package:yoloit/features/runs/ui/run_panel.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';

/// Records calls and replaces every I/O or process-spawning method of
/// [RunCubit] with a no-op so widget tests stay hermetic.
class FakeRunCubit extends RunCubit {
  FakeRunCubit(RunState initial) {
    emit(initial);
  }

  final stopped = <String>[];
  final restarted = <String>[];
  final cleared = <String>[];
  final removed = <String>[];
  final hotReloads = <String>[];
  final started = <RunConfig>[];
  final triggered = <String>[];
  final addedConfigs = <RunConfig>[];
  final updatedConfigs = <RunConfig>[];
  final removedConfigIds = <String>[];
  final groupsEnsured = <String>[];
  int loadCalls = 0;

  @override
  Future<void> loadForWorkspace(String workspacePath) async {
    loadCalls++;
  }

  @override
  Future<void> ensureGroupInitialized(String group) async {
    groupsEnsured.add(group);
  }

  @override
  Future<RunSession?> startRun(RunConfig config) async {
    started.add(config);
    return null;
  }

  @override
  Future<RunSession?> restartSession(String sessionId) async {
    restarted.add(sessionId);
    return null;
  }

  @override
  void stopRun(String sessionId) {
    stopped.add(sessionId);
  }

  @override
  void sendHotReload(String sessionId) {
    hotReloads.add(sessionId);
  }

  @override
  void triggerQuickAction(String sessionId, RunQuickAction action) {
    triggered.add('$sessionId:${action.id}');
  }

  @override
  void clearOutput(String sessionId) {
    cleared.add(sessionId);
  }

  @override
  void removeSession(String sessionId) {
    removed.add(sessionId);
  }

  @override
  Future<RunConfig> addConfig(RunConfig config) async {
    addedConfigs.add(config);
    return config;
  }

  @override
  Future<void> updateConfig(RunConfig config) async {
    updatedConfigs.add(config);
  }

  @override
  Future<void> removeConfig(String id) async {
    removedConfigIds.add(id);
  }
}

/// Records panel-level callback invocations.
class RunPanelCallbacks {
  final attached = <String?>[];
  final visibility = <String>[];
  final detached = <RunSession>[];
  final sent = <String>[];
  final groups = <String>[];
}

RunConfig runPanelConfig(
  String id, {
  String name = 'Config',
  String group = 'g1',
  bool flutter = false,
  List<RunQuickAction> quickActions = const [],
}) => RunConfig(
  id: id,
  name: name,
  command: 'echo $id',
  group: group,
  isFlutterRun: flutter,
  quickActions: quickActions,
);

RunSession runPanelSession(
  String id,
  RunConfig config, {
  RunStatus status = RunStatus.running,
  List<RunOutputLine> output = const [],
}) => RunSession(
  id: id,
  config: config,
  workspacePath: '/ws',
  status: status,
  output: output,
  startedAt: DateTime(2026, 1, 1, 10, 30),
);

RunOutputLine runPanelLine(String text, {bool isError = false}) =>
    RunOutputLine(text: text, isError: isError, timestamp: DateTime(2026));

/// Pumps a few fixed frames instead of `pumpAndSettle`, which never settles
/// because running sessions show an infinitely repeating pulsing dot.
Future<void> pumpRunPanelFrames(WidgetTester tester, [int count = 4]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

TestGesture? _mouse;

/// Moves a single shared mouse pointer so repeated hovers in one test do not
/// create multiple simultaneous pointers (which MouseTracker rejects).
Future<void> hoverRunPanel(WidgetTester tester, Finder finder) async {
  var mouse = _mouse;
  if (mouse == null) {
    final created = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await created.addPointer();
    mouse = created;
    _mouse = created;
    addTearDown(() {
      _mouse = null;
      return created.removePointer();
    });
  }
  await mouse.moveTo(tester.getCenter(finder));
  await tester.pump();
}

/// Pumps a [RunPanel] wired to [cubit] and [callbacks] on a large surface so
/// the dialogs the panel opens fit on screen.
Future<void> pumpRunPanel(
  WidgetTester tester,
  FakeRunCubit cubit,
  RunPanelCallbacks callbacks, {
  String groupId = 'g1',
  bool showSessionTabs = true,
  bool showConfigList = true,
  bool withDetachToPanel = false,
  bool withSendToGroup = false,
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
          body: RunPanel(
            groupId: groupId,
            showSessionTabs: showSessionTabs,
            showConfigList: showConfigList,
            onAttachedSessionChanged: callbacks.attached.add,
            onSessionVisibilityChanged:
                (id, hidden) => callbacks.visibility.add('$id:$hidden'),
            onDetachToPanel:
                withDetachToPanel
                    ? (session) async => callbacks.detached.add(session)
                    : null,
            onSendToGroup:
                withSendToGroup
                    ? (session, group, createNewPanel) async =>
                        callbacks.sent.add(
                          '${session.id}:$group:$createNewPanel',
                        )
                    : null,
            onGroupChanged: callbacks.groups.add,
          ),
        ),
      ),
    ),
  );
  await pumpRunPanelFrames(tester);
}
