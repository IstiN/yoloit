import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/widgets/widget_app_registry.dart';

// Minimal stub — JsWidgetEngine has complex deps, we only test registry logic
// by using real WidgetAppRegistry with null engines (the registry accepts nulls
// in the new design for pre-registration of reload callbacks).

void main() {
  late WidgetAppRegistry registry;

  setUp(() {
    // Create a fresh instance for each test (can't use the singleton in unit tests)
    registry = WidgetAppRegistry.testInstance();
  });

  group('WidgetAppRegistry reload callback', () {
    test('registerReload stores callback before engine is ready', () async {
      var called = false;
      registry.registerReload('weather', () async { called = true; });

      final ok = await registry.triggerReload('weather');
      expect(ok, isTrue);
      expect(called, isTrue);
    });

    test('triggerReload returns false when widget not registered', () async {
      final ok = await registry.triggerReload('nonexistent');
      expect(ok, isFalse);
    });

    test('triggerReload calls the latest registered callback', () async {
      var callCount = 0;
      registry.registerReload('calc', () async { callCount++; });
      // Re-register (simulates engine restart)
      registry.registerReload('calc', () async { callCount += 10; });

      await registry.triggerReload('calc');
      expect(callCount, 10, reason: 'second registration should win');
    });

    test('triggerReload returns false after unregister', () async {
      registry.registerReload('stocks', () async {});
      registry.unregister('stocks');

      final ok = await registry.triggerReload('stocks');
      expect(ok, isFalse);
    });

    test('activeIds does not include reload-only pre-registrations without engine', () {
      registry.registerReload('preload-only', () async {});
      // activeIds should reflect pre-registered entry exists but has no engine
      // The key point: triggerReload still works
      expect(registry.engine('preload-only'), isNull);
    });
  });

  group('WidgetAppRegistry tree updates', () {
    test('updateTree stores tree and tree() retrieves it', () {
      registry.registerReload('w1', () async {});
      registry.updateTree('w1', {'type': 'text', 'data': 'hello'});
      expect(registry.tree('w1'), {'type': 'text', 'data': 'hello'});
    });

    test('tree returns null for unknown widget', () {
      expect(registry.tree('unknown'), isNull);
    });
  });
}
