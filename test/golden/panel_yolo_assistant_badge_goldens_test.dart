import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/ui/panel_yolo_assistant_badge.dart';

const _kSurface = Size(420, 460);

Widget _shell({
  required BoardPanelInstance targetPanel,
  required bool expanded,
  Widget Function(
    BoardPanelInstance assistantPanel,
    ValueChanged<Map<String, dynamic>> onUpdateState,
  )? chatBuilder,
}) {
  final cubit = BoardCubit();
  final board = BoardDocument(
    id: 'board',
    name: 'Golden board',
    viewport: const BoardViewport(scale: 1),
    panels: [targetPanel],
  );
  cubit.emit(
    BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: BlocProvider.value(
        value: cubit,
        child: Stack(
          children: [
            const SizedBox.expand(),
            PanelYoloAssistantBadge(
              targetPanel: targetPanel,
              expanded: expanded,
              onExpandedChanged: (_) {},
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

  group('Golden tests — panel YoLo assistant badge', () {
    testGoldens('collapsed badge', (tester) async {
      const targetPanel = BoardPanelInstance(
        id: 'target',
        type: MarkdownNotePlugin.kTypeId,
        title: 'Focus panel',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 400),
        state: {'markdown': 'Hello'},
      );
      await tester.pumpWidgetBuilder(
        _shell(targetPanel: targetPanel, expanded: false),
        surfaceSize: _kSurface,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'panel_yolo_assistant_badge_collapsed');
    });

    testGoldens('expanded overlay', (tester) async {
      const targetPanel = BoardPanelInstance(
        id: 'target',
        type: MarkdownNotePlugin.kTypeId,
        title: 'Focus panel',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 400),
        state: {'markdown': 'Hello'},
      );
      await tester.pumpWidgetBuilder(
        _shell(
          targetPanel: targetPanel,
          expanded: true,
          chatBuilder: (_, __) => const Center(child: Text('Chat content')),
        ),
        surfaceSize: _kSurface,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await screenMatchesGolden(tester, 'panel_yolo_assistant_badge_expanded');
    });
  });
}
