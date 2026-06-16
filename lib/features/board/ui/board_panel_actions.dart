import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/ui/widgets/text_editing_utils.dart';
import 'package:yoloit/ui/components/buttons/markdown_tool_button.dart';

/// Panel-level UI actions extracted from [BoardView] to keep the main board
/// view file within size limits.
class BoardPanelActions {
  const BoardPanelActions._();

  /// Shows the dialog for adding a new markdown note.
  static Future<void> showAddNoteDialog(BuildContext context) =>
      _showMarkdownNoteDialog(context);

  /// Returns a callback that opens the appropriate editor for [panel],
  /// or null when the panel type has no editor.
  static VoidCallback? createEditCallback(
    BuildContext context,
    BoardPanelInstance panel,
  ) {
    if (panel.type == 'board.note.markdown') {
      return () => _showMarkdownNoteDialog(context, panel: panel);
    }
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    if (plugin?.hasEditor != true) return null;
    return () async {
      await plugin!.showEditor(context, panel, (newState) {
        context.read<BoardCubit>().updatePanel(
          panel.id,
          (BoardPanelInstance p) => p.copyWith(state: newState),
        );
      });
    };
  }

  /// Shows the color picker and updates the panel color.
  static Future<void> showPanelColorDialog(
    BuildContext context,
    BoardPanelInstance panel,
  ) async {
    final color = await _showInlineColorDialog(context, panel.color);
    if (!context.mounted) return;
    await context.read<BoardCubit>().updatePanelColor(panel.id, color: color);
  }

  static Future<Color?> _showInlineColorDialog(
    BuildContext context,
    Color? initialColor,
  ) {
    var selectedColor = initialColor ?? context.appColors.primary;
    return showAdaptiveYoloDialog<Color?>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Panel color'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: ColorPicker(
                  pickerColor: selectedColor,
                  onColorChanged: (color) {
                    selectedColor = color;
                  },
                  enableAlpha: false,
                  displayThumbColor: true,
                  portraitOnly: true,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text('Reset'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(selectedColor),
                child: const Text('Apply'),
              ),
            ],
          ),
    );
  }

  static Future<void> _showMarkdownNoteDialog(
    BuildContext context, {
    BoardPanelInstance? panel,
  }) async {
    final initialTitle = panel?.title ?? 'Note';
    final initialMarkdown = panel?.state['markdown'] as String? ?? '';
    Color? selectedColor = panel?.color;
    final titleController = TextEditingController(text: initialTitle);
    final markdownController = TextEditingController(text: initialMarkdown);
    final result = await showAdaptiveYoloDialog<
      ({String title, String markdown, Color? color})
    >(
      context: context,
      builder: (dialogContext) {
        var isPreview = false;
        return AlertDialog(
          title: Text(
            panel == null ? 'Add markdown note' : 'Edit markdown note',
          ),
          content: SizedBox(
            width: 760,
            child: StatefulBuilder(
              builder:
                  (context, setDialogState) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          MarkdownToolButton(
                            icon: Icons.title,
                            tooltip: 'Heading',
                            onTap: () {
                              prefixSelectedLines(markdownController, '# ');
                              setDialogState(() {});
                            },
                          ),
                          MarkdownToolButton(
                            icon: Icons.format_bold,
                            tooltip: 'Bold',
                            onTap: () {
                              wrapSelection(
                                markdownController,
                                before: '**',
                                after: '**',
                                placeholder: 'bold',
                              );
                              setDialogState(() {});
                            },
                          ),
                          MarkdownToolButton(
                            icon: Icons.format_italic,
                            tooltip: 'Italic',
                            onTap: () {
                              wrapSelection(
                                markdownController,
                                before: '*',
                                after: '*',
                                placeholder: 'italic',
                              );
                              setDialogState(() {});
                            },
                          ),
                          MarkdownToolButton(
                            icon: Icons.format_list_bulleted,
                            tooltip: 'Bullet list',
                            onTap: () {
                              prefixSelectedLines(markdownController, '- ');
                              setDialogState(() {});
                            },
                          ),
                          MarkdownToolButton(
                            icon: Icons.check_box_outlined,
                            tooltip: 'Checkbox',
                            onTap: () {
                              prefixSelectedLines(
                                markdownController,
                                '- [ ] ',
                              );
                              setDialogState(() {});
                            },
                          ),
                          MarkdownToolButton(
                            icon: Icons.code,
                            tooltip: 'Inline code',
                            onTap: () {
                              wrapSelection(
                                markdownController,
                                before: '`',
                                after: '`',
                                placeholder: 'code',
                              );
                              setDialogState(() {});
                            },
                          ),
                          MarkdownToolButton(
                            icon: Icons.format_quote,
                            tooltip: 'Quote',
                            onTap: () {
                              prefixSelectedLines(markdownController, '> ');
                              setDialogState(() {});
                            },
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed:
                                () => setDialogState(() {
                                  isPreview = !isPreview;
                                }),
                            icon: Icon(
                              isPreview ? Icons.edit : Icons.preview,
                              size: 16,
                            ),
                            label: Text(isPreview ? 'Edit' : 'Preview'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (isPreview)
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: context.appColors.border,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SingleChildScrollView(
                              child: Text(markdownController.text),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: TextField(
                            controller: markdownController,
                            decoration: const InputDecoration(
                              hintText: 'Write markdown here...',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: null,
                            expands: true,
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text('Color', style: TextStyle(color: context.appColors.textSecondary)),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () async {
                              final color = await _showInlineColorDialog(
                                context,
                                selectedColor,
                              );
                              if (color != null) {
                                setDialogState(() => selectedColor = color);
                              }
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: selectedColor ?? context.appColors.primary,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: context.appColors.border),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  () => Navigator.of(dialogContext).pop((
                    title: titleController.text.trim(),
                    markdown: markdownController.text,
                    color: selectedColor,
                  )),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (!context.mounted || result == null) return;
    final cubit = context.read<BoardCubit>();
    if (panel == null) {
      await cubit.addPanel(
        BoardPanelInstance(
          id: 'panel-${DateTime.now().millisecondsSinceEpoch}',
          type: MarkdownNotePlugin.kTypeId,
          title: result.title,
          bounds: const BoardPanelBounds(x: 0, y: 0, width: 320, height: 220),
          state: {
            'markdown': result.markdown,
            'color': result.color?.toARGB32(),
          },
          color: result.color,
        ),
      );
      return;
    }
    await cubit.updatePanel(
      panel.id,
      (BoardPanelInstance p) => p.copyWith(
        title: result.title,
        state: {...p.state, 'markdown': result.markdown},
        color: result.color,
      ),
    );
  }
}
