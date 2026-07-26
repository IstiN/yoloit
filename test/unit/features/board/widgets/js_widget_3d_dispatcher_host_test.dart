import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:yoloit/features/board/widgets/js_widget_3d_dispatcher_host.dart';

void main() {
  group('createYoloitJs3dHost', () {
    test('returns a YoloitJs3dDispatcherHost', () {
      expect(createYoloitJs3dHost(), isA<YoloitJs3dDispatcherHost>());
    });
  });

  group('YoloitJs3dDispatcherHost', () {
    test('selects flame host when engine is flame', () {
      final host = createYoloitJs3dHost() as YoloitJs3dDispatcherHost;
      final selected = host.selectHost(<String, dynamic>{'engine': 'flame'});
      expect(selected.toString(), contains('Flame3dHost'));
    });

    test('selects flame host for glb src', () {
      final host = createYoloitJs3dHost() as YoloitJs3dDispatcherHost;
      final selected = host.selectHost(<String, dynamic>{
        'src': 'assets/models/helmet.glb',
      });
      expect(selected.toString(), contains('Flame3dHost'));
    });

    test('selects flame host for gltf src', () {
      final host = createYoloitJs3dHost() as YoloitJs3dDispatcherHost;
      final selected = host.selectHost(<String, dynamic>{
        'model': <String, dynamic>{'src': 'assets/models/helmet.gltf'},
      });
      expect(selected.toString(), contains('Flame3dHost'));
    });

    test('selects cube host for primitives without engine', () {
      final host = createYoloitJs3dHost() as YoloitJs3dDispatcherHost;
      final selected = host.selectHost(<String, dynamic>{
        'primitive': 'cube',
      });
      expect(selected.toString(), contains('Cube3dHost'));
    });

    test('forwards apply calls to the inner controller', () {
      final inner = _FakeController();
      final fakeHost = _FakeHost(inner);
      final dispatcher = _TestDispatcher(fakeHost);
      final controller = dispatcher.createController('s1', <String, dynamic>{})
          as _TestHostedController;

      controller.apply(
        const Js3dCommand(kind: 'addModel', sceneId: 's1', modelId: 'box'),
      );

      expect(inner.applied.length, 1);
      expect(inner.applied.first.kind, 'addModel');
    });

    test('returns same controller for same sceneId regardless of config', () {
      final host = createYoloitJs3dHost() as YoloitJs3dDispatcherHost;

      final bridgeController = host.createController(
        'glb-demo',
        <String, dynamic>{
          'engine': 'flame',
          'camera': <String, dynamic>{'position': [0.0, 0.0, -8.0]},
        },
      );
      final rendererController = host.createController(
        'glb-demo',
        <String, dynamic>{'width': 320, 'height': 320},
      );

      expect(identical(bridgeController, rendererController), isTrue);

      bridgeController.dispose();
    });
  });
}

class _FakeController extends Js3dController {
  final List<Js3dCommand> applied = [];

  @override
  void apply(Js3dCommand command) => applied.add(command);
}

class _FakeHost extends Js3dHost {
  _FakeHost(this.controller);
  final Js3dController controller;

  @override
  Js3dController createController(
    String sceneId,
    Map<String, dynamic> config,
  ) =>
      controller;

  @override
  Widget build(
    BuildContext context,
    Js3dController controller,
    Map<String, dynamic> config,
  ) =>
      const SizedBox.shrink();
}

class _TestDispatcher extends Js3dHost {
  _TestDispatcher(this._fakeHost);
  final Js3dHost _fakeHost;

  @override
  Js3dController createController(
    String sceneId,
    Map<String, dynamic> config,
  ) =>
      _TestHostedController(_fakeHost.createController(sceneId, config));

  @override
  Widget build(
    BuildContext context,
    Js3dController controller,
    Map<String, dynamic> config,
  ) =>
      const SizedBox.shrink();
}

class _TestHostedController extends Js3dController {
  _TestHostedController(this.controller);
  final Js3dController controller;

  @override
  void apply(Js3dCommand command) => controller.apply(command);
}
