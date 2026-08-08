import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_executor_web.dart';
import 'package:yoloit/features/board/model/board_models.dart';

import '../../../../helpers/fake_board_cubit.dart';

/// Coverage-focused tests for the board viewport, grid, selection, drawing,
/// and link color handlers in `yoloit_tool_executor_web_handlers.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BoardPanelInstance fakePanel(String id, String title) {
    return BoardPanelInstance(
      id: id,
      type: 'board.note.markdown',
      title: title,
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      state: const {},
    );
  }

  Map<String, dynamic> decode(String result) =>
      jsonDecode(result) as Map<String, dynamic>;

  group('YoloitWebToolExecutor board ops', () {
    late FakeBoardCubit cubit;
    late YoloitWebToolExecutor executor;

    setUp(() {
      cubit = FakeBoardCubit();
      executor = YoloitWebToolExecutor();
    });

    Future<String> invoke(String functionName, Map<String, Object?> args) {
      return executor.invoke(
        functionName,
        args,
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
    }

    group('board:fit', () {
      test('fits the viewport around all panels', () async {
        cubit.addFakePanel(fakePanel('p-fit1', 'Fit1'));

        final result = await invoke('yoloit_board_fit', {'size': '1000x700'});
        expect(decode(result)['ok'], isTrue);
        final viewport = cubit.state.activeBoard?.viewport;
        expect(viewport?.scale, 2.0);
        expect(viewport?.translation.dx, closeTo(400, 0.01));
        expect(viewport?.translation.dy, closeTo(250, 0.01));
      });

      test('falls back to the default size for invalid input', () async {
        cubit.addFakePanel(fakePanel('p-fit2', 'Fit2'));

        final result = await invoke('yoloit_board_fit', {'size': 'junk'});
        expect(decode(result)['ok'], isTrue);
        expect(cubit.state.activeBoard?.viewport.scale, 2.0);
      });

      test('keeps the viewport when the board is empty', () async {
        final result = await invoke('yoloit_board_fit', {});
        expect(decode(result)['ok'], isTrue);
        expect(cubit.state.activeBoard?.viewport.scale, 1.0);
      });
    });

    group('board:grid', () {
      test('toggles grid mode on and off', () async {
        final on = await invoke('yoloit_board_grid', {'mode': 'on'});
        expect(decode(on)['ok'], isTrue);
        expect(cubit.state.activeBoard?.gridMode.enabled, isTrue);

        final off = await invoke('yoloit_board_grid', {'mode': 'off'});
        expect(decode(off)['ok'], isTrue);
        expect(cubit.state.activeBoard?.gridMode.enabled, isFalse);
      });

      test('reset restores the grid view', () async {
        final result = await invoke('yoloit_board_grid', {'mode': 'reset'});
        expect(decode(result)['ok'], isTrue);
      });

      test('applies cell size, spacing and arrange flag', () async {
        final result = await invoke('yoloit_board_grid', {
          'cell': 400,
          'spacing': 12,
          'arrange': true,
        });
        expect(decode(result)['ok'], isTrue);
        final gridMode = cubit.state.activeBoard?.gridMode;
        expect(gridMode?.cellSize, 400);
        expect(gridMode?.spacing, 12);
      });
    });

    group('select', () {
      test('selects panels by name', () async {
        cubit.addFakePanel(fakePanel('p-sel1', 'SelOne'));
        cubit.addFakePanel(fakePanel('p-sel2', 'SelTwo'));

        final result = await invoke('yoloit_select', {
          'panels': 'SelOne,SelTwo',
        });
        final decoded = decode(result);
        expect(decoded['ok'], isTrue);
        expect(
          decoded['selected'],
          containsAll(<String>['p-sel1', 'p-sel2']),
        );
      });

      test('selects panels inside a rect', () async {
        cubit.addFakePanel(fakePanel('p-sel3', 'SelRect'));

        final result = await invoke('yoloit_select', {'rect': '0,0,50,50'});
        expect(decode(result)['ok'], isTrue);
        expect(cubit.state.selectedPanelIds, contains('p-sel3'));
      });

      test('returns the current selection without arguments', () async {
        cubit.selectPanels({'p-sel4'});

        final result = await invoke('yoloit_select', {});
        final decoded = decode(result);
        expect(decoded['ok'], isTrue);
        expect(decoded['selected'], contains('p-sel4'));
      });
    });

    group('drawings', () {
      test('draw:add freehand uses the provided points', () async {
        final result = await invoke('yoloit_draw_add', {
          'type': 'freehand',
          'points': [
            [0, 0],
            [10, 10],
            [20, 5],
          ],
        });
        expect(decode(result)['ok'], isTrue);
        expect(cubit.addedDrawings.length, 1);
        expect(cubit.addedDrawings.first.strokes, isNotEmpty);
      });

      test('draw:add freehand without points uses a default stroke', () async {
        final result = await invoke('yoloit_draw_add', {'type': 'freehand'});
        expect(decode(result)['ok'], isTrue);
        expect(cubit.addedDrawings.length, 1);
      });

      test('draw:export renders drawings as SVG polylines', () async {
        await invoke('yoloit_draw_add', {
          'type': 'line',
          'x1': 0,
          'y1': 0,
          'x2': 50,
          'y2': 50,
        });

        final result = await invoke('yoloit_draw_export', {});
        final svg = decode(result)['svg'] as String;
        expect(svg, contains('<polyline'));
        expect(svg, contains('stroke="#'));
      });
    });

    group('link:color', () {
      Future<String> createLink() async {
        cubit.addFakePanel(fakePanel('p-lc-a', 'LinkA'));
        cubit.addFakePanel(fakePanel('p-lc-b', 'LinkB'));
        final result = await invoke('yoloit_link_create', {
          'from': 'LinkA',
          'to': 'LinkB',
        });
        return decode(result)['id'] as String;
      }

      test('sets the link color', () async {
        final linkId = await createLink();

        final result = await invoke('yoloit_link_color', {
          'link_id': linkId,
          'color': '#FF0000',
        });
        expect(decode(result)['ok'], isTrue);
        final link = cubit.state.activeBoard?.links.firstWhere(
          (l) => l.id == linkId,
        );
        expect(link?.color, isNotNull);
      });

      test('validates link id and color', () async {
        final missingId = await invoke('yoloit_link_color', {
          'color': '#FF0000',
        });
        expect(decode(missingId)['error'], contains('Missing link id'));

        final badColor = await invoke('yoloit_link_color', {
          'link_id': 'link-1',
          'color': 'not-a-color',
        });
        expect(
          decode(badColor)['error'],
          contains('Missing or invalid color'),
        );

        final unknown = await invoke('yoloit_link_color', {
          'link_id': 'no-such-link',
          'color': '#FF0000',
        });
        expect(decode(unknown)['error'], contains('Link not found'));
      });
    });
  });
}
