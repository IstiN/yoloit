import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/history/board_panel_history_adapter.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';

void main() {
  test('json history adapter deep clones snapshots and restores patches', () {
    const adapter = JsonBoardPanelHistoryAdapter();
    final state = {
      'title': 'Draft',
      'nested': {
        'items': ['one'],
      },
    };

    final snapshot = adapter.snapshotState(state);
    (state['nested']! as Map)['items'] = ['changed'];

    expect((snapshot['nested'] as Map)['items'], ['one']);

    final patch = adapter.diffState(before: state, after: snapshot);
    expect(adapter.applyPatch(state: state, patch: patch), snapshot);
    expect(
      adapter.applyPatch(state: snapshot, patch: adapter.invertPatch(patch)),
      state,
    );
  });

  test('every registered board plugin exposes a usable history adapter', () {
    for (final plugin in BoardPluginRegistry.instance.all) {
      final snapshot = plugin.historyAdapter.snapshotState(plugin.initialState);
      final restored = plugin.historyAdapter.restoreState(snapshot);

      expect(snapshot, isA<Map<String, dynamic>>());
      expect(restored, snapshot, reason: plugin.typeId);
    }
  });
}
