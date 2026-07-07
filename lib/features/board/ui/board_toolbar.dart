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
  final VoidCallback onDeleteBoard;
  final VoidCallback onOpenBoardOverview;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final remoteBoard = isRemoteBoard(board);
    final deleteTooltip = remoteBoard
        ? 'Disconnect remote board'
        : 'Delete board';
    final deleteLabel = remoteBoard ? 'Disconnect' : 'Delete';
    final deleteIcon = remoteBoard
        ? Icons.link_off_rounded
        : Icons.delete_outline;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final phone = constraints.maxWidth < 560;
        final horizontalPadding = phone ? 8.0 : 16.0;
        final gap = phone ? 6.0 : 12.0;
        return Container(
          decoration: BoxDecoration(
            color: kIsWeb
                ? colors.surfaceElevated.withAlpha(180)
                : colors.surface.withAlpha(31),
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
                if (!compact && board.defaultFolder.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  ToolbarChip(
                    icon: Icons.folder_outlined,
                    label: _shortToolbarPath(board.defaultFolder),
                  ),
                ],
                SizedBox(width: gap),
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
                              border: Border.all(
                                color: context.appColors.border,
                              ),
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
                                    color: context.appColors.textMuted
                                        .withAlpha(120),
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
                if (compact) const Spacer() else const SizedBox(width: 16),
                if (phone)
                  PopupMenuButton<String>(
                    tooltip: 'Board actions',
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (value) {
                      switch (value) {
                        case 'search':
                          onSearch();
                        case 'new':
                          onCreateBoard();
                        case 'newFromTemplate':
                          onCreateBoardFromTemplate();
                        case 'remote':
                          onConnectRemote();
                        case 'share':
                          onShareBoard();
                        case 'download':
                          unawaited(launchExternalUrl(_downloadReleasesUrl));
                        case 'settings':
                          onBoardSettings();
                        case 'delete':
                          onDeleteBoard();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'search',
                        child: Text('Search boards and panels'),
                      ),
                      const PopupMenuItem(
                        value: 'new',
                        child: Text('Blank board'),
                      ),
                      const PopupMenuItem(
                        value: 'newFromTemplate',
                        child: Text('From template...'),
                      ),
                      const PopupMenuItem(
                        value: 'remote',
                        child: Text('Connect remote YoLoIT'),
                      ),
                      const PopupMenuItem(
                        value: 'share',
                        child: Text('Share board'),
                      ),
                      if (kIsWeb)
                        const PopupMenuItem(
                          value: 'download',
                          child: Text('Download YoLoIT'),
                        ),
                      const PopupMenuItem(
                        value: 'settings',
                        child: Text('Settings'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text(deleteLabel)),
                    ],
                  )
                else if (compact) ...[
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
                  if (kIsWeb) const _DownloadReleasesButton(compact: true),
                  IconButton(
                    tooltip: 'Board settings',
                    onPressed: onBoardSettings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  IconButton(
                    tooltip: deleteTooltip,
                    onPressed: onDeleteBoard,
                    icon: Icon(deleteIcon),
                  ),
                ] else ...[
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
                    icon: Icon(deleteIcon),
                    label: Text(deleteLabel),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
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
