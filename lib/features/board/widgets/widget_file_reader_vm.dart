import 'dart:io';

import 'package:js_widget_runtime/js_widget_runtime.dart';

/// Returns the platform-specific default [WidgetFileReader].
WidgetFileReader get defaultWidgetFileReader => VmWidgetFileReader.instance;

/// [WidgetFileReader] backed by the local filesystem on VM targets.
class VmWidgetFileReader implements WidgetFileReader {
  /// Shared instance used by [WidgetRegistryService].
  static final VmWidgetFileReader instance = VmWidgetFileReader._();
  VmWidgetFileReader._();

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Future<String?> readString(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsString();
  }
}
