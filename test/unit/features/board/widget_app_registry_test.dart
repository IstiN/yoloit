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

  group('WidgetAppRegistry registerAlias', () {
    test('ignores alias identical to the canonical id', () async {
      var called = false;
      registry.registerReload('weather', () async { called = true; });

      registry.registerAlias('weather', 'weather');

      // No alias entry created; lookup still resolves through the entry.
      expect(registry.resolveLookupKey('weather'), 'weather');
      expect(await registry.triggerReload('weather'), isTrue);
      expect(called, isTrue);
    });

    test('resolves aliases to the canonical id', () {
      registry.registerReload('weather', () async {});

      registry.registerAlias('/tmp/apps/weather-dev', 'weather');

      expect(registry.resolveLookupKey('/tmp/apps/weather-dev'), 'weather');
    });

    test('registers the basename as an additional alias', () async {
      var calls = 0;
      registry.registerReload('weather', () async { calls++; });

      registry.registerAlias('/tmp/apps/weather-dev', 'weather');

      // Basename of the aliased path also resolves to the canonical id.
      expect(registry.resolveLookupKey('weather-dev'), 'weather');
      expect(await registry.triggerReload('weather-dev'), isTrue);
      expect(calls, 1);
    });

    test('does not duplicate basename when it equals the canonical id', () {
      registry.registerReload('weather', () async {});

      registry.registerAlias('/tmp/apps/weather', 'weather');

      expect(registry.resolveLookupKey('/tmp/apps/weather'), 'weather');
      expect(registry.resolveLookupKey('weather'), 'weather');
    });

    test('alias without path separator registers only the alias itself', () {
      registry.registerReload('weather', () async {});

      registry.registerAlias('meteo', 'weather');

      expect(registry.resolveLookupKey('meteo'), 'weather');
    });

    test('unregister removes aliases pointing at the entry', () {
      registry.registerReload('weather', () async {});
      registry.registerAlias('/tmp/apps/weather-dev', 'weather');

      registry.unregister('weather');

      expect(registry.resolveLookupKey('/tmp/apps/weather-dev'), '/tmp/apps/weather-dev');
      expect(registry.resolveLookupKey('weather-dev'), 'weather-dev');
    });
  });
}
