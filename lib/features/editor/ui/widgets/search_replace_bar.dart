import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
// ignore: implementation_imports
import 'package:flutter_code_editor/src/search/search_navigation_state.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

class SearchReplaceBar extends StatelessWidget {
  const SearchReplaceBar({
    required this.controller,
    required this.replaceController,
    required this.replaceFocus,
    required this.showReplace,
    required this.onToggleReplace,
    required this.onReplace,
    required this.onReplaceAll,
  });

  final CodeController controller;
  final TextEditingController replaceController;
  final FocusNode replaceFocus;
  final bool showReplace;
  final VoidCallback onToggleReplace;
  final VoidCallback onReplace;
  final VoidCallback onReplaceAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final searchController = controller.searchController;
    final patternController =
        searchController.settingsController.patternController;
    return Container(
      key: const Key('editor-search-replace-bar'),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.search, size: 14, color: colors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: SearchField(
                  key: const Key('editor-find-input'),
                  controller: patternController,
                  focusNode: searchController.patternFocusNode,
                  hint: 'Find',
                ),
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<SearchNavigationState>(
                valueListenable: searchController.navigationController,
                builder: (context, value, _) {
                  final current = value.currentMatchIndex;
                  final count = value.totalMatchCount;
                  final label =
                      count == 0 || current == null
                          ? '0 / 0'
                          : '${current + 1} / $count';
                  return Caption(label);
                },
              ),
              const SizedBox(width: 4),
              MiniIconButton(
                icon: Icons.keyboard_arrow_up,
                tooltip: 'Previous',
                onTap:
                    controller.searchController.navigationController.movePrevious,
              ),
              MiniIconButton(
                icon: Icons.keyboard_arrow_down,
                tooltip: 'Next',
                onTap:
                    controller.searchController.navigationController.moveNext,
              ),
              MiniIconButton(
                icon: Icons.find_replace,
                tooltip: 'Replace',
                active: showReplace,
                onTap: onToggleReplace,
              ),
              MiniIconButton(
                icon: Icons.close,
                tooltip: 'Close',
                onTap:
                    () => searchController.hideSearch(
                      returnFocusToCodeField: true,
                    ),
              ),
            ],
          ),
          if (showReplace) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(
                  Icons.drive_file_rename_outline,
                  size: 14,
                  color: colors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SearchField(
                    key: const Key('editor-replace-input'),
                    controller: replaceController,
                    focusNode: replaceFocus,
                    hint: 'Replace',
                  ),
                ),
                const SizedBox(width: 6),
                MiniTextButton(
                  key: const Key('editor-replace-one'),
                  label: 'Replace',
                  onTap: onReplace,
                ),
                const SizedBox(width: 4),
                MiniTextButton(
                  key: const Key('editor-replace-all'),
                  label: 'All',
                  onTap: onReplaceAll,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.controller, required this.focusNode, required this.hint});

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      height: 26,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: TextStyle(color: colors.textPrimary, fontSize: 12),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
          isDense: true,
          filled: true,
          fillColor: colors.surfaceElevated,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.primary),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        ),
      ),
    );
  }
}

class MiniIconButton extends StatelessWidget {
  const MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: active ? colors.primary.withAlpha(50) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 15,
            color: active ? colors.primaryLight : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

class MiniTextButton extends StatelessWidget {
  const MiniTextButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 26),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: colors.primaryLight,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
