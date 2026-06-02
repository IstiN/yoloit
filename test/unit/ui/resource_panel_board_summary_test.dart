import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/ui/shell/main_shell.dart';

void main() {
  test('resourcePanelTypeCounts sorts panel types by count then label', () {
    final counts = resourcePanelTypeCounts([
      BoardPanelInstance(
        id: 'terminal-1',
        type: 'board.terminal',
        title: 'Terminal',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 1, height: 1),
      ),
      BoardPanelInstance(
        id: 'sticky-1',
        type: 'board.sticky',
        title: 'Sticky',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 1, height: 1),
      ),
      BoardPanelInstance(
        id: 'terminal-2',
        type: 'board.terminal',
        title: 'Terminal 2',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 1, height: 1),
      ),
    ]);

    expect(counts.keys.first, 'board.terminal');
    expect(counts['board.terminal'], 2);
    expect(counts['board.sticky'], 1);
  });

  test('resourcePanelTypeLabel uses plugin names with readable fallback', () {
    expect(resourcePanelTypeLabel('board.terminal'), 'Terminal');
    expect(resourcePanelTypeLabel('board.custom_unknown'), 'custom unknown');
  });
}
