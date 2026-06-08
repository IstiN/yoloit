import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:yoloit/core/services/support_log_service.dart';
import 'package:yoloit/core/utils/svg_utils.dart';

/// Rasterized diagram data holder.
class MermaidRasterizedDiagram {
  const MermaidRasterizedDiagram({
    required this.svg,
    required this.png,
    required this.aspectRatio,
    required this.imageProvider,
  });

  final String svg;
  final Uint8List png;
  final double aspectRatio;
  final MemoryImage imageProvider;
}

/// LRU cache for rendered Mermaid diagrams.
///
/// Keys are computed from diagram source, target width and theme variant.
class MermaidRasterizedDiagramCache {
  static const int _maxEntries = 24;
  static final LinkedHashMap<String, Future<MermaidRasterizedDiagram>> _entries =
      LinkedHashMap<String, Future<MermaidRasterizedDiagram>>();
  static final LinkedHashMap<String, MermaidRasterizedDiagram> _resolved =
      LinkedHashMap<String, MermaidRasterizedDiagram>();
  static bool _renderMethodCallbackSet = false;

  static String keyFor(String code, double width, {String variant = ''}) =>
      '${width.round()}:$variant:${code.length}:${code.hashCode}';

  static bool contains(String key) => _entries.containsKey(key);

  static MermaidRasterizedDiagram? peek(
    String code,
    double width, {
    String variant = '',
  }) {
    final key = keyFor(code, width, variant: variant);
    final existing = _resolved.remove(key);
    if (existing == null) return null;
    _resolved[key] = existing;
    return existing;
  }

  static Future<MermaidRasterizedDiagram> load({
    required MermaidRenderer renderer,
    required String code,
    required double width,
    required MermaidRenderOptions options,
    String variant = '',
  }) {
    if (!_renderMethodCallbackSet) {
      _renderMethodCallbackSet = true;
      MermaidRenderer.onRenderMethod = (String method, String details) {
        SupportLogService.instance.add(
          'mermaid-render',
          'method=$method details=$details',
        );
      };
    }

    final key = keyFor(code, width, variant: variant);
    final existing = _entries.remove(key);
    if (existing != null) {
      debugPrint('[MermaidCache] HIT key=$key entries=${_entries.length + 1}');
      _entries[key] = existing;
      return existing;
    }

    debugPrint('[MermaidCache] MISS key=$key entries=${_entries.length}');
    final stopwatch = Stopwatch()..start();
    final future = () async {
      final svg = await renderer.renderToSvg(code, options: options);
      final png = await MermaidRenderer.svgToPng(
        svg,
        width: width,
        backgroundColor: options.backgroundColor,
      );
      final aspectRatio = parseSvgAspectRatio(svg);
      final imageProvider = MemoryImage(png);
      stopwatch.stop();
      final fontFamily = options.config?['fontFamily'] as String?;
      debugPrint(
        '[MermaidCache] STORE key=$key ms=${stopwatch.elapsedMilliseconds} pngBytes=${png.length} svgLength=${svg.length} fontFamily=$fontFamily',
      );
      final diagram = MermaidRasterizedDiagram(
        svg: svg,
        png: png,
        aspectRatio: aspectRatio,
        imageProvider: imageProvider,
      );
      _resolved[key] = diagram;
      _entries[key] = SynchronousFuture<MermaidRasterizedDiagram>(diagram);
      return diagram;
    }();

    _entries[key] = future;
    while (_entries.length > _maxEntries) {
      final eldestKey = _entries.keys.first;
      _entries.remove(eldestKey);
      _resolved.remove(eldestKey);
      debugPrint(
        '[MermaidCache] EVICT key=$eldestKey entries=${_entries.length}',
      );
    }
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          final removed = _entries.remove(key);
          if (removed != null) {
            _resolved.remove(key);
            debugPrint('[MermaidCache] DROP FAILED key=$key error=$error');
          }
        },
      ),
    );
    return future;
  }
}
