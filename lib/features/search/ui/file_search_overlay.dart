import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/file_preview_plugin.dart';
import 'package:yoloit/features/board/ui/board_overview_preview.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/search/data/file_search_service.dart';
import 'package:yoloit/features/search/utils/fuzzy_matcher.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';

/// Shows the quick-open overlay.
/// Searches open board panels, files inside file-tree panel directories,
/// and workspace files. Arrow keys + Enter to navigate and select.
Future<void> showFileSearch(
  BuildContext context, {
  required VoidCallback onFileOpened,
  void Function(String filePath)? onFileSelected,
}) async {
  // Capture bloc references before the builder closure
  final boardCubit = context.read<BoardCubit>();
  final workspaceCubit = context.read<WorkspaceCubit>();
  final reviewCubit = context.read<ReviewCubit>();
  final editorCubit = context.read<FileEditorCubit>();

  final colors = context.appColors;
  await showDialog<void>(
    context: context,
    barrierColor: colors.textPrimary.withAlpha(84),
    builder: (_) => Material(
      type: MaterialType.transparency,
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: boardCubit),
          BlocProvider.value(value: workspaceCubit),
          BlocProvider.value(value: reviewCubit),
          BlocProvider.value(value: editorCubit),
        ],
        child: FileSearchOverlay(
          onFileOpened: onFileOpened,
          onFileSelected: onFileSelected,
        ),
      ),
    ),
  );
}

// ─── Quick-open result types ─────────────────────────────────────────────────

enum _QuickResultKind { panel, file }

class _QuickResult {
  const _QuickResult({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    this.panelId,
    this.filePath,
  });

  final _QuickResultKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final String? panelId;
  final String? filePath;
}

// ─── Overlay widget ──────────────────────────────────────────────────────────

class FileSearchOverlay extends StatefulWidget {
  const FileSearchOverlay({
    super.key,
    required this.onFileOpened,
    this.onFileSelected,
  });
  final VoidCallback onFileOpened;
  final void Function(String filePath)? onFileSelected;

  @override
  State<FileSearchOverlay> createState() => _FileSearchOverlayState();
}

class _FileSearchOverlayState extends State<FileSearchOverlay> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  List<_QuickResult> _results = [];
  bool _loading = false;
  int _selectedIndex = 0;
  Timer? _debounce;

  // Precomputed panels + file tree roots for searching
  List<BoardPanelInstance> _panels = [];
  List<String> _fileTreeRoots = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    _loadBoardData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _loadBoardData() {
    final boardState = context.read<BoardCubit>().state;
    final board = boardState.activeBoard;
    if (board != null) {
      _panels = board.panels.where((p) => !p.hidden).toList();
      _fileTreeRoots = _panels
          .where((p) => p.type == 'board.filetree')
          .map((p) => p.state['rootPath'] as String? ?? '')
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _runSearch);
  }

  Future<void> _runSearch() async {
    final query = _controller.text.trim().toLowerCase();
    final appColors = context.appColors;
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
        _selectedIndex = 0;
      });
      return;
    }

    setState(() => _loading = true);

    final results = <_QuickResult>[];

    // 1. Search open panels by title
    for (final panel in _panels) {
      if (_fuzzyMatch(panel.title, query)) {
        results.add(_QuickResult(
          kind: _QuickResultKind.panel,
          title: panel.title,
          subtitle: _panelTypeLabel(panel.type),
          icon: _panelTypeIcon(panel.type),
          iconColor: _panelTypeColor(panel.type, appColors),
          panelId: panel.id,
        ));
      }
    }

    // 2. Search files inside file-tree directories
    for (final root in _fileTreeRoots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      _collectMatchingFiles(dir, root, query, results, maxResults: 100);
    }

    // 3. Also search workspace files via existing service
    final wsState = context.read<WorkspaceCubit>().state;
    if (wsState is WorkspaceLoaded) {
      final active = wsState.workspaces
          .where((w) => w.id == wsState.activeWorkspaceId)
          .firstOrNull ?? wsState.workspaces.firstOrNull;
      if (active != null) {
        // Only add workspace files that aren't already covered by file tree roots
        final wsResults = await FileSearchService.instance.searchFiles(
          query: _controller.text.trim(),
          workspaces: [(name: active.name, path: active.path)],
        );
        for (final r in wsResults) {
          // Skip if already in results from file tree
          if (results.any((q) => q.filePath == r.filePath)) continue;
          if (results.length >= 150) break;
          final ext = r.fileName.contains('.')
              ? r.fileName.split('.').last.toLowerCase()
              : '';
          final (icon, color) = _iconForExtension(ext, appColors);
          results.add(_QuickResult(
            kind: _QuickResultKind.file,
            title: r.fileName,
            subtitle: r.relativePath,
            icon: icon,
            iconColor: color,
            filePath: r.filePath,
          ));
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
      _selectedIndex = 0;
    });
  }

  void _collectMatchingFiles(
    Directory dir,
    String root,
    String query,
    List<_QuickResult> results, {
    int maxResults = 100,
  }) {
    if (results.length >= maxResults) return;
    try {
      for (final entity in dir.listSync()) {
        if (results.length >= maxResults) return;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (entity is Directory) {
          _collectMatchingFiles(entity, root, query, results,
              maxResults: maxResults);
        } else if (entity is File && _fuzzyMatch(name, query)) {
          final relPath = p.relative(entity.path, from: root);
          final ext = name.contains('.')
              ? name.split('.').last.toLowerCase()
              : '';
          final (icon, color) = _iconForExtension(ext, context.appColors);
          // Avoid duplicates
          if (!results.any((r) => r.filePath == entity.path)) {
            results.add(_QuickResult(
              kind: _QuickResultKind.file,
              title: name,
              subtitle: relPath,
              icon: icon,
              iconColor: color,
              filePath: entity.path,
            ));
          }
        }
      }
    } on FileSystemException {
      // skip inaccessible
    }
  }

  bool _fuzzyMatch(String text, String query) {
    final lower = text.toLowerCase();
    if (lower.contains(query)) return true;
    // Simple subsequence match
    int qi = 0;
    for (int i = 0; i < lower.length && qi < query.length; i++) {
      if (lower[i] == query[qi]) qi++;
    }
    return qi == query.length;
  }

  void _openSelected() {
    if (_results.isEmpty) return;
    final result = _results[_selectedIndex];
    Navigator.of(context).pop();

    if (result.kind == _QuickResultKind.panel && result.panelId != null) {
      context.read<BoardCubit>().focusPanel(result.panelId!, zoomOnFocus: true);
    } else if (result.kind == _QuickResultKind.file && result.filePath != null) {
      if (widget.onFileSelected != null) {
        widget.onFileSelected!(result.filePath!);
      } else {
        // Try to open as board file preview panel
        final boardCubit = context.read<BoardCubit>();
        final board = boardCubit.state.activeBoard;
        if (board != null) {
          final fileName = p.basename(result.filePath!);
          final bounds = BoardPanelBounds(
            x: 200,
            y: 200,
            width: 500,
            height: 400,
          );
          final panel = BoardPanelInstance(
            id: 'panel-${DateTime.now().microsecondsSinceEpoch}',
            type: FilePreviewPlugin.kTypeId,
            title: fileName,
            bounds: bounds,
            state: {'path': result.filePath!, 'title': fileName},
            zIndex: board.panels.fold<int>(
                  0, (v, p) => p.zIndex > v ? p.zIndex : v) +
                1,
          );
          boardCubit.addPanel(panel);
          boardCubit.focusPanel(panel.id);
        } else {
          context.read<ReviewCubit>().selectFile(result.filePath!);
          context.read<FileEditorCubit>().openFile(result.filePath!);
        }
      }
      widget.onFileOpened();
    }
  }

  void _navigate(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, _results.length - 1);
    });
    const itemHeight = 52.0;
    if (_scrollController.hasClients) {
      final target = (_selectedIndex * itemHeight)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 72),
        child: KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: (event) {
            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _navigate(1);
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                _navigate(-1);
              } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                _openSelected();
              } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.of(context).pop();
              }
            }
          },
          child: Container(
            width: 600,
            height: 480,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.border),
              boxShadow: [
                BoxShadow(
                  color: colors.textPrimary.withAlpha(100),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildHeader(context),
                Divider(height: 1, color: colors.divider),
                Expanded(child: _buildResults()),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: TextStyle(color: colors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search panels, files…',
                  hintStyle:
                      TextStyle(color: colors.textMuted, fontSize: 15),
                  border: InputBorder.none,
                  isDense: true,
                ),
                cursorColor: colors.primary,
              ),
            ),
          ),
          if (_loading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            ),
          if (!_loading && _controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _controller.clear();
                setState(() => _results = []);
              },
              child:
                  Icon(Icons.close, size: 16, color: colors.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final colors = context.appColors;
    if (_results.isEmpty && _controller.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 36, color: colors.textMuted.withAlpha(80)),
            const SizedBox(height: 8),
            Text(
              'Type to search panels & files…',
              style: TextStyle(color: colors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '↑↓ navigate  ↵ open  esc close',
              style: TextStyle(
                color: colors.textMuted.withAlpha(100),
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty && !_loading) {
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(color: colors.textMuted, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: _results.length,
      itemExtent: 52,
      itemBuilder: (context, index) {
        final result = _results[index];
        final isSelected = index == _selectedIndex;
        return _QuickResultTile(
          result: result,
          isSelected: isSelected,
          query: _controller.text.trim(),
          onTap: () {
            setState(() => _selectedIndex = index);
            _openSelected();
          },
        );
      },
    );
  }

  Widget _buildFooter() {
    final colors = context.appColors;
    final panelCount =
        _results.where((r) => r.kind == _QuickResultKind.panel).length;
    final fileCount =
        _results.where((r) => r.kind == _QuickResultKind.file).length;
    if (_results.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          if (panelCount > 0)
            Text(
              '$panelCount panel${panelCount > 1 ? 's' : ''}',
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
          if (panelCount > 0 && fileCount > 0)
            Text(' · ',
                style: TextStyle(color: colors.textMuted, fontSize: 11)),
          if (fileCount > 0)
            Text(
              '$fileCount file${fileCount > 1 ? 's' : ''}',
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
          const Spacer(),
          Text(
            '${_results.length} result${_results.length > 1 ? 's' : ''}',
            style: TextStyle(
                color: colors.textMuted.withAlpha(120), fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ── Icon helpers ──────────────────────────────────────────────────────────

  static IconData _panelTypeIcon(String type) {
    return switch (type) {
      'board.chat' => Icons.chat_outlined,
      'board.terminal' => Icons.terminal,
      'board.filetree' => Icons.account_tree_outlined,
      'board.file.preview' => Icons.description_outlined,
      'board.diff.preview' => Icons.difference_outlined,
      'board.note.markdown' => Icons.article_outlined,
      'board.code.snippet' => Icons.code,
      'board.run.configs' => Icons.play_circle_outline,
      'board.webpage' => Icons.language,
      'board.checklist' => Icons.checklist,
      'board.kanban' => Icons.view_kanban_outlined,
      'board.timer' => Icons.timer_outlined,
      'board.custom.widget' => Icons.widgets_outlined,
      'board.playlist' => Icons.queue_music,
      'board.yolo.assistant' => Icons.assistant_outlined,
      _ => Icons.dashboard_outlined,
    };
  }

  static Color _panelTypeColor(String type, AppColorScheme colors) {
    return panelTypeColor(type, colors);
  }

  static String _panelTypeLabel(String type) {
    return switch (type) {
      'board.chat' => 'Chat Panel',
      'board.terminal' => 'Terminal',
      'board.filetree' => 'File Tree',
      'board.file.preview' => 'File Preview',
      'board.diff.preview' => 'Diff Preview',
      'board.note.markdown' => 'Markdown Note',
      'board.code.snippet' => 'Code Snippet',
      'board.run.configs' => 'Run Configs',
      'board.webpage' => 'Web Page',
      'board.checklist' => 'Checklist',
      'board.kanban' => 'Kanban Board',
      'board.timer' => 'Timer',
      'board.custom.widget' => 'Custom Widget',
      'board.playlist' => 'Playlist',
      'board.yolo.assistant' => 'Yolo Assistant',
      _ => type,
    };
  }

  static (IconData, Color) _iconForExtension(
    String ext,
    AppColorScheme colors,
  ) {
    return switch (ext) {
      'dart' => (Icons.flutter_dash, colors.accentBlue),
      'py' => (Icons.code, colors.accentOrange),
      'js' || 'ts' || 'jsx' || 'tsx' => (Icons.javascript, colors.primaryLight),
      'swift' => (Icons.apple, colors.accentRed),
      'kt' || 'java' => (Icons.code, colors.accentOrange),
      'go' => (Icons.code, colors.accentBlue),
      'rs' => (Icons.code, colors.accentOrange),
      'html' || 'htm' => (Icons.html, colors.accentRed),
      'css' || 'scss' || 'sass' => (Icons.style, colors.accentBlue),
      'json' || 'yaml' || 'yml' || 'toml' => (Icons.data_object, colors.accentOrange),
      'md' || 'mdx' => (Icons.article, colors.textMuted),
      'sh' || 'bash' || 'zsh' => (Icons.terminal, colors.accentGreen),
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' || 'webp' => (Icons.image, colors.primaryLight),
      _ => (Icons.insert_drive_file_outlined, colors.textMuted),
    };
  }
}

// ─── Result tile ─────────────────────────────────────────────────────────────

class _QuickResultTile extends StatelessWidget {
  const _QuickResultTile({
    required this.result,
    required this.isSelected,
    required this.query,
    required this.onTap,
  });

  final _QuickResult result;
  final bool isSelected;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        color: isSelected ? colors.primary.withAlpha(25) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: result.iconColor.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(result.icon, size: 15, color: result.iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HighlightText(
                    text: result.title,
                    query: query,
                    baseStyle: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                    highlightStyle: TextStyle(
                      color: colors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    result.subtitle,
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (result.kind == _QuickResultKind.panel)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: result.iconColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'PANEL',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: result.iconColor,
                  ),
                ),
              ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Icon(Icons.keyboard_return, size: 12, color: colors.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Highlight text ──────────────────────────────────────────────────────────

class _HighlightText extends StatelessWidget {
  const _HighlightText({
    required this.text,
    required this.query,
    required this.baseStyle,
    required this.highlightStyle,
  });

  final String text;
  final String query;
  final TextStyle baseStyle;
  final TextStyle highlightStyle;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: baseStyle, overflow: TextOverflow.ellipsis);
    }

    final queries = FuzzyMatcher.candidates(query);
    final indices = FuzzyMatcher.bestMatchIndices(text, queries);
    if (indices.isEmpty) {
      return Text(text, style: baseStyle, overflow: TextOverflow.ellipsis);
    }

    final indexSet = indices.toSet();
    final spans = <TextSpan>[];
    for (int i = 0; i < text.length; i++) {
      spans.add(TextSpan(
        text: text[i],
        style: indexSet.contains(i) ? highlightStyle : baseStyle,
      ));
    }

    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }
}
