import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:yoloit/features/board/widgets/js_widget_flame_3d_host.dart';

void main() {
  group('createYoloitFlame3dHost', () {
    test('creates a Flame3dHost', () {
      expect(createYoloitFlame3dHost(), isA<Flame3dHost>());
    });
  });

  group('Flame3dController', () {
    test('queues commands while GPU initializes', () {
      fakeAsync((async) {
        final controller = Flame3dHost.instance.createController(
          's1',
          <String, dynamic>{},
        ) as Flame3dController;

        controller.apply(
          const Js3dCommand(
            kind: 'addModel',
            sceneId: 's1',
            modelId: 'helmet',
            payload: {'src': 'models/helmet.glb'},
          ),
        );

        // The command should be queued synchronously before async init runs.
        expect(controller.pendingLength, 1);
        expect(controller.hasGame, isFalse);

        // Let the async GPU initialization complete. In a test environment
        // Impeller/GPU is unavailable, so this surfaces as an error rather
        // than a game instance.
        async.elapse(const Duration(seconds: 1));
        expect(controller.error, isNotNull);
        expect(controller.pendingLength, 0);

        controller.dispose();
      });
    });

    test('multiple commands are queued and initialization starts once', () {
      fakeAsync((async) {
        final controller = Flame3dHost.instance.createController(
          's1',
          <String, dynamic>{},
        ) as Flame3dController;

        controller.apply(
          const Js3dCommand(
            kind: 'addModel',
            sceneId: 's1',
            modelId: 'helmet',
            payload: {'src': 'models/helmet.glb'},
          ),
        );
        controller.apply(
          const Js3dCommand(
            kind: 'playAnimation',
            sceneId: 's1',
            modelId: 'helmet',
            payload: {'axis': 'y', 'speed': 2.0},
          ),
        );
        controller.apply(
          const Js3dCommand(
            kind: 'setCamera',
            sceneId: 's1',
            modelId: 'helmet',
            payload: {
              'position': [0.0, 0.0, 10.0],
              'target': [0.0, 0.0, 0.0],
              'fov': 45.0,
            },
          ),
        );

        expect(controller.pendingLength, 3);
        async.elapse(const Duration(seconds: 1));
        expect(controller.error, isNotNull);
        expect(controller.pendingLength, 0);

        controller.dispose();
      });
    });

    test('does not queue after error', () {
      fakeAsync((async) {
        final controller = Flame3dHost.instance.createController(
          's1',
          <String, dynamic>{},
        ) as Flame3dController;

        controller.apply(
          const Js3dCommand(kind: 'addModel', sceneId: 's1', modelId: 'a'),
        );
        async.elapse(const Duration(seconds: 1));
        expect(controller.error, isNotNull);

        controller.apply(
          const Js3dCommand(kind: 'removeModel', sceneId: 's1', modelId: 'a'),
        );
        expect(controller.pendingLength, 0);

        controller.dispose();
      });
    });

    test('shares controller by sceneId between JS bridge and renderer', () {
      fakeAsync((async) {
        final first = Flame3dHost.instance.createController(
          'shared',
          <String, dynamic>{},
        );
        final second = Flame3dHost.instance.createController(
          'shared',
          <String, dynamic>{},
        );
        expect(identical(first, second), isTrue);

        first.apply(
          const Js3dCommand(
            kind: 'addModel',
            sceneId: 'shared',
            modelId: 'helmet',
          ),
        );
        expect((second as Flame3dController).pendingLength, 1);

        first.dispose();
        // One reference remains, so the controller is still alive.
        expect(second.pendingLength, 1);

        second.dispose();
        async.elapse(const Duration(seconds: 1));
      });
    });
  });
}
