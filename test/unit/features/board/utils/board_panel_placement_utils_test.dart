import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/plugin_type_ids.dart';
import 'package:yoloit/features/board/services/board_panel_placement_utils.dart';

void main() {
  group('initialPanelStateForBoard', () {
    const board = BoardDocument(
      id: 'b1',
      name: 'Board',
      metadata: {'defaultFolder': '/repo/root'},
    );

    test('returns the state untouched when the board has no default folder',
        () {
      const plain = BoardDocument(id: 'b2', name: 'Plain');
      const state = {'rootPath': '/elsewhere'};

      final result = initialPanelStateForBoard(
        state,
        kFileTreePluginTypeId,
        plain,
      );

      expect(identical(result, state), isTrue);
    });

    test('points file tree panels at the default folder', () {
      final result = initialPanelStateForBoard(
        const {'view': 'tree'},
        kFileTreePluginTypeId,
        board,
      );

      expect(result['rootPath'], '/repo/root');
      expect(result['view'], 'tree');
    });

    test('configures chat panels with the default folder as working dir', () {
      final result = initialPanelStateForBoard(
        const <String, dynamic>{},
        kChatPluginTypeId,
        board,
      );

      expect(result['configured'], isTrue);
      final config = result['config']! as Map<String, dynamic>;
      expect(config['workingDir'], '/repo/root');
    });

    test('preserves existing chat config fields while setting working dir',
        () {
      final result = initialPanelStateForBoard(
        const {
          'config': {'sessionName': 'My session', 'provider': 'kimi'},
        },
        kChatPluginTypeId,
        board,
      );

      final config = result['config']! as Map<String, dynamic>;
      expect(config['workingDir'], '/repo/root');
      expect(config['sessionName'], 'My session');
      expect(config['provider'], 'kimi');
    });

    test('tolerates a non-map chat config', () {
      final result = initialPanelStateForBoard(
        const {'config': 'junk'},
        kChatPluginTypeId,
        board,
      );

      final config = result['config']! as Map<String, dynamic>;
      expect(config['workingDir'], '/repo/root');
      expect(result['configured'], isTrue);
    });

    test('configures terminal panels with the default folder as working dir',
        () {
      final result = initialPanelStateForBoard(
        const {
          'config': {'sessionName': 'term'},
        },
        kTerminalPluginTypeId,
        board,
      );

      final config = result['config']! as Map<String, dynamic>;
      expect(config['workingDir'], '/repo/root');
      expect(config['sessionName'], 'term');
    });

    test('leaves unrelated panel types untouched', () {
      const state = {'shape': 'diamond'};

      final result = initialPanelStateForBoard(
        state,
        'board.shape',
        board,
      );

      expect(identical(result, state), isTrue);
    });
  });
}
