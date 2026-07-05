import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/unsupported_capability_panel.dart';

final _playlistDefaultColors = AppColorScheme.fromAccent(Colors.deepPurple);

/// Web stub for the media playlist panel.
///
/// Keeps the same metadata and type id so existing boards deserialize; the
/// content renders a placeholder because browsers cannot use the native MPV
/// media backend.
class PlaylistPlugin extends BoardPanelPlugin {
  const PlaylistPlugin();

  static const String kTypeId = 'board.playlist';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Playlist';

  @override
  IconData get icon => Icons.queue_music_rounded;

  @override
  Color get accentColor => _playlistDefaultColors.primary;

  @override
  Size get defaultSize => const Size(380, 480);

  @override
  Map<String, dynamic> get initialState => const {
        'tracks': <Map<String, dynamic>>[],
        'currentIndex': 0,
        'repeat': false,
        'shuffle': false,
      };

  @override
  bool get supportsHeadlessRender => false;

  @override
  Set<PlatformCapability> get requiredCapabilities => const {
        PlatformCapability.nativeMediaPlayback,
        PlatformCapability.filesystem,
      };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return buildUnsupportedPanel();
  }
}
