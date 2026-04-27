import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/search/data/file_search_service.dart';
import 'package:yoloit/features/search/utils/fuzzy_matcher.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Shows the quick file search overlay.
/// If [onFileSelected] is provided, it is called with the selected file path
/// instead of the default ReviewCubit/FileEditorCubit open behavior (e.g. for
/// opening files as mindmap panels).
Future<void> showFileSearch(
  BuildContext context, {
  required VoidCallback onFileOpened,
  void Function(String filePath)? onFileSelected,
}) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => Material(
      type: MaterialType.transparency,
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<WorkspaceCubit>()),
          BlocProvider.value(value: context.read<ReviewCubit>()),
          BlocProvider.value(value: context.read<FileEditorCubit>()),
        ],
        child: FileSearchOverlay(
          onFileOpened: onFileOpened,
          onFileSelected: onFileSelected,
        ),
      ),
    ),
  );
}

class FileSearchOverlay extends StatefulWidget {
  const FileSearchOverlay({
    super.key,
    required this.onFileOpened,
    this.onFileSelected,
  });
  final VoidCallback onFileOpened;
  /// When provided, replaces the default ReviewCubit+FileEditorCubit open.
  final void Function(String filePath)? onFileSelected;

  @override
  State<FileSearchOverlay> createState() => _FileSearchOverlayState();
}

class _FileSearchOverlayState extends State<FileSearchOverlay> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  SearchMode _mode = SearchMode.files;
  bool _allWorkspaces = false;
  List<SearchResult> _results = [];
  bool _loading = false;
  int _selectedIndex = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
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
    _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
  }

  List<({String name, String path})> _getWorkspaces() {
    final wsState = context.read<WorkspaceCubit>().state;
    if (wsState is! WorkspaceLoaded) return [];

    if (_allWorkspaces) {
      return wsState.workspaces
          .map((w) => (name: w.name, path: w.path))
          .toList();
    }

    // Active workspace only
    final active = wsState.workspaces.where((w) => w.id == wsState.activeWorkspaceId).firstOrNull
        ?? wsState.workspaces.firstOrNull;
    if (active == null) return [];
    return [(name: active.name, path: active.path)];
  }

  Future<void> _runSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() { _results = []; _loading = false; _selectedIndex = 0; });
      return;
    }

    setState(() => _loading = true);
    final workspaces = _getWorkspaces();

    final results = _mode == SearchMode.files
        ? await FileSearchService.instance.searchFiles(query: query, workspaces: workspaces)
        : await FileSearchService.instance.searchContent(query: query, workspaces: workspaces);

    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
      _selectedIndex = 0;
    });
  }

  void _openSelected() {
    if (_results.isEmpty) return;
    final result = _results[_selectedIndex];
    Navigator.of(context).pop();
    if (widget.onFileSelected != null) {
      widget.onFileSelected!(result.filePath);
    } else {
      context.read<ReviewCubit>().selectFile(result.filePath);
      context.read<FileEditorCubit>().openFile(result.filePath);
    }
    widget.onFileOpened();
  }

  void _navigate(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, _results.length - 1);
    });
    // Scroll selected item into view immediately (no animation — avoids jitter)
    const itemHeight = 60.0;
    _scrollController.jumpTo(
      (_selectedIndex * itemHeight).clamp(0.0, _scrollController.position.maxScrollExtent),
    );
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
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) _navigate(1);
              if (event.logicalKey == LogicalKeyboardKey.arrowUp) _navigate(-1);
              if (event.logicalKey == LogicalKeyboardKey.enter) _openSelected();
              if (event.logicalKey == LogicalKeyboardKey.escape) Navigator.of(context).pop();
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
                  color: Colors.black.withAlpha(100),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildHeader(context),
                _buildToolbar(),
                const Divider(height: 1, color: Color(0xFF2A2A3A)),
                Expanded(child: _buildResults()),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Icon(
            _mode == SearchMode.files ? Icons.search : Icons.manage_search,
            size: 18,
            color: colors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: _mode == SearchMode.files
                      ? 'Search files by name…'
                      : 'Search in file contents…',
                  hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 15),
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
              onTap: () { _controller.clear(); setState(() => _results = []); },
              child: Icon(Icons.close, size: 16, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          _ModeChip(
            label: 'Files',
            icon: Icons.insert_drive_file_outlined,
            selected: _mode == SearchMode.files,
            onTap: () { setState(() => _mode = SearchMode.files); _runSearch(); },
          ),
          const SizedBox(width: 6),
          _ModeChip(
            label: 'Content',
            icon: Icons.text_snippet_outlined,
            selected: _mode == SearchMode.content,
            onTap: () { setState(() => _mode = SearchMode.content); _runSearch(); },
          ),
          const Spacer(),
          _ModeChip(
            label: 'All workspaces',
            icon: Icons.workspaces_outlined,
            selected: _allWorkspaces,
            onTap: () { setState(() => _allWorkspaces = !_allWorkspaces); _runSearch(); },
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty && _controller.text.isEmpty) {
      return Center(
        child: Text(
          'Type to search files…',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }

    if (_results.isEmpty && !_loading) {
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: _results.length,
      itemExtent: 60,
      itemBuilder: (context, index) {
        final result = _results[index];
        final isSelected = index == _selectedIndex;
        return _ResultTile(
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
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? colors.primary.withAlpha(30) : Colors.transparent,
          border: Border.all(
            color: selected ? colors.primary.withAlpha(120) : colors.border,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: selected ? colors.primary : AppColors.textMuted),
            SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? colors.primary : AppColors.textMuted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.result,
    required this.isSelected,
    required this.query,
    required this.onTap,
  });

  final SearchResult result;
  final bool isSelected;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final extension = result.fileName.contains('.')
        ? result.fileName.split('.').last.toLowerCase()
        : '';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 80),
        color: isSelected ? colors.primary.withAlpha(25) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _FileIcon(extension: extension),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HighlightText(
                    text: result.fileName,
                    query: query,
                    baseStyle: const TextStyle(
                      color: Colors.white,
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
                  Row(
                    children: [
                      if (result.lineNumber != null) ...[
                        Text(
                          ':${result.lineNumber}',
                          style: TextStyle(
                            color: colors.primary.withAlpha(180),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          result.lineContent != null
                              ? result.lineContent!
                              : result.relativePath,
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (result.lineContent == null && result.workspaceName.isNotEmpty)
                        Text(
                          result.workspaceName,
                          style: TextStyle(color: AppColors.textMuted.withAlpha(120), fontSize: 10),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.keyboard_return, size: 12, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.extension});
  final String extension;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _iconForExtension(extension);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 15, color: color),
    );
  }

  static (IconData, Color) _iconForExtension(String ext) {
    return switch (ext) {
      'dart' => (Icons.flutter_dash, const Color(0xFF54C5F8)),
      'py' => (Icons.code, const Color(0xFFFFD43B)),
      'js' || 'ts' || 'jsx' || 'tsx' => (Icons.javascript, const Color(0xFFF7DF1E)),
      'swift' => (Icons.apple, const Color(0xFFFF6B35)),
      'kt' || 'java' => (Icons.code, const Color(0xFFB07219)),
      'go' => (Icons.code, const Color(0xFF00ADD8)),
      'rs' => (Icons.code, const Color(0xFFDEA584)),
      'html' || 'htm' => (Icons.html, const Color(0xFFE44D26)),
      'css' || 'scss' || 'sass' => (Icons.style, const Color(0xFF264DE4)),
      'json' || 'yaml' || 'yml' || 'toml' => (Icons.data_object, const Color(0xFFCBCB41)),
      'md' || 'mdx' => (Icons.article, const Color(0xFF888888)),
      'sh' || 'bash' || 'zsh' => (Icons.terminal, const Color(0xFF4EAF47)),
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' || 'webp' => (Icons.image, const Color(0xFFAB47BC)),
      _ => (Icons.insert_drive_file_outlined, const Color(0xFF888888)),
    };
  }
}

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
    if (query.isEmpty) return Text(text, style: baseStyle, overflow: TextOverflow.ellipsis);

    final queries = FuzzyMatcher.candidates(query);
    final indices = FuzzyMatcher.bestMatchIndices(text, queries);
    if (indices.isEmpty) return Text(text, style: baseStyle, overflow: TextOverflow.ellipsis);

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
