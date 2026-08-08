import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_executor_web.dart';
import 'package:yoloit/features/board/model/board_models.dart';

import '../../../../helpers/fake_board_cubit.dart';

const _panelA = BoardPanelInstance(
  id: 'p-a',
  type: 'board.note.markdown',
  title: 'Note A',
  bounds: BoardPanelBounds(x: 10, y: 20, width: 100, height: 100),
  zIndex: 1,
  state: {'markdown': 'hello'},
);

const _panelB = BoardPanelInstance(
  id: 'p-b',
  type: 'board.note.sticky',
  title: 'Sticky B',
  bounds: BoardPanelBounds(x: 50, y: 60, width: 80, height: 80),
  zIndex: 2,
  state: {'text': 'sticky text'},
);

const _linkAB = BoardPanelLink(
  id: 'l-1',
  fromPanelId: 'p-a',
  toPanelId: 'p-b',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YoloitWebToolExecutor panel:paste', () {
    late FakeBoardCubit cubit;
    late YoloitWebToolExecutor executor;

    setUp(() {
      cubit = FakeBoardCubit();
      executor = YoloitWebToolExecutor();
      YoloitWebToolExecutor.debugClipboardPayload = null;
    });

    Future<Map<String, dynamic>> invokePaste() async {
      final result = await executor.invoke(
        'yoloit_panel_paste',
        {},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      return jsonDecode(result) as Map<String, dynamic>;
    }

    test('returns error when there is no active board', () async {
      cubit.emit(cubit.state.copyWith(boards: const []));

      final decoded = await invokePaste();

      expect(decoded['ok'], isFalse);
      expect(decoded['error'], 'No active board');
    });

    test('returns error when clipboard is empty', () async {
      final decoded = await invokePaste();

      expect(decoded['ok'], isFalse);
      expect(decoded['error'], 'Clipboard is empty');
    });

    test('returns error when clipboard has a non-panel payload', () async {
      YoloitWebToolExecutor.debugClipboardPayload = jsonEncode(
        <String, dynamic>{'kind': 'yoloit/something-else', 'panels': <dynamic>[]},
      );

      final decoded = await invokePaste();

      expect(decoded['ok'], isFalse);
      expect(decoded['error'], 'Clipboard does not contain panels');
    });

    test('returns error when clipboard has no panels to paste', () async {
      YoloitWebToolExecutor.debugClipboardPayload = jsonEncode(
        <String, dynamic>{
          'kind': 'yoloit/panels',
          'panels': <dynamic>[],
          'links': <dynamic>[],
        },
      );

      final decoded = await invokePaste();

      expect(decoded['ok'], isFalse);
      expect(decoded['error'], 'No panels to paste');
    });

    test('pastes copied panels with new ids, offset and raised zIndex', () async {
      cubit
        ..addFakePanel(_panelA)
        ..addFakePanel(_panelB);
      await cubit.upsertLink(_linkAB);

      final copyResult = await executor.invoke(
        'yoloit_panel_copy',
        {'panels': 'p-a,p-b'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      expect((jsonDecode(copyResult) as Map<String, dynamic>)['ok'], isTrue);

      final decoded = await invokePaste();

      expect(decoded['ok'], isTrue);
      expect(decoded['command'], 'panel:paste');
      final ids = (decoded['ids'] as List).cast<String>();
      expect(ids.length, 2);
      expect(ids, isNot(contains('p-a')));
      expect(ids, isNot(contains('p-b')));

      final board = cubit.state.activeBoard!;
      expect(board.panels.length, 4);
      final pastedA = board.panels.firstWhere((p) => p.id == ids[0]);
      final pastedB = board.panels.firstWhere((p) => p.id == ids[1]);
      // Offset by +40/+40 relative to the original bounds.
      expect(pastedA.bounds.x, _panelA.bounds.x + 40);
      expect(pastedA.bounds.y, _panelA.bounds.y + 40);
      expect(pastedB.bounds.x, _panelB.bounds.x + 40);
      // New panels are stacked above the existing max zIndex.
      expect(pastedA.zIndex, greaterThan(2));
      expect(pastedB.zIndex, greaterThan(pastedA.zIndex));
      expect(pastedA.state['markdown'], 'hello');
      expect(pastedB.state['text'], 'sticky text');

      // The copied link is remapped to the new panel ids.
      expect(cubit.upsertedLinks.length, 2);
      final pastedLink = cubit.upsertedLinks.last;
      expect(pastedLink.id, isNot('l-1'));
      expect(pastedLink.fromPanelId, ids[0]);
      expect(pastedLink.toPanelId, ids[1]);

      // Pasted panels become the current selection.
      expect(cubit.state.selectedPanelIds, ids.toSet());
    });

    test('drops links whose endpoints were not copied', () async {
      YoloitWebToolExecutor.debugClipboardPayload = jsonEncode(
        <String, dynamic>{
          'kind': 'yoloit/panels',
          'panels': [_panelA.toJson(), _panelB.toJson()],
          'links': [
            _linkAB.toJson(),
            const BoardPanelLink(
              id: 'l-dangling',
              fromPanelId: 'p-a',
              toPanelId: 'p-missing',
            ).toJson(),
          ],
        },
      );

      final decoded = await invokePaste();

      expect(decoded['ok'], isTrue);
      // Only the fully-remapped link survives.
      expect(cubit.upsertedLinks.length, 1);
      expect(cubit.upsertedLinks.single.toPanelId, isNot('p-b'));
    });

    test('generates fresh ids on every paste', () async {
      YoloitWebToolExecutor.debugClipboardPayload = jsonEncode(
        <String, dynamic>{
          'kind': 'yoloit/panels',
          'panels': [_panelA.toJson()],
          'links': <dynamic>[],
        },
      );

      final first = await invokePaste();
      final second = await invokePaste();

      expect(first['ok'], isTrue);
      expect(second['ok'], isTrue);
      final firstIds = (first['ids'] as List).cast<String>();
      final secondIds = (second['ids'] as List).cast<String>();
      expect(secondIds.single, isNot(firstIds.single));
      expect(cubit.state.activeBoard!.panels.length, 2);
    });

    test('panel:duplicate copies and pastes in one step', () async {
      cubit.addFakePanel(_panelA);

      final result = await executor.invoke(
        'yoloit_panel_duplicate',
        {'panels': 'p-a'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;

      expect(decoded['ok'], isTrue);
      expect(decoded['command'], 'panel:paste');
      expect(cubit.state.activeBoard!.panels.length, 2);
    });
  });
}
