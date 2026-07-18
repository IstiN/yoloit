import 'package:flutter/widgets.dart';
// ignore: implementation_imports
import 'package:js_widget_runtime/src/renderer/nodes/image_provider_resolver_stub.dart'
    if (dart.library.io) 'package:js_widget_runtime/src/renderer/nodes/image_provider_resolver_io.dart'
    if (dart.library.html) 'package:js_widget_runtime/src/renderer/nodes/image_provider_resolver_web.dart';

/// Creates an [imageResolver] for [JsonWidgetRenderer] that maps host-side
/// references such as `external:<id>` to real image providers.
///
/// The returned resolver returns `null` for anything it does not recognise so
/// the renderer can fall back to its own `asset:` / `file:` / network logic.
ImageProvider? Function(String source) createExternalImageResolver(
  Map<String, dynamic> panelState,
) {
  return (source) {
    if (source.startsWith('external:')) {
      final id = source.substring('external:'.length);
      final files = (panelState['_externalFiles'] as Map?)
          ?.cast<String, String>();
      final path = files?[id];
      if (path != null && path.isNotEmpty) {
        return resolveFileImageProvider(path);
      }
    }
    return null;
  };
}
