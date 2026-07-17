import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';

/// Returns the platform-specific default [WidgetFileReader].
WidgetFileReader get defaultWidgetFileReader => WebWidgetFileReader.instance;

/// [WidgetFileReader] backed by [FileStorageAdapter] on web targets.
class WebWidgetFileReader implements WidgetFileReader {
  WebWidgetFileReader._({FileStorageAdapter? adapter})
    : _adapter = adapter ?? FileStorageAdapter.instance;

  static final WebWidgetFileReader instance = WebWidgetFileReader._();

  factory WebWidgetFileReader({FileStorageAdapter? adapter}) =>
      WebWidgetFileReader._(adapter: adapter);

  final FileStorageAdapter _adapter;

  @override
  Future<bool> exists(String path) => _adapter.exists(path);

  @override
  Future<String?> readString(String path) => _adapter.readString(path);
}
