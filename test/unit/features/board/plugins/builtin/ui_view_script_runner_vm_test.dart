import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_script_runner_vm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final runner = UiViewScriptRunner.instance;

  group('UiViewScriptRunner.runAction', () {
    test('blank script applies payload and tap counting to storage', () {
      final result = runner.runAction(
        script: '   ',
        storage: {'count': 1},
        actionId: 'inc',
        payload: {'delta': 2},
      );

      expect(result, {
        'count': 1,
        'delta': 2,
        'lastAction': 'inc',
        'taps': 1,
      });
    });

    test('script mutations are reflected in the returned storage', () {
      final result = runner.runAction(
        script: 'storage.count = (storage.count || 0) + payload.delta;',
        storage: {'count': 1},
        actionId: 'inc',
        payload: {'delta': 4},
      );

      expect(result['count'], 5);
      expect(result.containsKey('_scriptError'), isFalse);
    });

    test('bootstrap helpers are available to scripts', () {
      final result = runner.runAction(
        script: 'yoloit.inc("total", payload.delta);',
        storage: {'total': 10},
        actionId: 'inc',
        payload: {'delta': 5},
      );

      expect(result['total'], 15);
    });

    test('script runtime errors are captured into storage', () {
      final result = runner.runAction(
        script: 'throw new Error("boom");',
        storage: {'count': 1},
        actionId: 'inc',
        payload: const {},
      );

      expect(result['count'], 1);
      expect(result['_scriptError'].toString(), contains('boom'));
    });

    test('unparseable scripts return error storage with lastAction', () {
      final result = runner.runAction(
        script: 'this is not valid js %%',
        storage: {'count': 7},
        actionId: 'inc',
        payload: const {},
      );

      expect(result['count'], 7);
      expect(result['_scriptError'], isNotNull);
      expect(result['lastAction'], 'inc');
    });
  });
}
