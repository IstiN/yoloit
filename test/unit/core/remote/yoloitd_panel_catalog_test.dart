import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_panel_catalog.dart';

void main() {
  test(
    'host-backed widgets are unavailable locally on ios but available remotely',
    () {
      for (final type in <String>[
        'board.terminal',
        'board.files',
        'board.file.preview',
        'board.filetree',
        'board.setup_guide',
        'board.run',
        'board.run_configs',
      ]) {
        expect(
          yoloitdPanelTypeAvailableOn(type, platform: 'ios', remote: false),
          isFalse,
          reason: type,
        );
        expect(
          yoloitdPanelTypeAvailableOn(type, platform: 'ios', remote: true),
          isTrue,
          reason: type,
        );
      }
    },
  );

  test('portable widgets remain available locally on ios and web', () {
    for (final type in <String>[
      'board.note.markdown',
      'board.sticky',
      'board.shape',
      'board.kanban',
      'board.checklist',
      'board.code.snippet',
      'board.widget.custom',
      'board.timer',
      'board.calendar',
      'board.table',
      'board.chart',
      'board.webpage',
      'board.ui',
      'board.chat',
    ]) {
      expect(
        yoloitdPanelTypeAvailableOn(type, platform: 'ios', remote: false),
        isTrue,
        reason: type,
      );
      expect(
        yoloitdPanelTypeAvailableOn(type, platform: 'web', remote: false),
        isTrue,
        reason: type,
      );
    }
  });

  test('descriptors serialize actions and platform capabilities', () {
    final terminal = yoloitdPanelDescriptorFor('board.terminal')!;
    final json = terminal.toJson();
    expect(json['actions'], containsAll(<String>['config', 'set-dir']));
    expect(json['capabilities'], containsPair('requiresNativeHost', true));
    expect((json['capabilities'] as Map)['remotePlatforms'], contains('ios'));
  });
}
