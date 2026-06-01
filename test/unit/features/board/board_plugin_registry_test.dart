import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';

void main() {
  test('catalogPlugins exposes user-created panel types only', () {
    final typeIds =
        BoardPluginRegistry.instance.catalogPlugins
            .map((plugin) => plugin.typeId)
            .toList();

    expect(typeIds, contains('board.sticky'));
    expect(typeIds, contains('board.shape'));
    expect(typeIds, contains('board.kanban'));
    expect(typeIds, contains('board.run_configs'));
    expect(typeIds, contains('board.setup_guide'));

    expect(typeIds, isNot(contains('board.note.markdown')));
    expect(typeIds, isNot(contains('board.chat')));
    expect(typeIds, isNot(contains('board.terminal')));
    expect(typeIds, isNot(contains('board.diff.preview')));
    expect(typeIds, isNot(contains('board.run')));
  });
}
