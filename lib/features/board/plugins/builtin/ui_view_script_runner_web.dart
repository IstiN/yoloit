import 'package:js_widget_runtime/js_widget_runtime.dart';

/// Web stub for [UiViewScriptRunner].
///
/// The VM runner uses `flutter_js` to execute on-tap scripts, which is not
/// available on web. The stub falls back to the default no-script behavior:
/// it applies the tap event to panel storage without running JS.
class UiViewScriptRunner {
  UiViewScriptRunner._();

  static final UiViewScriptRunner instance = UiViewScriptRunner._();

  Map<String, dynamic> runAction({
    required String script,
    required Map<String, dynamic> storage,
    required String actionId,
    required Map<String, dynamic> payload,
  }) {
    return UiViewBindings.applyEventToStorage(
      storage: storage,
      actionId: actionId,
      payload: payload,
    );
  }
}
