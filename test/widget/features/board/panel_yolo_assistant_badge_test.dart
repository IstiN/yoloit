import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/ui/panel_yolo_assistant_badge.dart';

Widget _shell({
  required BoardCubit cubit,
  required BoardPanelInstance targetPanel,
  bool expanded = false,
  ValueChanged<bool>? onExpandedChanged,
  Widget Function(
    BoardPanelInstance assistantPanel,
    ValueChanged<Map<String, dynamic>> onUpdateState,
  )? chatBuilder,
}) {
  return MaterialApp(
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(
      body: BlocProvider.value(
        value: cubit,
        child: Stack(
          children: [
            const SizedBox.expand(),
            PanelYoloAssistantBadge(
              targetPanel: targetPanel,
              expanded: expanded,
              onExpandedChanged: onExpandedChanged ?? (_) {},
              chatBuilder: chatBuilder,
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PanelYoloAssistantBadge', () {
    testWidgets('collapsed badge renders and expands on tap', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final cubit = BoardCubit();
      const targetPanel = BoardPanelInstance(
        id: 'target',
        type: MarkdownNotePlugin.kTypeId,
        title: 'Focus panel',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 400),
        state: {},
      );
      const board = BoardDocument(
        id: 'board',
        name: 'Board',
        viewport: BoardViewport(scale: 1),
        panels: [targetPanel],
      );
      cubit.emit(
        const BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
      );

      var expanded = false;
      await tester.pumpWidget(
        _shell(
          cubit: cubit,
          targetPanel: targetPanel,
          onExpandedChanged: (value) => expanded = value,
          chatBuilder: (_, __) => const SizedBox.shrink(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byTooltip('Ask YoLo about this panel'), findsOneWidget);

      await tester.tap(find.byTooltip('Ask YoLo about this panel'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(expanded, isTrue);
      expect(find.text('YOLO'), findsOneWidget);
    });

    testWidgets('persists assistant state into target panel', (tester) async {
      final cubit = BoardCubit();
      const targetPanel = BoardPanelInstance(
        id: 'target',
        type: MarkdownNotePlugin.kTypeId,
        title: 'Focus panel',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 400),
        state: {},
      );
      const board = BoardDocument(
        id: 'board',
        name: 'Board',
        viewport: BoardViewport(scale: 1),
        panels: [targetPanel],
      );
      cubit.emit(
        const BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
      );

      ValueChanged<Map<String, dynamic>>? capturedOnUpdate;
      await tester.pumpWidget(
        _shell(
          cubit: cubit,
          targetPanel: targetPanel,
          expanded: true,
          chatBuilder: (panel, onUpdate) {
            capturedOnUpdate = onUpdate;
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(capturedOnUpdate, isNotNull);
      capturedOnUpdate!({'messages': <Map<String, dynamic>>[], 'configured': true});
      await tester.pump();

      final updated = cubit.state.activeBoard!.panels.singleWhere(
        (p) => p.id == 'target',
      );
      final assistantState = updated.state['yoloAssistant'] as Map<String, dynamic>?;
      expect(assistantState, isNotNull);
      expect(assistantState!['messages'], isEmpty);
    });

    testWidgets('creates chat-configured assistant panel', (tester) async {
      final cubit = BoardCubit();
      const targetPanel = BoardPanelInstance(
        id: 'target',
        type: MarkdownNotePlugin.kTypeId,
        title: 'Focus panel',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 400),
        state: {},
      );
      const board = BoardDocument(
        id: 'board',
        name: 'Board',
        viewport: BoardViewport(scale: 1),
        panels: [targetPanel],
      );
      cubit.emit(
        const BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
      );

      BoardPanelInstance? capturedPanel;
      await tester.pumpWidget(
        _shell(
          cubit: cubit,
          targetPanel: targetPanel,
          expanded: true,
          chatBuilder: (panel, onUpdate) {
            capturedPanel = panel;
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(capturedPanel, isNotNull);
      expect(capturedPanel!.type, ChatPanelPlugin.kTypeId);
      expect(capturedPanel!.state['configured'], isTrue);
      expect(capturedPanel!.state['targetPanelId'], 'target');
      final config = ChatSessionConfig.fromJson(
        Map<String, dynamic>.from(capturedPanel!.state['config'] as Map),
      );
      expect(config.provider, 'local');
    });

    testWidgets('restores persisted provider config', (tester) async {
      final cubit = BoardCubit();
      const targetPanel = BoardPanelInstance(
        id: 'target',
        type: MarkdownNotePlugin.kTypeId,
        title: 'Focus panel',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 400),
        state: {
          'yoloAssistant': {
            'configured': true,
            'config': {
              'sessionName': 'saved',
              'workingDir': '/tmp',
              'provider': 'copilot',
              'model': 'gpt-5-mini',
            },
          },
        },
      );
      const board = BoardDocument(
        id: 'board',
        name: 'Board',
        viewport: BoardViewport(scale: 1),
        panels: [targetPanel],
      );
      cubit.emit(
        const BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
      );

      BoardPanelInstance? capturedPanel;
      await tester.pumpWidget(
        _shell(
          cubit: cubit,
          targetPanel: targetPanel,
          expanded: true,
          chatBuilder: (panel, onUpdate) {
            capturedPanel = panel;
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      final config = ChatSessionConfig.fromJson(
        Map<String, dynamic>.from(capturedPanel!.state['config'] as Map),
      );
      expect(config.provider, 'local');
      expect(config.sessionName, 'saved');
    });
  });
}
