import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/audio_recorder/audio_recording_manager.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AudioRecordingManager.boardIdForPanel', () {
    test('returns null when no cubit is attached', () {
      final manager = AudioRecordingManager.testInstance();
      expect(manager.boardIdForPanel('p1'), isNull);
    });

    test('returns the board id that contains the panel', () {
      const panel = BoardPanelInstance(
        id: 'p1',
        type: 'board.audio_recorder',
        title: 'Recorder',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 300, height: 400),
      );
      final board1 = BoardDocument(
        id: 'b1',
        name: 'Board 1',
        panels: const [panel],
      );
      final board2 = BoardDocument(id: 'b2', name: 'Board 2');

      final cubit = BoardCubit();
      addTearDown(cubit.close);
      cubit.emit(BoardState(
        boards: [board1, board2],
        activeBoardId: 'b1',
        isLoaded: true,
      ));

      final manager = AudioRecordingManager.testInstance();
      manager.setCubit(cubit);

      expect(manager.boardIdForPanel('p1'), 'b1');
    });

    test('returns null for an unknown panel id', () {
      final board = BoardDocument(id: 'b1', name: 'Board 1');

      final cubit = BoardCubit();
      addTearDown(cubit.close);
      cubit.emit(BoardState(
        boards: [board],
        activeBoardId: 'b1',
        isLoaded: true,
      ));

      final manager = AudioRecordingManager.testInstance();
      manager.setCubit(cubit);

      expect(manager.boardIdForPanel('missing'), isNull);
    });

    test('finds the panel in the second board when not in the first', () {
      const panel = BoardPanelInstance(
        id: 'p2',
        type: 'board.audio_recorder',
        title: 'Recorder',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 300, height: 400),
      );
      final board1 = BoardDocument(id: 'b1', name: 'Board 1');
      final board2 = BoardDocument(
        id: 'b2',
        name: 'Board 2',
        panels: const [panel],
      );

      final cubit = BoardCubit();
      addTearDown(cubit.close);
      cubit.emit(BoardState(
        boards: [board1, board2],
        activeBoardId: 'b1',
        isLoaded: true,
      ));

      final manager = AudioRecordingManager.testInstance();
      manager.setCubit(cubit);

      expect(manager.boardIdForPanel('p2'), 'b2');
    });

    test('handles empty board list gracefully', () {
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      cubit.emit(const BoardState(boards: [], isLoaded: true));

      final manager = AudioRecordingManager.testInstance();
      manager.setCubit(cubit);

      expect(manager.boardIdForPanel('any'), isNull);
    });
  });
}
