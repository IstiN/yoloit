import 'dart:async';

import 'package:flame/game.dart';
import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/game.dart';
import 'package:flame_3d/graphics.dart';
import 'package:flame_3d/model.dart';
import 'package:flame_3d/parser.dart';
import 'package:flutter/material.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';

/// Creates a [Js3dHost] implementation backed by `flame_3d`.
///
/// Supports GLB/GLTF/OBJ models with animations and lighting. This host
/// requires Impeller + Flutter GPU, so it only runs on Android, iOS, and
/// macOS. On other platforms the panel shows a fallback message.
Js3dHost createYoloitFlame3dHost() => Flame3dHost.instance;

/// {@template flame3d_host}
/// A [Js3dHost] that drives a `flame_3d` scene from JS commands.
/// {@endtemplate}
class Flame3dHost extends Js3dHost {
  Flame3dHost._();

  /// Singleton instance shared by the JS bridge and the widget renderer.
  static final Flame3dHost instance = Flame3dHost._();

  final Map<String, Flame3dController> _controllers = {};

  bool _gpuInitialized = false;

  Future<void> _ensureGpu() async {
    if (_gpuInitialized) return;
    await GpuBackend.initialize();
    _gpuInitialized = true;
  }

  @override
  Js3dController createController(
    String sceneId,
    Map<String, dynamic> config,
  ) {
    final existing = _controllers[sceneId];
    if (existing != null && !existing._disposed) {
      existing._addRef();
      debugPrint(
        '[Flame3dHost] reuse controller sceneId=$sceneId '
        'refCount=${existing._refCount}',
      );
      return existing;
    }
    final controller = Flame3dController(sceneId, config, this);
    _controllers[sceneId] = controller;
    debugPrint(
      '[Flame3dHost] create controller sceneId=$sceneId '
      'configKeys=${config.keys.toList()}',
    );
    return controller;
  }

  bool _release(Flame3dController controller) {
    if (controller._releaseRef() == 0) {
      _controllers.remove(controller.sceneId);
      controller._disposeInternal();
      return true;
    }
    return false;
  }

  @override
  Widget build(
    BuildContext context,
    Js3dController controller,
    Map<String, dynamic> config,
  ) {
    final c = controller as Flame3dController;
    return _Flame3dGameWidget(controller: c);
  }
}

/// {@template flame3d_controller}
/// A [Js3dController] implementation that backs a `flame_3d` scene.
/// {@endtemplate}
class Flame3dController extends Js3dController {
  Flame3dController(this.sceneId, this.config, this._host);

  final String sceneId;
  final Map<String, dynamic> config;
  final Flame3dHost _host;

  YoloitFlame3dGame? game;
  String? error;
  final List<Js3dCommand> _pending = [];
  bool _initializing = false;
  bool _disposed = false;
  int _refCount = 1;

  void _addRef() => _refCount++;
  int _releaseRef() => --_refCount;

  /// Test helper exposing whether the game was created.
  @visibleForTesting
  bool get hasGame => game != null;

  /// Test helper exposing how many commands are queued before the game loads.
  @visibleForTesting
  int get pendingLength => _pending.length;

  @override
  void apply(Js3dCommand command) {
    if (_disposed) return;
    debugPrint(
      '[Flame3dController] apply sceneId=$sceneId kind=${command.kind} '
      'hasGame=${game != null} error=$error pending=${_pending.length}',
    );
    if (game == null && error == null) {
      _pending.add(command);
      _initGameIfNeeded();
      return;
    }
    if (game == null) return;
    _apply(command);
    notifyListeners();
  }

  void _initGameIfNeeded() {
    if (_disposed || _initializing || game != null || error != null) return;
    _initializing = true;
    debugPrint('[Flame3dController] init game sceneId=$sceneId');
    _host._ensureGpu().then((_) async {
      if (_disposed || game != null) return;
      debugPrint('[Flame3dController] game created sceneId=$sceneId');
      game = YoloitFlame3dGame(
        config,
        onError: (message) {
          if (_disposed) return;
          error = message;
          debugPrint('[Flame3dController] error sceneId=$sceneId: $message');
          notifyListeners();
        },
      );
      for (final cmd in _pending) {
        _apply(cmd);
      }
      _pending.clear();
      if (!_disposed) notifyListeners();
    }).catchError((Object e) {
      if (_disposed) return;
      error = 'flame_3d unavailable: $e';
      debugPrint('[Flame3dController] init error sceneId=$sceneId: $e');
      _pending.clear();
      notifyListeners();
    });
  }

  void _apply(Js3dCommand command) {
    final payload = command.payload ?? {};
    final modelId =
        (payload['modelId'] as String?) ?? command.modelId ?? 'default';

    switch (command.kind) {
      case 'addModel':
        debugPrint(
          '[Flame3dController] addModel sceneId=$sceneId modelId=$modelId '
          'src=${payload['src']}',
        );
        game?.loadModel(
          modelId: modelId,
          src: payload['src'] as String?,
          position: payload['position'] as List?,
          rotation: payload['rotation'] as List?,
          scale: payload['scale'] as List?,
        );
      case 'removeModel':
        game?.removeModel(modelId);
      case 'setTransform':
        game?.setTransform(
          modelId,
          position: payload['position'] as List?,
          rotation: payload['rotation'] as List?,
          scale: payload['scale'] as List?,
        );
      case 'playAnimation':
        final axis = payload['axis'] as String? ?? 'y';
        final speed = (payload['speed'] as num?)?.toDouble() ?? 1.0;
        game?.setRotation(modelId, axis, speed);
      case 'stopAnimation':
        game?.stopRotation(modelId);
      case 'setCamera':
        _applyCamera(payload);
      case 'setLight':
        _applyLight(payload);
    }
  }

  void _applyCamera(Map<String, dynamic>? cam) {
    final camera = game?.camera;
    if (cam == null || camera is! CameraComponent3D) return;
    _readVec3(cam['position'] as List?)?.let(camera.position.setFrom);
    _readVec3(cam['target'] as List?)?.let(camera.target.setFrom);
    _readVec3(cam['up'] as List?)
        ?.let((Vector3 v) => camera.up.setFrom(v));
    final fov = (cam['fov'] as num?)?.toDouble();
    if (fov != null) camera.fovY = fov;
  }

  void _applyLight(Map<String, dynamic>? light) {
    // Runtime light mutation is not exposed by flame_3d; lights are configured
    // once when the game loads.
  }

  @override
  void dispose() {
    final lastReference = _host._release(this);
    if (lastReference) {
      super.dispose();
    }
  }

  void _disposeInternal() {
    _disposed = true;
    game?.dispose();
  }
}

/// {@template yoloit_flame3d_game}
/// A small [FlameGame3D] that loads a single GLB/GLTF/OBJ model and rotates it.
/// {@endtemplate}
class YoloitFlame3dGame extends FlameGame3D<World3D, CameraComponent3D> {
  YoloitFlame3dGame(
    this.config, {
    this.onError,
  }) : super(
        world: World3D(),
        camera: CameraComponent3D(
          position: Vector3(0, 0, 8),
          target: Vector3.zero(),
          fovY: 60,
        ),
      );



  final Map<String, dynamic> config;
  final void Function(String)? onError;
  final Map<String, ModelComponent> _models = {};
  final Map<String, _Rotation> _rotations = {};

  @override
  FutureOr<void> onLoad() async {
    await super.onLoad();

    final cameraConfig = config['camera'] as Map<String, dynamic>?;
    if (cameraConfig != null) {
      _readVec3(cameraConfig['position'] as List?)
          ?.let(camera.position.setFrom);
      _readVec3(cameraConfig['target'] as List?)?.let(camera.target.setFrom);
      final fov = (cameraConfig['fov'] as num?)?.toDouble();
      if (fov != null) camera.fovY = fov;
    }

    final lightConfig = config['light'] as Map<String, dynamic>?;
    final ambientIntensity =
        (lightConfig?['ambient'] as num?)?.toDouble() ?? 0.4;
    final diffuseIntensity =
        (lightConfig?['diffuse'] as num?)?.toDouble() ?? 0.8;
    debugPrint(
      '[Flame3dGame] adding lights ambient=$ambientIntensity '
      'diffuse=$diffuseIntensity',
    );
    world.addAll([
      LightComponent.ambient(
        color: _parseColor(lightConfig?['color'] as String? ?? '#ffffff'),
        intensity: ambientIntensity,
      ),
      LightComponent.point(
        position: _readVec3(lightConfig?['position'] as List?) ??
            Vector3(5, 10, 5),
        color: _parseColor(lightConfig?['color'] as String? ?? '#ffffff'),
        intensity: diffuseIntensity,
      ),
    ]);
  }

  Future<void> loadModel({
    required String modelId,
    required String? src,
    List<dynamic>? position,
    List<dynamic>? rotation,
    List<dynamic>? scale,
  }) async {
    if (src == null || src.isEmpty) return;

    removeModel(modelId);

    debugPrint('[Flame3dGame] loadModel modelId=$modelId src=$src');
    try {
      final model = await ModelParser.parse(src);
      debugPrint(
        '[Flame3dGame] model parsed modelId=$modelId '
        'nodes=${model.nodes.length} animations=${model.animations.length}',
      );
      final component = ModelComponent(
        model: model,
        position: _readVec3(position) ?? Vector3.zero(),
        rotation: _quaternionFromEuler(_readVec3(rotation) ?? Vector3.zero()),
        scale: _readVec3(scale) ?? Vector3.all(1),
      );
      _models[modelId] = component;
      world.add(component);
      debugPrint(
        '[Flame3dGame] model added modelId=$modelId '
        'worldChildren=${world.children.length}',
      );
    } catch (e) {
      final message = 'Failed to load model "$src": $e';
      debugPrint('[Flame3dGame] $message');
      onError?.call(message);
    }
  }

  void removeModel(String modelId) {
    final existing = _models.remove(modelId);
    if (existing != null) {
      world.remove(existing);
    }
    _rotations.remove(modelId);
  }

  void setTransform(
    String modelId, {
    List<dynamic>? position,
    List<dynamic>? rotation,
    List<dynamic>? scale,
  }) {
    final model = _models[modelId];
    if (model == null) return;
    _readVec3(position)?.let(model.position.setFrom);
    _readVec3(rotation)?.let((Vector3 v) {
      model.rotation.setFrom(_quaternionFromEuler(v));
    });
    _readVec3(scale)?.let(model.scale.setFrom);
  }

  void setRotation(String modelId, String axis, double speed) {
    _rotations[modelId] = _Rotation(axis: axis, speed: speed);
  }

  void stopRotation(String modelId) {
    _rotations.remove(modelId);
  }

  @override
  void update(double dt) {
    super.update(dt);
    for (final entry in _rotations.entries) {
      final model = _models[entry.key];
      if (model == null) continue;
      final rot = entry.value;
      final axis = switch (rot.axis) {
        'x' => Vector3(1, 0, 0),
        'y' => Vector3(0, 1, 0),
        'z' || _ => Vector3(0, 0, 1),
      };
      final delta = rot.speed * dt * 360 * degrees2Radians;
      final q = Quaternion.axisAngle(axis, delta);
      model.rotation.setFrom(model.rotation * q);
    }
  }
}

class _Rotation {
  _Rotation({required this.axis, required this.speed});
  final String axis;
  final double speed;
}



class _ErrorWidget extends StatelessWidget {
  const _ErrorWidget({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color.fromARGB(255, 239, 68, 68),
          ),
        ),
      ),
    );
  }
}

/// A widget that owns the [GameWidget] lifecycle for a [Flame3dController].
///
/// Keeping [GameWidget] in a single persistent child avoids the
/// "game instance can only be attached to one widget at a time" error that
/// occurs when [ListenableBuilder] recreates the game widget on every
/// controller notification.
class _Flame3dGameWidget extends StatefulWidget {
  const _Flame3dGameWidget({required this.controller});

  final Flame3dController controller;

  @override
  State<_Flame3dGameWidget> createState() => _Flame3dGameWidgetState();
}

class _Flame3dGameWidgetState extends State<_Flame3dGameWidget> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _Flame3dGameWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    debugPrint(
      '[Flame3dHost] build sceneId=${c.sceneId} '
      'hasGame=${c.game != null} error=${c.error}',
    );
    if (c.error != null) {
      return _ErrorWidget(message: c.error!);
    }
    final game = c.game;
    if (game == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return GameWidget(game: game, addRepaintBoundary: false);
  }
}

Color _parseColor(String value) {
  var hex = value.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 6) {
    final rgb = int.tryParse(hex, radix: 16);
    if (rgb != null) {
      return Color.fromARGB(
        255,
        (rgb >> 16) & 0xff,
        (rgb >> 8) & 0xff,
        rgb & 0xff,
      );
    }
  }
  return const Color.fromARGB(255, 59, 130, 246);
}

Vector3? _readVec3(List<dynamic>? value) {
  if (value == null || value.length < 3) return null;
  return Vector3(
    (value[0] as num).toDouble(),
    (value[1] as num).toDouble(),
    (value[2] as num).toDouble(),
  );
}

Quaternion _quaternionFromEuler(Vector3 eulerDegrees) {
  final yaw = eulerDegrees.y * degrees2Radians;
  final pitch = eulerDegrees.x * degrees2Radians;
  final roll = eulerDegrees.z * degrees2Radians;
  return Quaternion.euler(pitch, yaw, roll);
}

extension _Vector3Let on Vector3 {
  void let(void Function(Vector3) action) => action(this);
}
