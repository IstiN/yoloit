import 'package:fake_async/fake_async.dart';
import 'package:flutter_cube/flutter_cube.dart' as cube;
import 'package:flutter_test/flutter_test.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:yoloit/features/board/widgets/js_widget_cube_3d_host.dart';

void main() {
  group('createYoloitCube3dHost', () {
    test('creates a Cube3dHost', () {
      expect(createYoloitCube3dHost(), isA<Cube3dHost>());
    });

    test('controller applies commands after scene is created', () {
      final controller = createYoloitCube3dHost().createController(
        's1',
        <String, dynamic>{},
      ) as Cube3dController;

      var updates = 0;
      final scene = cube.Scene(onUpdate: () => updates++);
      controller.onSceneCreated(scene);

      controller.apply(
        const Js3dCommand(
          kind: 'addModel',
          sceneId: 's1',
          modelId: 'box',
          payload: {
            'primitive': 'cube',
            'color': '#ef4444',
            'scale': [2.0, 2.0, 2.0],
          },
        ),
      );

      expect(controller.objects, contains('box'));
      expect(updates, greaterThan(0));

      controller.apply(
        const Js3dCommand(
          kind: 'setTransform',
          sceneId: 's1',
          modelId: 'box',
          payload: {
            'position': [1.0, 0.0, 0.0],
            'rotation': [0.0, 45.0, 0.0],
          },
        ),
      );
      expect(controller.object('box')!.position.x, 1.0);

      controller.apply(
        const Js3dCommand(
          kind: 'playAnimation',
          sceneId: 's1',
          modelId: 'box',
          payload: {'axis': 'y', 'speed': 1.0},
        ),
      );
      controller.apply(
        const Js3dCommand(
          kind: 'setCamera',
          sceneId: 's1',
          payload: {
            'position': [0.0, 0.0, -12.0],
            'target': [0.0, 0.0, 0.0],
            'fov': 45.0,
          },
        ),
      );
      expect(scene.camera.fov, 45.0);

      controller.apply(
        const Js3dCommand(
          kind: 'setLight',
          sceneId: 's1',
          payload: {
            'position': [5.0, 5.0, 5.0],
            'color': '#00ff00',
          },
        ),
      );
      expect(scene.light.position.x, 5.0);

      controller.apply(
        const Js3dCommand(
          kind: 'removeModel',
          sceneId: 's1',
          modelId: 'box',
        ),
      );
      expect(controller.objects, isNot(contains('box')));

      controller.dispose();
    });

    test('controller queues commands until scene is ready', () {
      final controller = createYoloitCube3dHost().createController(
        's1',
        <String, dynamic>{},
      ) as Cube3dController;

      controller.apply(
        const Js3dCommand(
          kind: 'addModel',
          sceneId: 's1',
          modelId: 'sphere',
          payload: {'primitive': 'sphere'},
        ),
      );

      expect(controller.objects, isEmpty);
      expect(controller.pendingLength, 1);

      controller.onSceneCreated(cube.Scene());
      expect(controller.objects, contains('sphere'));
      expect(controller.pendingLength, 0);

      controller.dispose();
    });

    test('controller creates city primitive with many faces', () {
      final controller = createYoloitCube3dHost().createController(
        's1',
        <String, dynamic>{},
      ) as Cube3dController;

      controller.onSceneCreated(cube.Scene());
      controller.apply(
        const Js3dCommand(
          kind: 'addModel',
          sceneId: 's1',
          modelId: 'city',
          payload: {'primitive': 'city'},
        ),
      );

      final city = controller.object('city')!;
      expect(city.mesh.indices.length, greaterThan(100));
      expect(city.backfaceCulling, isTrue);

      controller.dispose();
    });

    test('animation speed changes rotation rate', () {
      fakeAsync((async) {
        final controller = createYoloitCube3dHost().createController(
          's1',
          <String, dynamic>{},
        ) as Cube3dController;

        controller.onSceneCreated(cube.Scene());
        controller.apply(
          const Js3dCommand(
            kind: 'addModel',
            sceneId: 's1',
            modelId: 'box',
            payload: {'primitive': 'cube'},
          ),
        );
        controller.apply(
          const Js3dCommand(
            kind: 'playAnimation',
            sceneId: 's1',
            modelId: 'box',
            payload: {'axis': 'y', 'speed': 1.0},
          ),
        );

        async.elapse(const Duration(milliseconds: 100));
        final rot1 = controller.object('box')!.rotation.y;

        controller.apply(
          const Js3dCommand(
            kind: 'playAnimation',
            sceneId: 's1',
            modelId: 'box',
            payload: {'axis': 'y', 'speed': 3.0},
          ),
        );
        async.elapse(const Duration(milliseconds: 100));
        final rot2 = controller.object('box')!.rotation.y;

        // Speed tripled, so the second 100ms interval should rotate ~3x more.
        expect(rot2 - rot1, closeTo(rot1 * 3, 15.0));

        controller.dispose();
      });
    });

  });
}

extension _TestableController on Cube3dController {
  cube.Object? object(String id) => objects[id];
}
