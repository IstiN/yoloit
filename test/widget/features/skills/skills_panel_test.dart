import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/skills/bloc/skills_cubit.dart';
import 'package:yoloit/features/skills/bloc/skills_state.dart';
import 'package:yoloit/features/skills/models/skill_entry.dart';
import 'package:yoloit/features/skills/models/skill_store_config.dart';
import 'package:yoloit/features/skills/ui/skills_panel.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

class _MockSkillsCubit extends Mock implements SkillsCubit {}

class _MockWorkspaceCubit extends Mock implements WorkspaceCubit {}

_MockSkillsCubit _stubSkillsCubit(
  SkillsState state, {
  Stream<SkillsState>? stream,
}) {
  final cubit = _MockSkillsCubit();
  when(() => cubit.state).thenReturn(state);
  when(
    () => cubit.stream,
  ).thenAnswer((_) => stream ?? const Stream<SkillsState>.empty());
  when(() => cubit.load(any())).thenAnswer((_) async {});
  when(() => cubit.selectStore(any())).thenReturn(null);
  when(() => cubit.clearError()).thenReturn(null);
  when(() => cubit.addCustomStore(any())).thenAnswer((_) async {});
  when(() => cubit.removeStore(any())).thenAnswer((_) async {});
  when(() => cubit.installSkill(any())).thenAnswer((_) async {});
  when(() => cubit.uninstallSkill(any())).thenAnswer((_) async {});
  when(() => cubit.installSkillToRepo(any(), any())).thenAnswer((_) async {});
  when(() => cubit.readSkillContent(any())).thenAnswer((_) async => null);
  when(
    () => cubit.setSkillEnabledForWorkspace(
      skillId: any(named: 'skillId'),
      workspace: any(named: 'workspace'),
      enabled: any(named: 'enabled'),
    ),
  ).thenAnswer((_) async => null);
  return cubit;
}

_MockWorkspaceCubit _stubWorkspaceCubit(WorkspaceState state) {
  final cubit = _MockWorkspaceCubit();
  when(() => cubit.state).thenReturn(state);
  when(
    () => cubit.stream,
  ).thenAnswer((_) => const Stream<WorkspaceState>.empty());
  when(() => cubit.updateWorkspace(any())).thenAnswer((_) async {});
  return cubit;
}

Widget _buildPanel({
  required SkillsCubit skillsCubit,
  required WorkspaceCubit workspaceCubit,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<SkillsCubit>.value(value: skillsCubit),
      BlocProvider<WorkspaceCubit>.value(value: workspaceCubit),
    ],
    child: MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: const Scaffold(body: SkillsPanel()),
    ),
  );
}

/// Dialogs in this panel use wide fixed-size content; give them room.
void _useBigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Finder _dialogButton(String label) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(label),
    );

const ws = Workspace(id: 'ws_1', name: 'alpha', paths: ['/repo/main']);

const ghSkill = SkillEntry(
  id: 'gh-skill',
  name: 'GH Skill',
  description: 'github skill',
  source: 'flutter/skills',
  sourceType: SkillSourceType.github,
);

const scriptSkill = SkillEntry(
  id: 'script-skill',
  name: 'Script Skill',
  description: 'script skill',
  source: 'curl ... | bash',
  sourceType: SkillSourceType.installScript,
  installCommand: 'curl ... | bash',
);

const urlSkill = SkillEntry(
  id: 'url-skill',
  name: 'Url Skill',
  description: '',
  source: 'https://example.com',
  sourceType: SkillSourceType.url,
);

const installedSkill = SkillEntry(
  id: 'inst-skill',
  name: 'Installed Skill',
  description: 'installed skill',
  source: 'flutter/skills',
  sourceType: SkillSourceType.github,
  isInstalled: true,
);

SkillsLoaded _loadedState({
  List<SkillEntry> skills = const [ghSkill, scriptSkill, urlSkill, installedSkill],
  List<Workspace> workspaces = const [ws],
  String? selectedStoreId,
  bool loadedFromRemote = false,
  SkillsStoreConfig? config,
}) {
  return SkillsLoaded(
    config: config ??
        SkillsStoreConfig.defaults.withStore(
          const SkillStore(
            id: 'custom-store',
            name: 'Custom Store',
            type: SkillStoreType.local,
            url: '/opt/skills',
          ),
        ),
    skills: skills,
    workspaces: workspaces,
    selectedStoreId: selectedStoreId,
    loadedFromRemote: loadedFromRemote,
  );
}

Future<_MockSkillsCubit> _pumpPanel(
  WidgetTester tester,
  SkillsState state, {
  Stream<SkillsState>? stream,
}) async {
  final skillsCubit = _stubSkillsCubit(state, stream: stream);
  final wsCubit = _stubWorkspaceCubit(const WorkspaceLoaded(workspaces: [ws]));
  await tester.pumpWidget(
    _buildPanel(skillsCubit: skillsCubit, workspaceCubit: wsCubit),
  );
  await tester.pump();
  return skillsCubit;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(ws);
    registerFallbackValue(ghSkill);
    registerFallbackValue(
      const SkillStore(id: 'x', name: 'x', type: SkillStoreType.github, url: 'x'),
    );
  });

  group('state views', () {
    testWidgets('loading state shows a spinner and loads on init', (tester) async {
      final cubit = await _pumpPanel(tester, const SkillsLoading());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      verify(() => cubit.load([ws])).called(1);
    });

    testWidgets('error state shows message and retry reloads', (tester) async {
      final cubit = await _pumpPanel(tester, const SkillsError('kaboom'));

      expect(find.text('kaboom'), findsOneWidget);
      verify(() => cubit.load(any())).called(1);

      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pump();

      // mocktail counts only unverified invocations: one new load call.
      verify(() => cubit.load(any())).called(1);
    });

    testWidgets('empty catalog shows the placeholder', (tester) async {
      await _pumpPanel(tester, _loadedState(skills: const []));

      expect(find.text('No skills found'), findsOneWidget);
    });
  });

  group('loaded view', () {
    testWidgets('renders sidebar, sync bar and skill cards', (tester) async {
      await _pumpPanel(tester, _loadedState());

      expect(find.text('STORES'), findsOneWidget);
      expect(find.text('All Skills'), findsOneWidget);
      expect(find.text('Installed'), findsOneWidget);
      expect(find.text('Flutter Skills'), findsOneWidget);
      expect(find.text('Custom Store'), findsOneWidget);
      // Offline sync bar copy.
      expect(find.text('Using cached catalog — no network or offline'), findsOneWidget);

      // Skill cards with per-source action labels and badges.
      expect(find.text('GH Skill'), findsOneWidget);
      expect(find.text('Install'), findsOneWidget);
      expect(find.text('Run Script'), findsOneWidget);
      expect(find.text('Open Docs'), findsOneWidget);
      expect(find.text('GitHub'), findsWidgets);
      expect(find.text('Script'), findsOneWidget);
      expect(find.text('URL'), findsOneWidget);

      // Installed skill card actions.
      expect(find.text('View'), findsOneWidget);
      expect(find.text('To Repo'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);

      // Workspace checkbox row for the installed skill.
      expect(find.text('alpha'), findsOneWidget);
    });

    testWidgets('remote sync bar shows synced copy and Sync reloads', (tester) async {
      final cubit = await _pumpPanel(tester, _loadedState(loadedFromRemote: true));

      expect(
        find.text('Catalog synced from github.com/IstiN/yoloit'),
        findsOneWidget,
      );

      await tester.tap(find.text('Sync'));
      await tester.pump();

      verify(() => cubit.load(any())).called(2);
    });

    testWidgets('tapping a store tile selects it', (tester) async {
      final cubit = await _pumpPanel(tester, _loadedState());

      await tester.tap(find.text('Installed'));
      await tester.pump();
      verify(() => cubit.selectStore('_installed')).called(1);

      await tester.tap(find.text('Custom Store'));
      await tester.pump();
      verify(() => cubit.selectStore('custom-store')).called(1);

      await tester.tap(find.text('All Skills'));
      await tester.pump();
      verify(() => cubit.selectStore(null)).called(1);
    });

    testWidgets('removing a custom store calls removeStore', (tester) async {
      final cubit = await _pumpPanel(tester, _loadedState());

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      verify(() => cubit.removeStore('custom-store')).called(1);
    });

    testWidgets('installed filter lists only installed skills', (tester) async {
      await _pumpPanel(tester, _loadedState(selectedStoreId: '_installed'));

      expect(find.text('Installed Skill'), findsOneWidget);
      expect(find.text('GH Skill'), findsNothing);
    });

    testWidgets('tapping Install installs the skill', (tester) async {
      final cubit = await _pumpPanel(tester, _loadedState());

      await tester.tap(find.text('Install'));
      await tester.pump();

      verify(() => cubit.installSkill(ghSkill)).called(1);
    });

    testWidgets('workspace checkbox toggles skill enablement', (tester) async {
      final updated = ws.copyWith(enabledSkills: const ['inst-skill']);
      final skillsCubit = _stubSkillsCubit(_loadedState());
      when(
        () => skillsCubit.setSkillEnabledForWorkspace(
          skillId: any(named: 'skillId'),
          workspace: any(named: 'workspace'),
          enabled: any(named: 'enabled'),
        ),
      ).thenAnswer((_) async => updated);
      final wsCubit = _stubWorkspaceCubit(const WorkspaceLoaded(workspaces: [ws]));
      await tester.pumpWidget(
        _buildPanel(skillsCubit: skillsCubit, workspaceCubit: wsCubit),
      );
      await tester.pump();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.pump();

      verify(
        () => skillsCubit.setSkillEnabledForWorkspace(
          skillId: 'inst-skill',
          workspace: ws,
          enabled: true,
        ),
      ).called(1);
      verify(() => wsCubit.updateWorkspace(updated)).called(1);
    });

    testWidgets('error message state surfaces a snackbar and clears it', (
      tester,
    ) async {
      final base = _loadedState();
      final errored = base.copyWith(errorMessage: 'sync failed');
      final cubit = await _pumpPanel(
        tester,
        base,
        stream: Stream<SkillsState>.fromIterable([errored]),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('sync failed'), findsOneWidget);
      verify(() => cubit.clearError()).called(greaterThanOrEqualTo(1));
      await tester.pump(const Duration(seconds: 5)); // drain snackbar timer
    });
  });

  group('dialogs', () {
    testWidgets('uninstall confirmation calls uninstallSkill', (tester) async {
      _useBigSurface(tester);
      final cubit = await _pumpPanel(tester, _loadedState());

      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Uninstall Skill'), findsOneWidget);

      await tester.tap(_dialogButton('Remove'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      verify(() => cubit.uninstallSkill('inst-skill')).called(1);
    });

    testWidgets('cancelling uninstall does nothing', (tester) async {
      _useBigSurface(tester);
      final cubit = await _pumpPanel(tester, _loadedState());

      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(_dialogButton('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      verifyNever(() => cubit.uninstallSkill(any()));
    });

    testWidgets('install to repo picks a path and installs', (tester) async {
      _useBigSurface(tester);
      final cubit = await _pumpPanel(tester, _loadedState());

      await tester.tap(find.text('To Repo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Install "Installed Skill" to Repo'), findsOneWidget);

      await tester.tap(find.text('main'));
      await tester.pump();
      await tester.tap(_dialogButton('Install'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      verify(() => cubit.installSkillToRepo(installedSkill, '/repo/main')).called(1);
    });

    testWidgets('view dialog renders the skill markdown', (tester) async {
      _useBigSurface(tester);
      final cubit = await _pumpPanel(tester, _loadedState());
      when(() => cubit.readSkillContent('inst-skill'))
          .thenAnswer((_) async => '# Deep Content\n\nsome body');

      await tester.tap(find.text('View'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('Deep Content'), findsOneWidget);
      expect(find.text('some body'), findsOneWidget);

      await tester.tap(_dialogButton('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('view dialog shows fallback when content is missing', (
      tester,
    ) async {
      _useBigSurface(tester);
      await _pumpPanel(tester, _loadedState());

      await tester.tap(find.text('View'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('Skill content not found.'), findsOneWidget);

      await tester.tap(_dialogButton('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('add store dialog validates and submits a custom store', (
      tester,
    ) async {
      _useBigSurface(tester);
      final cubit = await _pumpPanel(tester, _loadedState());

      await tester.tap(find.text('Add Store'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Add Custom Store'), findsOneWidget);

      // Empty fields: submit is a no-op.
      await tester.tap(_dialogButton('Add'));
      await tester.pump();
      verifyNever(() => cubit.addCustomStore(any()));

      await tester.enterText(
        find.byType(TextField).at(0),
        'My Store',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'https://example.com/skills.json',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(ChoiceChip, 'URL'),
        ),
      );
      await tester.pump();
      await tester.tap(_dialogButton('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final captured = verify(() => cubit.addCustomStore(captureAny())).captured;
      final store = captured.single as SkillStore;
      expect(store.id, 'my-store');
      expect(store.name, 'My Store');
      expect(store.type, SkillStoreType.url);
      expect(store.url, 'https://example.com/skills.json');
    });
  });
}
