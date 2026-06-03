import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';

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

  static double parseAspectRatio(String svg) {
    final match = RegExp(r'viewBox="([^"]+)"').firstMatch(svg);
    if (match != null) {
      final parts = match.group(1)!.trim().split(RegExp(r'[\s,]+'));
      if (parts.length == 4) {
        final width = double.tryParse(parts[2]);
        final height = double.tryParse(parts[3]);
        if (width != null && height != null && width > 0 && height > 0) {
          return width / height;
        }
      }
    }
    return 16 / 9;
  }

  static Future<MermaidRasterizedDiagram> load({
    required MermaidRenderer renderer,
    required String code,
    required double width,
    required MermaidRenderOptions options,
    String variant = '',
  }) {
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
      final aspectRatio = parseAspectRatio(svg);
      final imageProvider = MemoryImage(png);
      stopwatch.stop();
      debugPrint(
        '[MermaidCache] STORE key=$key ms=${stopwatch.elapsedMilliseconds} pngBytes=${png.length}',
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
