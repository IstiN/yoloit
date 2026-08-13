import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/url_opener.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/ui/components/chip/toolbar_chip.dart';

class BoardToolbar extends StatelessWidget {
  const BoardToolbar({
    super.key,
    required this.board,
    required this.onCreateBoard,
    required this.onCreateBoardFromTemplate,
    required this.onConnectRemote,
    required this.onShareBoard,
    required this.onBoardSettings,
    this.onAppSettings,
    this.onPopOutBoard,
    required this.onDeleteBoard,
    required this.onOpenBoardOverview,
    required this.onSearch,
  });

  final BoardDocument board;
  final VoidCallback onCreateBoard;
  final VoidCallback onCreateBoardFromTemplate;
  final VoidCallback onConnectRemote;
  final VoidCallback onShareBoard;
  final VoidCallback onBoardSettings;
  final VoidCallback? onAppSettings;
  final VoidCallback? onPopOutBoard;
  final VoidCallback onDeleteBoard;
  final VoidCallback onOpenBoardOverview;
  final VoidCallback onSearch;

  bool get _remoteBoard => isRemoteBoard(board);
  String get _deleteTooltip =>
      _remoteBoard ? 'Disconnect remote board' : 'Delete board';
  String get _deleteLabel => _remoteBoard ? 'Disconnect' : 'Delete';
  IconData get _deleteIcon =>
      _remoteBoard ? Icons.link_off_rounded : Icons.delete_outline;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final phone = constraints.maxWidth < 560;
        final horizontalPadding = phone ? 8.0 : 16.0;
        final gap = phone ? 6.0 : 12.0;
        return Container(
          decoration: BoxDecoration(
            color: kIsWeb ? colors.surface : colors.surface.withAlpha(31),
            border: Border(
              bottom: BorderSide(color: colors.border.withAlpha(128)),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              phone ? 8 : 12,
              horizontalPadding,
              phone ? 8 : 12,
            ),
            child: Row(
              children: [
                ..._buildBoardSwitcher(compact: compact, phone: phone),
                ..._buildFolderChip(compact: compact),
                SizedBox(width: gap),
                ..._buildSearchArea(context, compact: compact, phone: phone),
                if (compact) const Spacer() else const SizedBox(width: 16),
                ..._buildActions(context, compact: compact, phone: phone),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildBoardSwitcher({
    required bool compact,
    required bool phone,
  }) {
    return [
      if (compact)
        Flexible(
          child: BoardSwitcherButton(
            board: board,
            onOpenBoardOverview: onOpenBoardOverview,
            compact: phone,
          ),
        )
      else
        BoardSwitcherButton(
          board: board,
          onOpenBoardOverview: onOpenBoardOverview,
        ),
    ];
  }

  List<Widget> _buildFolderChip({required bool compact}) {
    return [
      if (!compact && board.defaultFolder.isNotEmpty) ...[
        const SizedBox(width: 12),
        ToolbarChip(
          icon: Icons.folder_outlined,
          label: _shortToolbarPath(board.defaultFolder),
        ),
      ],
    ];
  }

  List<Widget> _buildSearchArea(
    BuildContext context, {
    required bool compact,
    required bool phone,
  }) {
    return [
      if (!compact)
        Expanded(
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onSearch,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.appColors.border),
                    color: context.appColors.surface,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search,
                        size: 18,
                        color: context.appColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Search boards and panels…',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.appColors.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        defaultTargetPlatform == TargetPlatform.macOS
                            ? '⌘O'
                            : 'Ctrl+O',
                        style: TextStyle(
                          color: context.appColors.textMuted.withAlpha(120),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )
      else if (!phone)
        Tooltip(
          message: 'Search boards and panels',
          child: IconButton(
            onPressed: onSearch,
            icon: const Icon(Icons.search),
          ),
        ),
    ];
  }

  List<Widget> _buildActions(
    BuildContext context, {
    required bool compact,
    required bool phone,
  }) {
    if (phone) return [_buildPhoneActionsMenu()];
    if (compact) return _buildCompactActions();
    return _buildFullActions(context);
  }

  void _onPhoneMenuSelected(String value) {
    final actions = <String, VoidCallback?>{
      'search': onSearch,
      'new': onCreateBoard,
      'newFromTemplate': onCreateBoardFromTemplate,
      'remote': onConnectRemote,
      'share': onShareBoard,
      'download': () => unawaited(launchExternalUrl(_downloadReleasesUrl)),
      'settings': onBoardSettings,
      'appSettings': onAppSettings,
      'delete': onDeleteBoard,
    };
    actions[value]?.call();
  }

  Widget _buildPhoneActionsMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Board actions',
      icon: const Icon(Icons.more_horiz),
      onSelected: _onPhoneMenuSelected,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'search',
          child: Text('Search boards and panels'),
        ),
        const PopupMenuItem(value: 'new', child: Text('Blank board')),
        const PopupMenuItem(
          value: 'newFromTemplate',
          child: Text('From template...'),
        ),
        const PopupMenuItem(
          value: 'remote',
          child: Text('Connect remote YoLoIT'),
        ),
        const PopupMenuItem(value: 'share', child: Text('Share board')),
        if (kIsWeb)
          const PopupMenuItem(
            value: 'download',
            child: Text('Download YoLoIT'),
          ),
        const PopupMenuItem(value: 'settings', child: Text('Settings')),
        if (onAppSettings != null)
          const PopupMenuItem(
            value: 'appSettings',
            child: Text('YoLoIT settings'),
          ),
        PopupMenuItem(value: 'delete', child: Text(_deleteLabel)),
      ],
    );
  }

  List<Widget> _buildCompactActions() {
    return [
      _NewBoardMenuButton(
        onCreateBoard: onCreateBoard,
        onCreateBoardFromTemplate: onCreateBoardFromTemplate,
        compact: true,
      ),
      IconButton(
        tooltip: 'Connect remote YoLoIT',
        onPressed: onConnectRemote,
        icon: const Icon(Icons.cloud_outlined),
      ),
      IconButton(
        tooltip: 'Share board',
        onPressed: onShareBoard,
        icon: const Icon(Icons.ios_share_outlined),
      ),
      // Pop-out button only in full layout — compact is too narrow.
      if (kIsWeb) const _DownloadReleasesButton(compact: true),
      IconButton(
        tooltip: 'Board settings',
        onPressed: onBoardSettings,
        icon: const Icon(Icons.settings_outlined),
      ),
      IconButton(
        tooltip: _deleteTooltip,
        onPressed: onDeleteBoard,
        icon: Icon(_deleteIcon),
      ),
    ];
  }

  List<Widget> _buildFullActions(BuildContext context) {
    return [
      _NewBoardMenuButton(
        onCreateBoard: onCreateBoard,
        onCreateBoardFromTemplate: onCreateBoardFromTemplate,
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        style: _toolbarButtonStyle(context, isWeb: kIsWeb),
        onPressed: onConnectRemote,
        icon: const Icon(Icons.cloud_outlined),
        label: const Text('Remote'),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        style: _toolbarButtonStyle(context, isWeb: kIsWeb),
        onPressed: onShareBoard,
        icon: const Icon(Icons.ios_share_outlined),
        label: const Text('Share'),
      ),
      if (onPopOutBoard != null && !kIsWeb) ...[
        const SizedBox(width: 8),
        OutlinedButton.icon(
          style: _toolbarButtonStyle(context, isWeb: kIsWeb),
          onPressed: onPopOutBoard,
          icon: const Icon(Icons.open_in_new_outlined),
          label: const Text('Window'),
        ),
      ],
      if (kIsWeb) ...[
        const SizedBox(width: 8),
        const _DownloadReleasesButton(),
      ],
      const SizedBox(width: 8),
      OutlinedButton.icon(
        style: _toolbarButtonStyle(context, isWeb: kIsWeb),
        onPressed: onBoardSettings,
        icon: const Icon(Icons.settings_outlined),
        label: const Text('Settings'),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        style: _toolbarButtonStyle(context, isWeb: kIsWeb),
        onPressed: onDeleteBoard,
        icon: Icon(_deleteIcon),
        label: Text(_deleteLabel),
      ),
    ];
  }

  static ButtonStyle _toolbarButtonStyle(
    BuildContext context, {
    required bool isWeb,
  }) {
    final colors = context.appColors;
    return OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      foregroundColor: isWeb ? colors.textSecondary : null,
      iconColor: isWeb ? colors.textSecondary : null,
      side: isWeb ? BorderSide(color: colors.border) : null,
    );
  }

  static String _shortToolbarPath(String path) {
    final normalized = path.trim();
    if (normalized.length <= 28) return normalized;
    final parts = normalized.split(p.context.separator);
    if (parts.length >= 2) return '…${p.context.separator}${parts.last}';
    return '…${normalized.substring(normalized.length - 27)}';
  }
}

class _NewBoardMenuButton extends StatelessWidget {
  const _NewBoardMenuButton({
    required this.onCreateBoard,
    required this.onCreateBoardFromTemplate,
    this.compact = false,
  });

  final VoidCallback onCreateBoard;
  final VoidCallback onCreateBoardFromTemplate;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = MenuController();
    return MenuAnchor(
      controller: controller,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.add),
          onPressed: onCreateBoard,
          child: const Text('Blank board'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.dashboard_customize_outlined),
          onPressed: onCreateBoardFromTemplate,
          child: const Text('From template...'),
        ),
      ],
      builder: (context, controller, child) {
        if (compact) {
          return IconButton(
            tooltip: 'New board',
            onPressed: () => _toggle(controller),
            icon: const Icon(Icons.add),
          );
        }
        return OutlinedButton.icon(
          style: BoardToolbar._toolbarButtonStyle(context, isWeb: kIsWeb),
          onPressed: () => _toggle(controller),
          icon: const Icon(Icons.add),
          label: const Text('New board'),
        );
      },
    );
  }

  void _toggle(MenuController controller) {
    if (controller.isOpen) {
      controller.close();
    } else {
      controller.open();
    }
  }
}

const String _downloadReleasesUrl =
    'https://github.com/IstiN/yoloit/releases/latest';

class _DownloadReleasesButton extends StatelessWidget {
  const _DownloadReleasesButton({this.compact = false});

  final bool compact;

  Future<void> _openReleases() => launchExternalUrl(_downloadReleasesUrl);

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: 'Download YoLoIT',
        onPressed: _openReleases,
        icon: const Icon(Icons.download_outlined),
      );
    }
    return OutlinedButton.icon(
      style: BoardToolbar._toolbarButtonStyle(context, isWeb: kIsWeb),
      onPressed: _openReleases,
      icon: const Icon(Icons.download_outlined),
      label: const Text('Download'),
    );
  }
}

class BoardSwitcherButton extends StatelessWidget {
  const BoardSwitcherButton({
    super.key,
    required this.board,
    required this.onOpenBoardOverview,
    this.compact = false,
  });

  final BoardDocument board;
  final VoidCallback onOpenBoardOverview;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (colors, textColor, mutedColor) = boardTextColors(context);
    return Tooltip(
      message: 'Open boards overview',
      child: InkWell(
        onTap: onOpenBoardOverview,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 36,
          constraints: BoxConstraints(
            minWidth: compact ? 0 : 160,
            maxWidth: compact ? 220 : 260,
          ),
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                size: 16,
                color: mutedColor,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  board.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.expand_more, size: 18, color: mutedColor),
            ],
          ),
        ),
      ),
    );
  }
}
