import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/utils/http_client.dart';

/// Fetches built-in example widgets from a GitHub raw-content URL so the web
/// app can load them without relying on the local file system.
///
/// The default source is the `tools/widgets/` directory of the `IstiN/yoloit`
/// repository on the `main` branch. Each widget is expected to contain at
/// least `manifest.json` and `widget.js`.
class WidgetRemoteSource {
  WidgetRemoteSource({
    String? baseUrl,
    YoloitHttpClient? client,
  }) : _baseUrl = (baseUrl ?? _defaultBaseUrl).replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? YoloitHttpClientImpl();

  static const _defaultBaseUrl =
      'https://raw.githubusercontent.com/IstiN/yoloit/main/tools/widgets';

  final String _baseUrl;
  final YoloitHttpClient _client;

  /// Names of the bundled example widgets that are also published to GitHub.
  static const exampleNames = [
    'weather',
    'crypto',
    'stocks',
    'calculator',
    'yolo-hello',
    'animation-showcase',
    '3d-showcase',
  ];

  /// Fetches [name] from the remote source and returns a map of relative file
  /// paths to file contents. Returns `null` if the widget could not be loaded.
  Future<Map<String, String>?> fetchWidget(String name) async {
    final manifest = await _fetchText('$name/manifest.json');
    if (manifest == null) {
      assert(() {
        debugPrint('[WidgetRemoteSource] missing manifest for $name');
        return true;
      }());
      return null;
    }

    final files = <String, String>{'manifest.json': manifest};

    // If the manifest declares an ordered file list, fetch those files;
    // otherwise just fetch widget.js.
    final extraFiles = _filesFromManifest(manifest);
    if (extraFiles != null && extraFiles.isNotEmpty) {
      for (final filename in extraFiles) {
        final content = await _fetchText('$name/$filename');
        if (content != null) files[filename] = content;
      }
    } else {
      final widgetJs = await _fetchText('$name/widget.js');
      if (widgetJs == null) {
        assert(() {
          debugPrint('[WidgetRemoteSource] missing widget.js for $name');
          return true;
        }());
        return null;
      }
      files['widget.js'] = widgetJs;
    }

    return files;
  }

  /// Fetches all known example widgets from the remote source.
  ///
  /// Returns a map of widget id to file map. Individual widget failures are
  /// skipped so partial network outages do not block the whole list.
  Future<Map<String, Map<String, String>>> fetchAllExamples() async {
    final result = <String, Map<String, String>>{};
    for (final name in exampleNames) {
      final files = await fetchWidget(name);
      if (files != null) result[name] = files;
    }
    return result;
  }

  void close() => _client.close();

  Future<String?> _fetchText(String relativePath) async {
    final url = '$_baseUrl/$relativePath';
    return _client.getString(url, timeout: const Duration(seconds: 15));
  }

  List<String>? _filesFromManifest(String manifestJson) {
    try {
      final raw = jsonDecode(manifestJson) as Map<String, dynamic>;
      final files = raw['files'] as List?;
      if (files == null) return null;
      return List<String>.from(files);
    } catch (_) {
      return null;
    }
  }
}
