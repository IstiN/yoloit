import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/ui/components/chip/toolbar_chip.dart';

class BoardToolbar extends StatelessWidget {
  const BoardToolbar({
    super.key,
    required this.board,
    required this.onCreateBoard,
    required this.onConnectRemote,
    required this.onShareBoard,
    required this.onBoardSettings,
    required this.onDeleteBoard,
    required this.onOpenBoardOverview,
    required this.onSearch,
  });

  final BoardDocument board;
  final VoidCallback onCreateBoard;
  final VoidCallback onConnectRemote;
  final VoidCallback onShareBoard;
  final VoidCallback onBoardSettings;
  final VoidCallback onDeleteBoard;
  final VoidCallback onOpenBoardOverview;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final remoteBoard = isRemoteBoard(board);
    final deleteTooltip =
        remoteBoard ? 'Disconnect remote board' : 'Delete board';
    final deleteLabel = remoteBoard ? 'Disconnect' : 'Delete';
    final deleteIcon =
        remoteBoard ? Icons.link_off_rounded : Icons.delete_outline;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final phone = constraints.maxWidth < 560;
        final horizontalPadding = phone ? 8.0 : 16.0;
        final gap = phone ? 6.0 : 12.0;
        return Padding(
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
                                Platform.isMacOS ? '⌘O' : 'Ctrl+O',
                                style: TextStyle(
                                  color: context.appColors.textMuted.withAlpha(
                                    120,
                                  ),
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
                      case 'remote':
                        onConnectRemote();
                      case 'share':
                        onShareBoard();
                      case 'settings':
                        onBoardSettings();
                      case 'delete':
                        onDeleteBoard();
                    }
                  },
                  itemBuilder:
                      (context) => [
                        const PopupMenuItem(
                          value: 'search',
                          child: Text('Search boards and panels'),
                        ),
                        const PopupMenuItem(
                          value: 'new',
                          child: Text('New board'),
                        ),
                        const PopupMenuItem(
                          value: 'remote',
                          child: Text('Connect remote YoLoIT'),
                        ),
                        const PopupMenuItem(
                          value: 'share',
                          child: Text('Share board'),
                        ),
                        const PopupMenuItem(
                          value: 'settings',
                          child: Text('Settings'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(deleteLabel),
                        ),
                      ],
                )
              else if (compact) ...[
                IconButton(
                  tooltip: 'New board',
                  onPressed: onCreateBoard,
                  icon: const Icon(Icons.add),
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
                OutlinedButton.icon(
                  style: _toolbarButtonStyle(),
                  onPressed: onCreateBoard,
                  icon: const Icon(Icons.add),
                  label: const Text('New board'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: _toolbarButtonStyle(),
                  onPressed: onConnectRemote,
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('Remote'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: _toolbarButtonStyle(),
                  onPressed: onShareBoard,
                  icon: const Icon(Icons.ios_share_outlined),
                  label: const Text('Share'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: _toolbarButtonStyle(),
                  onPressed: onBoardSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Settings'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: _toolbarButtonStyle(),
                  onPressed: onDeleteBoard,
                  icon: Icon(deleteIcon),
                  label: Text(deleteLabel),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static ButtonStyle _toolbarButtonStyle() {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }

  static String _shortToolbarPath(String path) {
    final normalized = path.trim();
    if (normalized.length <= 28) return normalized;
    final parts = normalized.split(Platform.pathSeparator);
    if (parts.length >= 2) return '…${Platform.pathSeparator}${parts.last}';
    return '…${normalized.substring(normalized.length - 27)}';
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
