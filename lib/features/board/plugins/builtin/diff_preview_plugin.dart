import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

final _diffPreviewDefaultColors = AppColorScheme.fromAccent(Colors.deepPurple);

class DiffPreviewPlugin extends BoardPanelPlugin {
  const DiffPreviewPlugin();

  static const String kTypeId = 'board.diff.preview';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Diff Preview';

  @override
  IconData get icon => Icons.difference_outlined;

  @override
  Color get accentColor => _diffPreviewDefaultColors.accentBlue;

  @override
  Size get defaultSize => const Size(600, 500);

  @override
  Map<String, dynamic> get initialState => {
    'filePath': '',
    'rootPath': '',
    'title': '',
  };

  @override
  bool get showInCatalog => false;

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _DiffPreviewContent(panel: panel, renderContext: renderContext);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _DiffPreviewContent extends StatefulWidget {
  const _DiffPreviewContent({
    required this.panel,
    required this.renderContext,
  });

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_DiffPreviewContent> createState() => _DiffPreviewContentState();
}

class _DiffPreviewContentState extends State<_DiffPreviewContent> {
  List<_DiffLine>? _lines;
  bool _loading = true;
  String? _error;
  bool _sideBySide = false;

  String get _filePath => widget.panel.state['filePath'] as String? ?? '';
  String get _rootPath => widget.panel.state['rootPath'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _loadDiff();
  }

  @override
  void didUpdateWidget(covariant _DiffPreviewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel.state['filePath'] != widget.panel.state['filePath']) {
      _loadDiff();
    }
  }

  void _openFilePreview() {
    if (_filePath.isEmpty) return;
    final fullPath = _rootPath.isNotEmpty
        ? '$_rootPath/$_filePath'
        : _filePath;
    final fileName = _filePath.split('/').last;
    widget.renderContext.onCreateLinkedPanel?.call(
      'board.file.preview',
      {'path': fullPath, 'title': fileName},
      fileName,
    );
  }

  Future<void> _loadDiff() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final filePath = _filePath;
    final rootPath = _rootPath;
    if (filePath.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No file selected';
      });
      return;
    }

    try {
      final result = await Process.run(
        'git',
        ['diff', 'HEAD', '--', filePath],
        workingDirectory: rootPath.isNotEmpty ? rootPath : null,
      );

      String diffOutput = (result.stdout as String);

      // If no diff against HEAD, try unstaged
      if (diffOutput.trim().isEmpty) {
        final unstagedResult = await Process.run(
          'git',
          ['diff', '--', filePath],
          workingDirectory: rootPath.isNotEmpty ? rootPath : null,
        );
        diffOutput = (unstagedResult.stdout as String);
      }

      // If still empty, try showing untracked file as all-new
      if (diffOutput.trim().isEmpty) {
        final statusResult = await Process.run(
          'git',
          ['status', '--porcelain', '--', filePath],
          workingDirectory: rootPath.isNotEmpty ? rootPath : null,
        );
        final status = (statusResult.stdout as String).trim();
        if (status.startsWith('?')) {
          // Untracked file — show full content as additions
          final fullPath = rootPath.isNotEmpty
              ? '$rootPath/$filePath'
              : filePath;
          final file = File(fullPath);
          if (file.existsSync()) {
            final content = await file.readAsString();
            final lines = content.split('\n');
            if (!mounted) return;
            setState(() {
              _lines = lines
                  .asMap()
                  .entries
                  .map((e) => _DiffLine(
                        type: _DiffLineType.added,
                        content: e.value,
                        newLineNo: e.key + 1,
                      ))
                  .toList();
              _loading = false;
            });
            return;
          }
        }
        // No changes
        if (!mounted) return;
        setState(() {
          _lines = [];
          _loading = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _lines = _parseDiff(diffOutput);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to get diff: $e';
      });
    }
  }

  List<_DiffLine> _parseDiff(String diff) {
    final lines = diff.split('\n');
    final result = <_DiffLine>[];
    int oldLine = 0;
    int newLine = 0;

    for (final line in lines) {
      if (line.startsWith('@@')) {
        // Parse hunk header: @@ -oldStart,oldCount +newStart,newCount @@
        final match = RegExp(r'@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)').firstMatch(line);
        if (match != null) {
          oldLine = int.parse(match.group(1)!);
          newLine = int.parse(match.group(2)!);
        }
        result.add(_DiffLine(
          type: _DiffLineType.hunk,
          content: line,
        ));
      } else if (line.startsWith('---') || line.startsWith('+++') || line.startsWith('diff ') || line.startsWith('index ')) {
        // Skip diff header lines
        continue;
      } else if (line.startsWith('+')) {
        result.add(_DiffLine(
          type: _DiffLineType.added,
          content: line.substring(1),
          newLineNo: newLine,
        ));
        newLine++;
      } else if (line.startsWith('-')) {
        result.add(_DiffLine(
          type: _DiffLineType.removed,
          content: line.substring(1),
          oldLineNo: oldLine,
        ));
        oldLine++;
      } else if (line.startsWith(' ')) {
        result.add(_DiffLine(
          type: _DiffLineType.context,
          content: line.substring(1),
          oldLineNo: oldLine,
          newLineNo: newLine,
        ));
        oldLine++;
        newLine++;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(),
        const Divider(height: 1, thickness: 0.5),
        Expanded(child: _buildDiffContent()),
      ],
    );
  }

  Widget _buildToolbar() {
    final colors = context.appColors;
    final fileName = _filePath.split('/').last;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.difference_outlined, size: 14, color: colors.accentBlue),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              fileName.isEmpty ? 'Diff Preview' : fileName,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _ToggleButton(
            label: 'Unified',
            isActive: !_sideBySide,
            onTap: () => setState(() => _sideBySide = false),
          ),
          const SizedBox(width: 4),
          _ToggleButton(
            label: 'Split',
            isActive: _sideBySide,
            onTap: () => setState(() => _sideBySide = true),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.description_outlined, size: 14),
            onPressed: _openFilePreview,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: colors.textSecondary,
            tooltip: 'Open file preview',
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh, size: 14),
            onPressed: _loadDiff,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: colors.textSecondary,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildDiffContent() {
    final colors = context.appColors;
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
      );
    }
    final lines = _lines ?? [];
    if (lines.isEmpty) {
      return Center(
        child: Text(
          'No changes',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
      );
    }

    if (_sideBySide) {
      return _buildSideBySide(lines);
    }
    return _buildUnified(lines);
  }

  Widget _buildUnified(List<_DiffLine> lines) {
    final colors = context.appColors;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: lines.length,
      itemBuilder: (_, i) {
        final line = lines[i];
        final bgColor = switch (line.type) {
          _DiffLineType.added => colors.diffAddBg,
          _DiffLineType.removed => colors.diffRemoveBg,
          _DiffLineType.hunk => colors.diffContextBg,
          _DiffLineType.context => Colors.transparent,
        };
        final textColor = switch (line.type) {
          _DiffLineType.added => colors.diffAddText,
          _DiffLineType.removed => colors.diffRemoveText,
          _DiffLineType.hunk => colors.accentBlue,
          _DiffLineType.context => colors.terminalText,
        };
        final prefix = switch (line.type) {
          _DiffLineType.added => '+',
          _DiffLineType.removed => '-',
          _DiffLineType.hunk => '',
          _DiffLineType.context => ' ',
        };
        final lineNo = line.type == _DiffLineType.hunk
            ? ''
            : '${(line.oldLineNo ?? '').toString().padLeft(4)} ${(line.newLineNo ?? '').toString().padLeft(4)}';

        return Container(
          color: bgColor,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          height: 20,
          child: Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(lineNo, style: _lineNoStyle(colors)),
              ),
              SizedBox(
                width: 12,
                child: Text(
                  prefix,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
              _diffContentText(line.content, textColor),
            ],
          ),
        );
      },
    );
  }

  static TextStyle _lineNoStyle(AppColorScheme colors) {
    return TextStyle(
      fontSize: 10,
      fontFamily: 'monospace',
      color: colors.textMuted,
    );
  }

  static Widget _diffContentText(String content, Color textColor) {
    return Expanded(
      child: Text(
        content,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: textColor,
        ),
        overflow: TextOverflow.clip,
        softWrap: false,
      ),
    );
  }

  Widget _buildSideBySide(List<_DiffLine> lines) {
    final colors = context.appColors;
    // Build left (old) and right (new) columns
    final leftLines = <_DiffLine>[];
    final rightLines = <_DiffLine>[];

    for (final line in lines) {
      switch (line.type) {
        case _DiffLineType.context:
          leftLines.add(line);
          rightLines.add(line);
        case _DiffLineType.removed:
          leftLines.add(line);
          rightLines.add(const _DiffLine(type: _DiffLineType.context, content: ''));
        case _DiffLineType.added:
          leftLines.add(const _DiffLine(type: _DiffLineType.context, content: ''));
          rightLines.add(line);
        case _DiffLineType.hunk:
          leftLines.add(line);
          rightLines.add(line);
      }
    }

    final count = leftLines.length;
    final scrollController = ScrollController();

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: count,
      itemBuilder: (_, i) {
        final left = leftLines[i];
        final right = rightLines[i];

        if (left.type == _DiffLineType.hunk) {
          return Container(
            color: colors.diffContextBg,
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              left.content,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: colors.accentBlue,
              ),
            ),
          );
        }

        return SizedBox(
          height: 20,
          child: Row(
            children: [
              Expanded(child: _sideCell(left, isLeft: true)),
              VerticalDivider(width: 1, thickness: 0.5, color: colors.border),
              Expanded(child: _sideCell(right, isLeft: false)),
            ],
          ),
        );
      },
    );
  }

  Widget _sideCell(_DiffLine line, {required bool isLeft}) {
    final colors = context.appColors;
    final bgColor = switch (line.type) {
      _DiffLineType.removed => colors.diffRemoveBg,
      _DiffLineType.added => colors.diffAddBg,
      _ => Colors.transparent,
    };
    final textColor = switch (line.type) {
      _DiffLineType.removed => colors.diffRemoveText,
      _DiffLineType.added => colors.diffAddText,
      _ => colors.terminalText,
    };
    final lineNo = isLeft ? line.oldLineNo : line.newLineNo;

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              lineNo != null ? '$lineNo' : '',
              style: _lineNoStyle(colors),
            ),
          ),
          _diffContentText(line.content, textColor),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isActive ? colors.tabActiveBg : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? colors.accentBlue : colors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? colors.accentBlue : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

enum _DiffLineType { context, added, removed, hunk }

class _DiffLine {
  const _DiffLine({
    required this.type,
    required this.content,
    this.oldLineNo,
    this.newLineNo,
  });
  final _DiffLineType type;
  final String content;
  final int? oldLineNo;
  final int? newLineNo;
}
