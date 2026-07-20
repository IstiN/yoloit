import 'package:js_widget_runtime/js_widget_runtime.dart';

import 'package:yoloit/features/board/widgets/js_widget_media_kit_audio.dart';
import 'package:yoloit/features/board/widgets/js_widget_media_kit_video.dart';

/// Creates a [JsMediaHost] that uses `media_kit` for video and audio nodes.
JsMediaHost createYoloitMediaHost() => _YoloitMediaHost();

class _YoloitMediaHost extends JsMediaHost {
  @override
  JsVideoController createVideoController(String src) =>
      MediaKitVideoController.async(src);

  @override
  JsAudioController createAudioController(String src) =>
      MediaKitAudioController.async(src);
}
