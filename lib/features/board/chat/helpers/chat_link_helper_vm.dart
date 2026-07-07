import 'package:yoloit/core/platform/platform_launcher.dart';

abstract class ChatLinkHelper {
  static Future<void> open(String url) async {
    try {
      await PlatformLauncher.instance.openUrl(url);
    } catch (_) {
      // ignore link open failures
    }
  }
}
