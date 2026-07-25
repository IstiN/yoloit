import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_cube/flutter_cube.dart' as cube;
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

/// Creates a [Js3dHost] implementation backed by `flutter_cube`.
///
/// Supports procedural primitives (`cube`, `sphere`, `torus`) and Wavefront
/// `.obj` assets/files. This host works on all Flutter platforms because
/// `flutter_cube` renders with a [CustomPainter] instead of platform views.
Js3dHost createYoloitCube3dHost() => Cube3dHost.instance;

/// {@template cube3d_host}
/// A [Js3dHost] that drives a `flutter_cube` scene from JS commands.
///
/// The runtime creates one controller when JS calls `jsr.scene3d.create()` and
/// a second controller when the `scene3d` node is rendered. Because both sides
/// must mutate the same scene, this host caches controllers by [sceneId] and
/// returns the same instance to both the JS bridge and the widget renderer.
/// {@endtemplate}
class Cube3dHost extends Js3dHost {
  Cube3dHost._();

  /// Singleton instance shared by the JS bridge and the widget renderer.
  static final Cube3dHost instance = Cube3dHost._();

  final Map<String, Cube3dController> _controllers = {};

  @override
  Js3dController createController(
    String sceneId,
    Map<String, dynamic> config,
  ) {
    final existing = _controllers[sceneId];
    if (existing != null && !existing._disposed) {
      existing._addRef();
      return existing;
    }
    final controller = Cube3dController._(sceneId, config);
    _controllers[sceneId] = controller;
    return controller;
  }

  void _release(Cube3dController controller) {
    if (controller._releaseRef() == 0) {
      _controllers.remove(controller.sceneId);
      controller._disposeInternal();
    }
  }

  @override
  Widget build(
    BuildContext context,
    Js3dController controller,
    Map<String, dynamic> config,
  ) {
    final c = controller as Cube3dController;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => cube.Cube(
        onSceneCreated: c.onSceneCreated,
        interactive: config['interactive'] != false,
      ),
    );
  }
}

/// {@template cube3d_controller}
/// A [Js3dController] implementation that backs a `flutter_cube` scene.
///
/// Exposed as public only for unit testing; the host returns it through the
/// abstract [Js3dController] interface.
/// {@endtemplate}
class Cube3dController extends Js3dController {
  Cube3dController._(this.sceneId, this.config);

  final String sceneId;
  final Map<String, dynamic> config;

  cube.Scene? _scene;
  final Map<String, cube.Object> _objects = {};
  final List<Js3dCommand> _pending = [];
  final Map<String, _Animation> _animations = {};
  Timer? _animationTimer;
  bool _disposed = false;
  int _refCount = 1;

  void _addRef() => _refCount++;
  int _releaseRef() => --_refCount;

  /// Test helpers exposing internal controller state.
  @visibleForTesting
  Map<String, cube.Object> get objects => Map.unmodifiable(_objects);

  @visibleForTesting
  int get pendingLength => _pending.length;

  void onSceneCreated(cube.Scene scene) {
    if (_disposed) return;
    _scene = scene;
    _applyCamera(config['camera'] as Map<String, dynamic>?);
    _applyLight(config['light'] as Map<String, dynamic>?);
    for (final cmd in _pending) {
      _apply(cmd);
    }
    _pending.clear();
    _startAnimationLoop();
    notifyListeners();
  }

  @override
  void apply(Js3dCommand command) {
    if (_scene == null) {
      _pending.add(command);
      return;
    }
    _apply(command);
  }

  void _apply(Js3dCommand command) {
    final payload = command.payload ?? {};
    final modelId =
        (payload['modelId'] as String?) ?? command.modelId ?? 'default';

    switch (command.kind) {
      case 'addModel':
        _addModel(
          modelId: modelId,
          src: payload['src'] as String?,
          primitive: payload['primitive'] as String? ?? 'cube',
          color: payload['color'] as String? ?? '#3b82f6',
          position: payload['position'] as List?,
          rotation: payload['rotation'] as List?,
          scale: payload['scale'] as List?,
        );
      case 'removeModel':
        final existing = _objects.remove(modelId);
        if (existing != null) {
          _scene?.world.remove(existing);
          _scene?.update();
        }
      case 'setTransform':
        final existing = _objects[modelId];
        if (existing != null) {
          _vec3(payload['position'] as List?)?.copyInto(existing.position);
          _vec3(payload['rotation'] as List?)?.copyInto(existing.rotation);
          _vec3(payload['scale'] as List?)?.copyInto(existing.scale);
          existing.updateTransform();
          _scene?.update();
        }
      case 'playAnimation':
        final axis = payload['axis'] as String? ?? 'y';
        final speed = (payload['speed'] as num?)?.toDouble() ?? 1.0;
        _animations[modelId] = _Animation(axis: axis, speed: speed);
      case 'stopAnimation':
        _animations.remove(modelId);
      case 'setCamera':
        _applyCamera(payload);
      case 'setLight':
        _applyLight(payload);
    }
    notifyListeners();
  }

  void _addModel({
    required String modelId,
    required String? src,
    required String primitive,
    required String color,
    required List<dynamic>? position,
    required List<dynamic>? rotation,
    required List<dynamic>? scale,
  }) {
    final scene = _scene;
    if (scene == null) return;

    final parsedColor = _parseColor(color);
    final mesh = src == null ? _primitiveMesh(primitive, parsedColor) : null;
    final obj = cube.Object(
      position: _vec3(position) ?? Vector3.zero(),
      rotation: _vec3(rotation) ?? Vector3.zero(),
      scale: _vec3(scale) ?? Vector3.all(1),
      mesh: mesh,
      backfaceCulling: false,
      lighting: true,
    );

    if (src != null) {
      final isAsset = src.startsWith('assets/');
      cube.loadObj(src, true, isAsset: isAsset).then((meshes) {
        if (meshes.isNotEmpty) {
          obj.mesh = meshes.first;
          _applyMaterialColor(obj, parsedColor);
        }
        obj.updateTransform();
        _scene?.update();
      });
    } else {
      _applyMaterialColor(obj, parsedColor);
    }

    _objects[modelId] = obj;
    scene.world.add(obj);
    scene.update();
  }

  void _applyMaterialColor(cube.Object obj, Color color) {
    // flutter_cube material channels are in the 0-1 range, not 0-255.
    final v = Vector3(
      color.red / 255,
      color.green / 255,
      color.blue / 255,
    );
    obj.mesh.material.diffuse = v;
    obj.mesh.material.ambient = v * 0.2;
    obj.mesh.material.specular = Vector3.all(0.5);
  }

  void _applyCamera(Map<String, dynamic>? cam) {
    final scene = _scene;
    if (scene == null || cam == null) return;
    _vec3(cam['position'] as List?)?.copyInto(scene.camera.position);
    _vec3(cam['target'] as List?)?.copyInto(scene.camera.target);
    _vec3(cam['up'] as List?)?.copyInto(scene.camera.up);
    final fov = (cam['fov'] as num?)?.toDouble();
    if (fov != null) scene.camera.fov = fov;
    final zoom = (cam['zoom'] as num?)?.toDouble();
    if (zoom != null) scene.camera.zoom = zoom;
    scene.update();
  }

  void _applyLight(Map<String, dynamic>? light) {
    final scene = _scene;
    if (scene == null || light == null) return;
    _vec3(light['position'] as List?)?.copyInto(scene.light.position);
    final color = _parseColor(light['color'] as String? ?? '#ffffff');
    final ambient = (light['ambient'] as num?)?.toDouble() ?? 0.1;
    final diffuse = (light['diffuse'] as num?)?.toDouble() ?? 0.8;
    final specular = (light['specular'] as num?)?.toDouble() ?? 0.5;
    scene.light.setColor(color, ambient, diffuse, specular);
    scene.update();
  }

  void _startAnimationLoop() {
    _animationTimer?.cancel();
    _animationTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        if (_disposed || _animations.isEmpty) return;
        var changed = false;
        for (final entry in _animations.entries) {
          final obj = _objects[entry.key];
          if (obj == null) continue;
          final anim = entry.value;
          final delta = anim.speed * 16 / 1000 * 360;
          switch (anim.axis) {
            case 'x':
              obj.rotation.x = (obj.rotation.x + delta) % 360;
            case 'y':
              obj.rotation.y = (obj.rotation.y + delta) % 360;
            case 'z':
              obj.rotation.z = (obj.rotation.z + delta) % 360;
          }
          obj.updateTransform();
          changed = true;
        }
        if (changed) _scene?.update();
      },
    );
  }

  @override
  void dispose() {
    Cube3dHost.instance._release(this);
  }

  void _disposeInternal() {
    _disposed = true;
    _animationTimer?.cancel();
    super.dispose();
  }
}

class _Animation {
  _Animation({required this.axis, required this.speed});
  final String axis;
  final double speed;
}

Vector3? _vec3(List<dynamic>? value) {
  if (value == null || value.length < 3) return null;
  return Vector3(
    (value[0] as num).toDouble(),
    (value[1] as num).toDouble(),
    (value[2] as num).toDouble(),
  );
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
  return Colors.blue;
}

// ═════════════════════════════════════════════════════════════════════════════
// Procedural meshes
// ═════════════════════════════════════════════════════════════════════════════

cube.Mesh _primitiveMesh(String primitive, Color color) {
  switch (primitive) {
    case 'sphere':
      return _sphereMesh();
    case 'torus':
      return _torusMesh();
    case 'cube':
    default:
      return _cubeMesh();
  }
}

cube.Mesh _cubeMesh() {
  // A simple cube with per-face vertices so flat shading looks correct.
  const s = 1.0;
  final vertices = <Vector3>[
    // Front
    Vector3(-s, -s, s), Vector3(s, -s, s), Vector3(s, s, s), Vector3(-s, s, s),
    // Back
    Vector3(s, -s, -s), Vector3(-s, -s, -s), Vector3(-s, s, -s), Vector3(s, s, -s),
    // Top
    Vector3(-s, s, s), Vector3(s, s, s), Vector3(s, s, -s), Vector3(-s, s, -s),
    // Bottom
    Vector3(-s, -s, -s), Vector3(s, -s, -s), Vector3(s, -s, s), Vector3(-s, -s, s),
    // Right
    Vector3(s, -s, s), Vector3(s, -s, -s), Vector3(s, s, -s), Vector3(s, s, s),
    // Left
    Vector3(-s, -s, -s), Vector3(-s, -s, s), Vector3(-s, s, s), Vector3(-s, s, -s),
  ];
  final indices = <cube.Polygon>[];
  for (var i = 0; i < 6; i++) {
    final o = i * 4;
    indices.add(cube.Polygon(o, o + 1, o + 2));
    indices.add(cube.Polygon(o, o + 2, o + 3));
  }
  return cube.Mesh(vertices: vertices, indices: indices);
}

cube.Mesh _sphereMesh({int subdivisions = 2}) {
  // Build an icosphere: no degenerate pole triangles, smooth uniform faces.
  const phi = 1.618033988749895; // golden ratio
  final vertices = <Vector3>[
    Vector3(-1, phi, 0).normalized(),
    Vector3(1, phi, 0).normalized(),
    Vector3(-1, -phi, 0).normalized(),
    Vector3(1, -phi, 0).normalized(),
    Vector3(0, -1, phi).normalized(),
    Vector3(0, 1, phi).normalized(),
    Vector3(0, -1, -phi).normalized(),
    Vector3(0, 1, -phi).normalized(),
    Vector3(phi, 0, -1).normalized(),
    Vector3(phi, 0, 1).normalized(),
    Vector3(-phi, 0, -1).normalized(),
    Vector3(-phi, 0, 1).normalized(),
  ];
  var faces = <_Face>[
    _Face(0, 11, 5),
    _Face(0, 5, 1),
    _Face(0, 1, 7),
    _Face(0, 7, 10),
    _Face(0, 10, 11),
    _Face(1, 5, 9),
    _Face(5, 11, 4),
    _Face(11, 10, 2),
    _Face(10, 7, 6),
    _Face(7, 1, 8),
    _Face(3, 9, 4),
    _Face(3, 4, 2),
    _Face(3, 2, 6),
    _Face(3, 6, 8),
    _Face(3, 8, 9),
    _Face(4, 9, 5),
    _Face(2, 4, 11),
    _Face(6, 2, 10),
    _Face(8, 6, 7),
    _Face(9, 8, 1),
  ];

  final midCache = <_MidKey, int>{};
  int mid(int a, int b) {
    final key = a < b ? _MidKey(a, b) : _MidKey(b, a);
    final cached = midCache[key];
    if (cached != null) return cached;
    final m = ((vertices[a] + vertices[b]) * 0.5).normalized();
    vertices.add(m);
    final index = vertices.length - 1;
    midCache[key] = index;
    return index;
  }

  for (var s = 0; s < subdivisions; s++) {
    final next = <_Face>[];
    for (final f in faces) {
      final a = mid(f.i0, f.i1);
      final b = mid(f.i1, f.i2);
      final c = mid(f.i2, f.i0);
      next
        ..add(_Face(f.i0, a, c))
        ..add(_Face(f.i1, b, a))
        ..add(_Face(f.i2, c, b))
        ..add(_Face(a, b, c));
    }
    faces = next;
  }

  final indices = faces
      .map((f) => cube.Polygon(f.i0, f.i1, f.i2))
      .toList();
  return cube.Mesh(vertices: vertices, indices: indices);
}

cube.Mesh _torusMesh({int majorSegments = 32, int minorSegments = 16, double majorRadius = 1.0, double minorRadius = 0.35}) {
  final vertices = <Vector3>[];
  final indices = <cube.Polygon>[];
  for (var i = 0; i <= majorSegments; i++) {
    final u = i * 2 * pi / majorSegments;
    final cosU = cos(u);
    final sinU = sin(u);
    for (var j = 0; j <= minorSegments; j++) {
      final v = j * 2 * pi / minorSegments;
      final cosV = cos(v);
      final sinV = sin(v);
      vertices.add(
        Vector3(
          (majorRadius + minorRadius * cosV) * cosU,
          minorRadius * sinV,
          (majorRadius + minorRadius * cosV) * sinU,
        ),
      );
    }
  }
  for (var i = 0; i < majorSegments; i++) {
    for (var j = 0; j < minorSegments; j++) {
      final a = i * (minorSegments + 1) + j;
      final b = a + minorSegments + 1;
      // Winding produces outward-facing normals.
      indices.add(cube.Polygon(a, a + 1, b));
      indices.add(cube.Polygon(b, a + 1, b + 1));
    }
  }
  return cube.Mesh(vertices: vertices, indices: indices);
}

class _Face {
  _Face(this.i0, this.i1, this.i2);
  final int i0;
  final int i1;
  final int i2;
}

class _MidKey {
  _MidKey(this.a, this.b);
  final int a;
  final int b;

  @override
  bool operator ==(Object other) =>
      other is _MidKey && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);
}
