import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

final _webpageDefaultColors = AppColorScheme.fromAccent(Colors.lightBlue);

/// Shared static caches and metadata for the Webpage plugin.
///
/// VM and web implementations extend this base and provide their own
/// [buildContent] / controller implementations. Keeping the caches and
/// metadata in one place removes duplication between VM and web files.
abstract class WebpagePluginBase extends BoardPanelPlugin {
  const WebpagePluginBase();

  static const String kTypeId = 'board.webpage';

  /// Shared controller cache so the board view can render WebViews
  /// outside the InteractiveViewer transform to avoid coordinate offset.
  ///
  /// VM stores [WebViewController]; web stores no-op dynamic values.
  static final Map<String, dynamic> controllers = {};

  /// Last known CSS zoom per panel (= board scale at gesture-end).
  static final Map<String, double> pendingCssZoom = {};

  /// Target JS viewport width per panel (375/768/1280).
  static final Map<String, double> viewportTargets = {};

  /// Loading state per panel.
  static final Map<String, ValueNotifier<bool>> pageLoading = {};

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Webpage';

  @override
  IconData get icon => Icons.language_outlined;

  @override
  Color get accentColor => _webpageDefaultColors.accentBlue;

  @override
  Size get defaultSize => const Size(700, 500);

  @override
  Map<String, dynamic> get initialState => {
    'url': '',
    'title': '',
    'favicon': '',
  };

  @override
  bool get hasEditor => false;
}
