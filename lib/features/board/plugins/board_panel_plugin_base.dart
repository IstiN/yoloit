import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

/// A convenience base class for built-in plugins that carry their metadata as
/// final fields rather than as a long list of getters.
///
/// Subclasses only need to provide [buildContent]; everything else can be
/// supplied once through the constructor. [accentColor] and
/// [buildIconWidget] remain overridable getters so plugins that compute them
/// from a non-const theme helper can still keep a const constructor.
abstract class BoardPanelPluginBase extends BoardPanelPlugin {
  const BoardPanelPluginBase({
    required this.typeId,
    required this.displayName,
    required this.icon,
    this.defaultSize = const Size(360, 220),
    this.initialState = const {},
    this.showInCatalog = true,
    this.showHeader = true,
    this.usePanelChrome = true,
    this.hasEditor = false,
    this.contentPadding = const EdgeInsets.all(12),
    this.supportsHeadlessRender = true,
    this.requiredCapabilities = const {},
  });

  @override
  final String typeId;

  @override
  final String displayName;

  @override
  final IconData icon;

  @override
  Color get accentColor => Colors.transparent;

  @override
  final Size defaultSize;

  @override
  final Map<String, dynamic> initialState;

  @override
  final bool showInCatalog;

  @override
  final bool showHeader;

  @override
  final bool usePanelChrome;

  @override
  final bool hasEditor;

  @override
  final EdgeInsets contentPadding;

  @override
  final bool supportsHeadlessRender;

  @override
  final Set<PlatformCapability> requiredCapabilities;
}
