import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

/// Generic placeholder shown when a panel requires capabilities the current
/// runtime does not have (e.g. terminal on web, media player on mobile).
class UnsupportedCapabilityPanel extends StatelessWidget {
  const UnsupportedCapabilityPanel({
    required this.plugin,
    super.key,
  });

  final BoardPanelPlugin plugin;

  String get _capabilityLabel {
    final labels = plugin.requiredCapabilities
        .where(
          (capability) => !PlatformCapabilities.current.has(capability),
        )
        .map(_formatCapability)
        .toList();

    if (labels.isEmpty) {
      return 'a native desktop feature';
    }
    if (labels.length == 1) {
      return labels.first;
    }
    return '${labels.take(labels.length - 1).join(', ')} and ${labels.last}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(16),
      color: colors.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.desktop_mac_outlined, size: 40, color: colors.textMuted),
          const SizedBox(height: 12),
          Text(
            'Available in YoLoIT for macOS',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${plugin.displayName} requires $_capabilityLabel and is not available in the browser.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatCapability(PlatformCapability capability) {
    return switch (capability) {
      PlatformCapability.filesystem => 'local file system access',
      PlatformCapability.processes => 'native process execution',
      PlatformCapability.nativeTerminal => 'a terminal shell',
      PlatformCapability.nativeMediaPlayback => 'native media playback',
      PlatformCapability.secureStorage => 'secure credential storage',
      PlatformCapability.networkServer => 'a local network server',
      PlatformCapability.windowManagement => 'window management',
      PlatformCapability.clipboardFiles => 'clipboard file access',
    };
  }
}

/// Convenience extension so any plugin can build its unsupported placeholder.
extension UnsupportedPanelExtension on BoardPanelPlugin {
  Widget buildUnsupportedPanel() => UnsupportedCapabilityPanel(plugin: this);
}

/// Convenience constructor for building a placeholder panel from raw metadata.
///
/// Used by history restore or remote sync when the real plugin class is not
/// registered on the current platform.
class UnsupportedCapabilityPanelByMetadata extends StatelessWidget {
  const UnsupportedCapabilityPanelByMetadata({
    required this.displayName,
    required this.requiredCapabilities,
    super.key,
  });

  final String displayName;
  final Set<PlatformCapability> requiredCapabilities;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(16),
      color: colors.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.desktop_mac_outlined, size: 40, color: colors.textMuted),
          const SizedBox(height: 12),
          Text(
            'Available in YoLoIT for macOS',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$displayName requires native desktop features and is not available in the browser.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
