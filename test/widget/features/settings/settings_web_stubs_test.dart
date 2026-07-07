import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/settings/ui/sections/about_section_web.dart';
import 'package:yoloit/features/settings/ui/sections/chat_context_section_web.dart';
import 'package:yoloit/features/settings/ui/sections/prompts_section_web.dart';
import 'package:yoloit/features/settings/ui/sections/session_settings_section_web.dart';
import 'package:yoloit/features/settings/ui/sections/terminal_renderer_settings_web.dart';
import 'package:yoloit/features/settings/ui/sections/workspace_storage_row_web.dart';
import 'package:yoloit/features/settings/ui/setup_guide_page_web.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit_web.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

/// Verifies that the web stub settings sections compile and render an empty
/// placeholder. These are imported directly so the tests run on the VM while
/// still covering the web variants.
void main() {
  group('Settings web stubs render SizedBox.shrink()', () {
    testWidgets('AboutSection', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AboutSection()));
      expect(find.byType(AboutSection), findsOneWidget);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('ChatContextSection', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ChatContextSection()));
      expect(find.byType(ChatContextSection), findsOneWidget);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('PromptsSection', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PromptsSection()));
      expect(find.byType(PromptsSection), findsOneWidget);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('SessionSettings', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SessionSettings()));
      expect(find.byType(SessionSettings), findsOneWidget);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('TerminalRendererSettings', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: TerminalRendererSettings()),
      );
      expect(find.byType(TerminalRendererSettings), findsOneWidget);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('WorkspaceStorageRow', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: WorkspaceStorageRow()));
      expect(find.byType(WorkspaceStorageRow), findsOneWidget);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('SetupGuidePage', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SetupGuidePage()));
      expect(find.byType(SetupGuidePage), findsOneWidget);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('SetupGuideEmbedded', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SetupGuideEmbedded()));
      expect(find.byType(SetupGuideEmbedded), findsOneWidget);
      expect(find.byType(SizedBox), findsOneWidget);
    });
  });

  group('WorkspaceCubit web stub', () {
    test('initial state is empty', () {
      final cubit = WorkspaceCubit();
      expect((cubit.state as WorkspaceLoaded).workspaces, isEmpty);
    });

    test('load is a no-op', () async {
      final cubit = WorkspaceCubit();
      await cubit.load();
      expect((cubit.state as WorkspaceLoaded).workspaces, isEmpty);
    });

    test('mutations do not throw', () async {
      final cubit = WorkspaceCubit();
      await cubit.addWorkspace('/tmp');
      await cubit.addPathToWorkspace('x', '/tmp');
      await cubit.removePathFromWorkspace('x', '/tmp');
      await cubit.removeWorkspace('x');
      cubit.setActive('x');
      await cubit.setWorkspaceColor('x', Colors.red);
      await cubit.renameWorkspace('x', 'new');
      await cubit.refreshAll();
      await cubit.updateWorkspace(
        const Workspace(id: 'x', name: 'new', paths: []),
      );
      expect((cubit.state as WorkspaceLoaded).workspaces, isEmpty);
    });
  });
}
