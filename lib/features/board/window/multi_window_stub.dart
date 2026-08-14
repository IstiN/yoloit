/// Stub for desktop_multi_window when running in test environment.
/// The real desktop_multi_window package is not available in tests.
class WindowController {
  Future<void> setFrame(dynamic rect) async {}
  Future<void> setTitle(String title) async {}
  Future<void> show() async {}
}

class DesktopMultiWindow {
  static Future<WindowController> createWindow(List<String> args) async {
    throw UnsupportedError('desktop_multi_window not available in tests');
  }
}
