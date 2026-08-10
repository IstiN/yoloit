import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/board/ui/board_panel_card.dart';

/// Captures the [BoardPanelRenderContext] handed to plugin content so tests
/// can exercise the lookup callbacks wired up by [BoardPanelCard].
class _ContextCapturePlugin extends BoardPanelPlugin {
  _ContextCapturePlugin(this.onBuild);

  final void Function(BoardPanelRenderContext) onBuild;

  @override
  String get typeId => 'test.context_capture';

  @override
  String get displayName => 'Context Capture';

  @override
  IconData get icon => Icons.widgets_outlined;

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    onBuild(renderContext);
    return const SizedBox.expand();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const capturePanel = BoardPanelInstance(
    id: 'cap-1',
    type: 'test.context_capture',
    title: 'Capture',
    bounds: BoardPanelBounds(x: 40, y: 40, width: 320, height: 240),
  );
  const tablePanel = BoardPanelInstance(
    id: 'tbl-1',
    type: 'board.table',
    title: 'Orders',
    bounds: BoardPanelBounds(x: 400, y: 40, width: 320, height: 240),
    state: {'tableId': 'orders'},
  );
  const runPanel = BoardPanelInstance(
    id: 'run-1',
    type: 'board.run',
    title: 'Build runner',
    bounds: BoardPanelBounds(x: 40, y: 400, width: 320, height: 240),
    state: {'group': 'build'},
  );
  const spacedRunPanel = BoardPanelInstance(
    id: 'run-2',
    type: 'board.run',
    title: 'Test runner',
    bounds: BoardPanelBounds(x: 400, y: 400, width: 320, height: 240),
    state: {'group': '  test  '},
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<BoardPanelRenderContext> pumpCard(
    WidgetTester tester,
    BoardCubit cubit,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    BoardPanelRenderContext? captured;
    BoardPluginRegistry.instance.register(
      _ContextCapturePlugin((ctx) => captured = ctx),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: Stack(
              children: [
                BoardPanelCard(
                  panel: capturePanel,
                  positionOffset: Offset.zero,
                  onTap: () {},
                  onMove: (_) {},
                  onResize: (_) {},
                  onDragStart: (_) {},
                  onDragEnd: () {},
                  onDelete: () {},
                  onEditColor: () {},
                  onBringToFront: () {},
                  onSendToBack: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    return captured!;
  }

  BoardCubit cubitWithBoard(List<BoardPanelInstance> panels) {
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    cubit.emit(
      BoardState(
        boards: [BoardDocument(id: 'board', name: 'Board', panels: panels)],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );
    return cubit;
  }

  testWidgets('onFindPanelById resolves panel ids and table custom ids', (
    tester,
  ) async {
    final cubit = cubitWithBoard(const [capturePanel, tablePanel]);
    final ctx = await pumpCard(tester, cubit);

    expect(ctx.onFindPanelById!('cap-1')?.id, 'cap-1');
    expect(ctx.onFindPanelById!('tbl-1')?.id, 'tbl-1');
    expect(ctx.onFindPanelById!('orders')?.id, 'tbl-1');
    expect(ctx.onFindPanelById!('missing'), isNull);
  });

  testWidgets('onFindPanelByGroup matches trimmed group names per type', (
    tester,
  ) async {
    final cubit = cubitWithBoard(const [capturePanel, runPanel, spacedRunPanel]);
    final ctx = await pumpCard(tester, cubit);

    expect(ctx.onFindPanelByGroup!('board.run', 'build'), 'run-1');
    expect(ctx.onFindPanelByGroup!('board.run', 'test'), 'run-2');
    expect(ctx.onFindPanelByGroup!('board.run', 'missing'), isNull);
    expect(ctx.onFindPanelByGroup!('board.kanban', 'build'), isNull);
  });

  testWidgets('lookups return null when there is no active board', (
    tester,
  ) async {
    final cubit = cubitWithBoard(const [capturePanel, tablePanel]);
    final ctx = await pumpCard(tester, cubit);
    expect(ctx.onFindPanelById!('cap-1'), isNotNull);

    cubit.emit(const BoardState(isLoaded: true));
    await tester.pump();

    expect(ctx.onFindPanelById!('cap-1'), isNull);
    expect(ctx.onFindPanelByGroup!('board.run', 'build'), isNull);
  });
}
