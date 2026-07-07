import 'dart:io';

abstract class ChatSoundHelper {
  static Future<void> play() async {
    try {
      await Process.run('afplay', ['/System/Library/Sounds/Glass.aiff']);
    } catch (_) {
      // ignore sound playback failures
    }
  }
}
