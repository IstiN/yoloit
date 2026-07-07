import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/plugins/board_panel_plugin_base.dart';

final _playlistDefaultColors = AppColorScheme.fromAccent(Colors.deepPurple);

/// Shared metadata for the media playlist panel plugin.
abstract class PlaylistPluginBase extends BoardPanelPluginBase {
  const PlaylistPluginBase()
    : super(
        typeId: kTypeId,
        displayName: 'Playlist',
        icon: Icons.queue_music_rounded,
        defaultSize: const Size(380, 480),
        initialState: const {
          'tracks': <Map<String, dynamic>>[],
          'currentIndex': 0,
          'repeat': false,
          'shuffle': false,
        },
        supportsHeadlessRender: false,
        requiredCapabilities: const {
          PlatformCapability.nativeMediaPlayback,
          PlatformCapability.filesystem,
        },
      );

  static const String kTypeId = 'board.playlist';

  @override
  Color get accentColor => _playlistDefaultColors.primary;
}
