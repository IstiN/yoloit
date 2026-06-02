import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/services/support_log_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlatformDirs.setInstance(
      const MacosPlatformDirs(homeOverride: '/tmp/yoloit'),
    );
    SupportLogService.instance.clearMemoryLog();
  });

  test('captures recent support events and builds copy payload', () async {
    SupportLogService.instance.add(
      'board-scroll',
      'pointerScroll delta=(1, 2)',
    );
    SupportLogService.instance.add(
      'board-scroll',
      'interaction.end scale=1.00',
    );

    final memory = SupportLogService.instance.memoryLog;
    expect(memory, contains('[board-scroll] pointerScroll'));
    expect(memory, contains('[board-scroll] interaction.end'));

    final payload = await SupportLogService.instance.buildCopyPayload();
    expect(payload, contains('YoLoIT Support Logs'));
    expect(payload, contains('== Recent support events =='));
    expect(payload, contains('pointerScroll delta=(1, 2)'));
  });
}
