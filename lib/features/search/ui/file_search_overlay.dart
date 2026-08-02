import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/file_preview_plugin_base.dart';
import 'package:yoloit/features/board/ui/board_overview_preview.dart';
import 'package:yoloit/features/board/utils/panel_placement.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/search/ui/file_search_overlay_files.dart' as file_search;
import 'package:yoloit/features/search/utils/fuzzy_matcher.dart';
import 'package:yoloit/features/search/utils/quick_open_search.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

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
    builder:
        (_) => Material(
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

enum _QuickResultKind { board, panel, file }

class _QuickResult {
  const _QuickResult({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    this.panelId,
    this.boardId,
    this.boardName,
    this.filePath,
    this.preview,
  });

  final _QuickResultKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final String? panelId;
  final String? boardId;
  final String? boardName;
  final String? filePath;
  final String? preview;
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
  int _searchGeneration = 0;

  // Precomputed panels + file tree roots for searching.
  List<({BoardDocument board, BoardPanelInstance panel})> _panels = [];
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
    _panels =
        boardState.boards
            .expand(
              (board) => board.panels
                  .where((panel) => !panel.hidden)
                  .map((panel) => (board: board, panel: panel)),
            )
            .toList();
    _fileTreeRoots =
        _panels
            .where((entry) => entry.panel.type == 'board.filetree')
            .map((entry) => entry.panel.state['rootPath'] as String? ?? '')
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList();
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
    final generation = ++_searchGeneration;
    final rawQuery = _controller.text.trim();
    final query = rawQuery.toLowerCase();
    final queries = FuzzyMatcher.candidates(query);
    final appColors = context.appColors;
    final wsState = context.read<WorkspaceCubit>().state;
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

    // 0. If the query looks like an existing file path, surface it first.
    await _collectPathResult(results, rawQuery, appColors);

    final boardState = context.read<BoardCubit>().state;

    // 1. Search boards by name (quick board switch).
    _collectBoardResults(results, boardState.boards, rawQuery, appColors);

    // 2. Search panels across all boards by title and shallow state content.
    _collectPanelResults(results, queries, appColors);

    // 3. Search files inside file-tree directories (no-op on web).
    if (!await _collectFileTreeResults(results, queries, appColors, generation)) {
      return;
    }

    // 4. Also search workspace files via existing service (no-op on web).
    if (!await _collectWorkspaceResults(results, wsState, generation, appColors)) {
      return;
    }

    if (!mounted || generation != _searchGeneration) return;
    results.sort(
      (a, b) => _kindRank(a.kind).compareTo(_kindRank(b.kind)),
    );
    setState(() {
      _results = results;
      _loading = false;
      _selectedIndex = 0;
    });
  }

  // 0. If the query looks like an existing file path, surface it first.
  Future<void> _collectPathResult(
    List<_QuickResult> results,
    String rawQuery,
    AppColorScheme appColors,
  ) async {
    if (PlatformCapabilities.current.platform == RuntimePlatform.web) return;
    final pathInfo = await file_search.tryResolveExistingPath(rawQuery);
    if (pathInfo != null &&
        !results.any((r) => r.filePath == pathInfo.filePath)) {
      final ext =
          pathInfo.name.contains('.')
              ? pathInfo.name.split('.').last.toLowerCase()
              : '';
      final (icon, color) = _iconForExtension(ext, appColors);
      results.insert(
        0,
        _QuickResult(
          kind: _QuickResultKind.file,
          title: pathInfo.name,
          subtitle: pathInfo.filePath,
          icon: icon,
          iconColor: color,
          filePath: pathInfo.filePath,
        ),
      );
    }
  }

  // 1. Search boards by name (quick board switch).
  void _collectBoardResults(
    List<_QuickResult> results,
    List<BoardDocument> boards,
    String rawQuery,
    AppColorScheme appColors,
  ) {
    for (final board in matchBoardsForQuickOpen(boards, rawQuery)) {
      final panelCount = board.panels.where((panel) => !panel.hidden).length;
      results.add(
        _QuickResult(
          kind: _QuickResultKind.board,
          title: board.name,
          subtitle:
              panelCount == 0
                  ? 'Board'
                  : '$panelCount panel${panelCount == 1 ? '' : 's'}',
          icon: Icons.space_dashboard_outlined,
          iconColor: appColors.primary,
          boardId: board.id,
          boardName: board.name,
        ),
      );
    }
  }

  // 2. Search panels across all boards by title and shallow state content.
  void _collectPanelResults(
    List<_QuickResult> results,
    List<String> queries,
    AppColorScheme appColors,
  ) {
    for (final entry in _panels) {
      final board = entry.board;
      final panel = entry.panel;
      final searchable = <String>[
        panel.title,
        panel.id,
        ..._collectSearchStrings(panel.state),
      ];
      String? preview;
      var matched = false;
      for (final text in searchable) {
        if (FuzzyMatcher.bestScore(text, queries) != null) {
          matched = true;
          preview = _snippet(text, queries);
          break;
        }
      }
      if (matched) {
        results.add(
          _QuickResult(
            kind: _QuickResultKind.panel,
            title: panel.title,
            subtitle: '${board.name} · ${_panelTypeLabel(panel.type)}',
            icon: _panelTypeIcon(panel.type),
            iconColor: _panelTypeColor(panel.type, appColors),
            panelId: panel.id,
            boardId: board.id,
            boardName: board.name,
            preview: preview,
          ),
        );
      }
    }
  }

  // 3. Search files inside file-tree directories (no-op on web).
  // Returns false when a newer search superseded this one.
  Future<bool> _collectFileTreeResults(
    List<_QuickResult> results,
    List<String> queries,
    AppColorScheme appColors,
    int generation,
  ) async {
    if (PlatformCapabilities.current.platform == RuntimePlatform.web) {
      return true;
    }
    final fileInfos = await file_search.collectMatchingFiles(
      _fileTreeRoots,
      queries,
      maxResults: 100,
    );
    for (final info in fileInfos) {
      if (generation != _searchGeneration) return false;
      if (results.length >= 150) break;
      final ext =
          info.name.contains('.') ? info.name.split('.').last.toLowerCase() : '';
      final (icon, color) = _iconForExtension(ext, appColors);
      if (!results.any((r) => r.filePath == info.filePath)) {
        results.add(
          _QuickResult(
            kind: _QuickResultKind.file,
            title: info.name,
            subtitle: info.relativePath,
            icon: icon,
            iconColor: color,
            filePath: info.filePath,
          ),
        );
      }
    }
    return true;
  }

  // 4. Also search workspace files via existing service (no-op on web).
  // Returns false when a newer search superseded this one.
  Future<bool> _collectWorkspaceResults(
    List<_QuickResult> results,
    WorkspaceState wsState,
    int generation,
    AppColorScheme appColors,
  ) async {
    if (wsState is! WorkspaceLoaded ||
        PlatformCapabilities.current.platform == RuntimePlatform.web) {
      return true;
    }
    if (generation != _searchGeneration) return false;
    final active =
        wsState.workspaces
            .where((w) => w.id == wsState.activeWorkspaceId)
            .firstOrNull ??
        wsState.workspaces.firstOrNull;
    if (active != null) {
      // Only add workspace files that aren't already covered by file tree roots
      final wsResults = await file_search.searchWorkspaceFiles(
        _controller.text.trim(),
        (name: active.name, path: active.path),
        maxResults: 50,
      );
      for (final r in wsResults) {
        // Skip if already in results from file tree
        if (results.any((q) => q.filePath == r.filePath)) continue;
        if (results.length >= 150) break;
        final ext =
            r.name.contains('.') ? r.name.split('.').last.toLowerCase() : '';
        final (icon, color) = _iconForExtension(ext, appColors);
        results.add(
          _QuickResult(
            kind: _QuickResultKind.file,
            title: r.name,
            subtitle: r.relativePath,
            icon: icon,
            iconColor: color,
            filePath: r.filePath,
          ),
        );
      }
    }
    return true;
  }

  List<String> _collectSearchStrings(dynamic value, {int depth = 0}) {
    if (value == null || depth > 4) return const [];
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? const [] : <String>[trimmed];
    }
    if (value is num || value is bool) return <String>['$value'];
    if (value is List) {
      return [
        for (final item in value)
          ..._collectSearchStrings(item, depth: depth + 1),
      ];
    }
    if (value is Map) {
      return [
        for (final entry in value.entries)
          if (entry.key != 'id' && entry.key != 'timestamp')
            ..._collectSearchStrings(entry.value, depth: depth + 1),
      ];
    }
    return const [];
  }

  String _snippet(String text, List<String> queries) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 96) return compact;
    final lower = compact.toLowerCase();
    final index =
        queries
            .map((query) => lower.indexOf(query.toLowerCase()))
            .where((index) => index >= 0)
            .firstOrNull ??
        -1;
    final start = index < 0 ? 0 : (index - 24).clamp(0, compact.length);
    final end = (start + 96).clamp(0, compact.length);
    return '${start > 0 ? '…' : ''}${compact.substring(start, end)}${end < compact.length ? '…' : ''}';
  }

  Future<void> _openSelected() async {
    final rawQuery = _controller.text.trim();
    if (_results.isEmpty) {
      // Fallback: if the typed text is an existing file path, open it directly.
      if (PlatformCapabilities.current.platform != RuntimePlatform.web) {
        final pathInfo = await file_search.tryResolveExistingPath(rawQuery);
        if (pathInfo != null) {
          Navigator.of(context).pop();
          await _openFilePath(pathInfo.filePath);
          return;
        }
      }
      return;
    }
    final result = _results[_selectedIndex];
    Navigator.of(context).pop();

    if (result.kind == _QuickResultKind.board && result.boardId != null) {
      await context.read<BoardCubit>().setActiveBoard(result.boardId!);
    } else if (result.kind == _QuickResultKind.panel && result.panelId != null) {
      final boardCubit = context.read<BoardCubit>();
      if (result.boardId != null) {
        await boardCubit.setActiveBoard(result.boardId!);
      }
      await boardCubit.focusPanel(
        result.panelId!,
        boardId: result.boardId,
        zoomOnFocus: true,
      );
    } else if (result.kind == _QuickResultKind.file &&
        result.filePath != null) {
      await _openFilePath(result.filePath!);
    }
  }

  Future<void> _openFilePath(String filePath) async {
    if (widget.onFileSelected != null) {
      widget.onFileSelected!(filePath);
      widget.onFileOpened();
      return;
    }

    final boardCubit = context.read<BoardCubit>();
    final board = boardCubit.state.activeBoard;
    if (board == null) {
      context.read<ReviewCubit>().selectFile(filePath);
      await context.read<FileEditorCubit>().openFile(filePath);
      widget.onFileOpened();
      return;
    }

    // 1. Deduplicate: focus existing panel for this file.
    final existing = PanelPlacementHelper.findExistingFilePreview(board, filePath);
    if (existing != null) {
      await boardCubit.focusPanel(existing.id, zoomOnFocus: true);
      widget.onFileOpened();
      return;
    }

    // 2. Smart sizing based on file type.
    final desiredSize = PanelPlacementHelper.desiredSizeForFile(filePath);

    // 3. Find a non-overlapping slot near the focused panel or viewport centre
    //    (so the user doesn't get teleported far away).
    final viewport = board.viewport;
    final screenSize = MediaQuery.sizeOf(context);
    final viewportCenter = Offset(
      (-viewport.translation.dx + screenSize.width / 2) /
          math.max(viewport.scale, 0.001),
      (-viewport.translation.dy + screenSize.height / 2) /
          math.max(viewport.scale, 0.001),
    );
    final placement = PanelPlacementHelper.findPlacement(
      board,
      desiredSize: desiredSize,
      anchorPanelId: board.viewport.focusedPanelId,
      viewportCenter: viewportCenter,
    );

    final fileName = p.basename(filePath);
    final panel = BoardPanelInstance(
      id: 'panel-${DateTime.now().microsecondsSinceEpoch}',
      type: FilePreviewPluginBase.kTypeId,
      title: fileName,
      bounds: placement.bounds,
      state: {'path': filePath, 'title': fileName},
      zIndex: placement.zIndex,
    );

    await boardCubit.addPanel(panel);
    await boardCubit.focusPanel(panel.id, zoomOnFocus: true);
    widget.onFileOpened();
  }

  void _navigate(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, _results.length - 1);
    });
    const itemHeight = 68.0;
    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      final itemTop = _selectedIndex * itemHeight;
      final itemBottom = itemTop + itemHeight;
      final viewportTop = position.pixels;
      final viewportBottom = viewportTop + position.viewportDimension;
      double? target;
      if (itemTop < viewportTop) {
        target = itemTop;
      } else if (itemBottom > viewportBottom) {
        target = itemBottom - position.viewportDimension;
      }
      if (target != null) {
        _scrollController.jumpTo(target.clamp(0.0, position.maxScrollExtent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 72),
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _navigate(1);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                _navigate(-1);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                unawaited(_openSelected());
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.of(context).pop();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
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
                  hintText: 'Search boards, panels, files…',
                  hintStyle: TextStyle(color: colors.textMuted, fontSize: 15),
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
              child: Icon(Icons.close, size: 16, color: colors.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final colors = context.appColors;
    if (_results.isEmpty && _controller.text.isEmpty) {
      final isWeb = PlatformCapabilities.current.platform == RuntimePlatform.web;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 36, color: colors.textMuted.withAlpha(80)),
            const SizedBox(height: 8),
            Caption(
              isWeb
                  ? 'File search is available in YoLoIT for macOS'
                  : 'Type to search boards, panels & files…',
              fontSize: 13,
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
      return const Center(
        child: Caption('No results found', fontSize: 13),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: _results.length,
      itemExtent: 68,
      itemBuilder: (context, index) {
        final result = _results[index];
        final isSelected = index == _selectedIndex;
        return _QuickResultTile(
          result: result,
          isSelected: isSelected,
          query: _controller.text.trim(),
          onTap: () {
            setState(() => _selectedIndex = index);
            unawaited(_openSelected());
          },
        );
      },
    );
  }

  static int _kindRank(_QuickResultKind kind) {
    return switch (kind) {
      _QuickResultKind.board => 0,
      _QuickResultKind.panel => 1,
      _QuickResultKind.file => 2,
    };
  }

  Widget _buildFooter() {
    final colors = context.appColors;
    final boardCount =
        _results.where((r) => r.kind == _QuickResultKind.board).length;
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
          if (boardCount > 0)
            Caption('$boardCount board${boardCount > 1 ? 's' : ''}'),
          if (boardCount > 0 && panelCount > 0)
            const Caption(' · '),
          if (panelCount > 0)
            Caption('$panelCount panel${panelCount > 1 ? 's' : ''}',),
          if ((boardCount > 0 || panelCount > 0) && fileCount > 0)
            const Caption(' · '),
          if (fileCount > 0)
            Caption('$fileCount file${fileCount > 1 ? 's' : ''}',),
          const Spacer(),
          Text(
            '${_results.length} result${_results.length > 1 ? 's' : ''}',
            style: TextStyle(
              color: colors.textMuted.withAlpha(120),
              fontSize: 11,
            ),
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
      'json' ||
      'yaml' ||
      'yml' ||
      'toml' => (Icons.data_object, colors.accentOrange),
      'md' || 'mdx' => (Icons.article, colors.textMuted),
      'sh' || 'bash' || 'zsh' => (Icons.terminal, colors.accentGreen),
      'png' ||
      'jpg' ||
      'jpeg' ||
      'gif' ||
      'svg' ||
      'webp' => (Icons.image, colors.primaryLight),
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
      child: Container(
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
                  Caption(result.subtitle, overflow: TextOverflow.ellipsis),
                  if (result.preview != null &&
                      result.preview != result.title) ...[
                    const SizedBox(height: 1),
                    Text(
                      result.preview!,
                      style: TextStyle(
                        color: colors.textMuted.withAlpha(150),
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (result.kind == _QuickResultKind.board)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: result.iconColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'BOARD',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: result.iconColor,
                  ),
                ),
              )
            else if (result.kind == _QuickResultKind.panel)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            const SizedBox(width: 8),
            SizedBox(
              width: 12,
              child:
                  isSelected
                      ? Icon(
                        Icons.keyboard_return,
                        size: 12,
                        color: colors.textMuted,
                      )
                      : null,
            ),
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
      spans.add(
        TextSpan(
          text: text[i],
          style: indexSet.contains(i) ? highlightStyle : baseStyle,
        ),
      );
    }

    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }
}
