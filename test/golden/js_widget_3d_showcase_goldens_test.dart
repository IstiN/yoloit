import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:yoloit/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget shell({required Widget child}) {
    return MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        backgroundColor: AppThemePreset.neonPurple.theme.colorScheme.surface,
        body: Center(
          child: SizedBox(
            width: 320,
            height: 320,
            child: child,
          ),
        ),
      ),
    );
  }

  group('Golden tests — 3D showcases', () {
    testGoldens('cube 3D showcase renders a colored cube', (tester) async {
      await tester.pumpWidgetBuilder(
        shell(
          child: const _CubeGoldenWidget(
            sceneId: 'cube-golden',
            config: <String, dynamic>{
              'camera': {
                'position': [0.0, 0.0, -6.0],
                'target': [0.0, 0.0, 0.0],
                'fov': 60.0,
              },
              'light': {
                'position': [5.0, 8.0, 5.0],
                'color': '#ffffff',
                'ambient': 0.4,
                'diffuse': 0.7,
              },
            },
            commands: [
              Js3dCommand(
                kind: 'addModel',
                sceneId: 'cube-golden',
                modelId: 'box',
                payload: {
                  'primitive': 'cube',
                  'color': '#3b82f6',
                  'scale': [2.0, 2.0, 2.0],
                },
              ),
            ],
          ),
        ),
        surfaceSize: const Size(320, 320),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await screenMatchesGolden(tester, 'cube_3d_showcase');
    });

    testGoldens('flame 3D showcase shows loading indicator before GPU init', (
      tester,
    ) async {
      final controller = Flame3dHost.instance.createController(
        'flame-golden',
        <String, dynamic>{},
      ) as Flame3dController;
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        shell(
          child: Builder(
            builder: (context) => Flame3dHost.instance.build(
              context,
              controller,
              <String, dynamic>{},
            ),
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/flame_3d_showcase_loading.png'),
      );
    });
  });
}

class _CubeGoldenWidget extends StatefulWidget {
  const _CubeGoldenWidget({
    required this.sceneId,
    required this.config,
    required this.commands,
  });

  final String sceneId;
  final Map<String, dynamic> config;
  final List<Js3dCommand> commands;

  @override
  State<_CubeGoldenWidget> createState() => _CubeGoldenWidgetState();
}

class _CubeGoldenWidgetState extends State<_CubeGoldenWidget> {
  late final Cube3dController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Cube3dHost.instance.createController(
      widget.sceneId,
      widget.config,
    ) as Cube3dController;
    for (final cmd in widget.commands) {
      _controller.apply(cmd);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Cube3dHost.instance.build(context, _controller, widget.config);
  }
}
