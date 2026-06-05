// ignore_for_file: avoid_print
import 'dart:io';
import 'package:test/test.dart';

/// Ratchet test: prevents NEW hardcoded colors from being added to UI code.
///
/// We track a baseline count of `Color(0x...)` occurrences per file.
/// If a file's count goes UP (or a new file appears with hardcoded colors),
/// the test fails.  Over time, migrate files to use `context.appColors` and
/// lower the baseline number until it reaches 0.
///
/// Files inside `lib/core/theme/` are exempt (theme definitions themselves).
void main() {
  // ── Baseline: file → max allowed Color(0x...) count ──────────────────
  // Generated from current codebase.  When you migrate a file to use
  // theme colors, lower its count here.  Remove the entry once it hits 0.
  const baseline = <String, int>{
    'lib/features/board/assistant/yolo_voice_overlay.dart': 87,
    'lib/features/settings/ui/settings_page.dart': 3,
    'lib/features/settings/ui/dialogs/color_picker_dialog.dart': 40,
    'lib/features/settings/ui/debug_ui/sections/plectrum_debug.dart': 12,
    'lib/features/settings/ui/debug_ui/sections/voice_overlay_debug.dart': 19,
    'lib/features/board/ui/board_history_panel.dart': 2,
    'lib/features/board/ui/board_tools_panel.dart': 2,
    'lib/features/board/ui/board_view.dart': 0,
    'lib/features/board/ui/miro_panel_toolbar.dart': 33,
    'lib/features/board/ui/board_overview_preview.dart': 57,
    'lib/features/board/chat/chat_panel_widget.dart': 55,
    'lib/features/collaboration/ui/web_mindmap_canvas.dart': 49,
    'lib/features/board/plugins/builtin/filetree_plugin.dart': 47,
    'lib/features/editor/utils/file_type_utils.dart': 47,
    'lib/features/terminal/ui/terminal_panel.dart': 46,
    'lib/features/mindmap/sidebar/show_hide_sidebar.dart': 45,
    'lib/features/editor/ui/file_editor_panel.dart': 37,
    'lib/features/mindmap/nodes/presentation/editor_card.dart': 34,
    'lib/features/collaboration/ui/collaboration_button.dart': 30,
    'lib/features/mindmap/nodes/presentation/agent_card.dart': 30,
    'lib/features/board/plugins/builtin/diff_preview_plugin.dart': 28,
    'lib/features/mindmap/nodes/presentation/diff_card.dart': 28,
    'lib/features/collaboration/ui/guest_terminal_view.dart': 27,
    'lib/features/search/ui/file_search_overlay.dart': 25,
    'lib/features/mindmap/nodes/presentation/file_tree_card.dart': 25,
    'lib/features/board/plugins/builtin/kanban_plugin.dart': 24,
    'lib/features/mindmap/nodes/presentation/files_card.dart': 22,
    'lib/features/mindmap/nodes/presentation/run_card.dart': 22,
    'lib/features/mindmap/nodes/presentation/workspace_card.dart': 18,
    'lib/features/mindmap/nodes/presentation/repo_branch_card.dart': 16,
    'lib/features/collaboration/ui/guest_shell.dart': 15,
    'lib/features/board/plugins/builtin/custom_widget_plugin.dart': 14,
    'lib/features/board/plugins/builtin/webpage_plugin.dart': 13,
    'lib/features/mindmap/model/mindmap_graph_builder.dart': 13,
    'lib/features/board/assistant/yolo_assistant_widget.dart': 11,
    'lib/features/mindmap/nodes/presentation/session_card.dart': 11,
    'lib/features/board/terminal/board_terminal_panel_widget.dart': 10,
    'lib/features/workspaces/bloc/workspace_cubit.dart': 10,
    'lib/features/board/plugins/builtin/files_plugin.dart': 9,
    'lib/features/skills/ui/skills_panel.dart': 9,
    'lib/features/board/plugins/builtin/checklist_plugin.dart': 8,
    'lib/features/workspaces/ui/workspace_panel.dart': 8,
    'lib/features/runs/ui/run_config_dialog.dart': 8,
    'lib/features/board/plugins/builtin/file_preview_plugin.dart': 7,
    'lib/features/settings/ui/env_group_picker.dart': 6,
    'lib/features/board/tools/board_tool.dart': 5,
    'lib/features/board/plugins/builtin/code_snippet_plugin.dart': 5,
    'lib/features/board/plugins/builtin/timer_plugin.dart': 5,
    'lib/features/board/services/board_offscreen_renderer.dart': 5,
    'lib/features/board/widgets/json_widget_renderer.dart': 5,
    'lib/ui/shell/main_shell.dart': 4,
    'lib/features/board/plugins/builtin/markdown_note_plugin.dart': 3,
    'lib/features/board/plugins/builtin/playlist_plugin.dart': 3,
    'lib/features/runs/models/run_config.dart': 3,
    'lib/features/board/plugins/builtin/run_configs_plugin.dart': 2,
    'lib/features/mindmap/bloc/mindmap_cubit.dart': 2,
    'lib/features/board/assistant/assistant_voice_visualizer.dart': 1,
    'lib/features/board/chat/chat_panel_plugin.dart': 1,
    'lib/features/board/chat/provider_icon.dart': 1,
    'lib/features/board/plugins/board_plugin_registry.dart': 1,
    'lib/features/board/plugins/builtin/yolo_assistant_plugin.dart': 1,
    'lib/features/board/terminal/board_terminal_panel_plugin.dart': 1,
    'lib/features/board/model/board_models.dart': 1,
    'lib/features/review/ui/review_panel.dart': 1,
    'lib/features/runs/ui/run_panel.dart': 1,
    'lib/ui/widgets/panel_shell.dart': 1,
  };

  // Directories to scan (relative to repo root)
  const scanDirs = ['lib/features/', 'lib/ui/'];

  // Directories exempt from checking (theme system itself)
  const exemptPrefixes = ['lib/core/theme/'];

  test('no new hardcoded Color(0x...) in UI code (ratchet)', () {
    final repoRoot = _findRepoRoot();
    final pattern = RegExp(r'Color\(0x[0-9A-Fa-f]+\)');
    final violations = <String>[];
    var totalHardcoded = 0;
    var baselineTotal = 0;

    for (final dir in scanDirs) {
      final absDir = Directory('$repoRoot/$dir');
      if (!absDir.existsSync()) continue;

      for (final entity in absDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final relPath = entity.path
            .replaceFirst('$repoRoot/', '')
            .replaceFirst('$repoRoot\\', '');

        // Skip exempt directories
        if (exemptPrefixes.any((p) => relPath.startsWith(p))) continue;

        final content = entity.readAsStringSync();
        final count = pattern.allMatches(content).length;
        if (count == 0) continue;

        totalHardcoded += count;
        final allowed = baseline[relPath] ?? 0;
        baselineTotal += allowed;

        if (count > allowed) {
          if (allowed == 0) {
            violations.add(
              '  NEW: $relPath has $count hardcoded Color(0x...) — '
              'use context.appColors instead',
            );
          } else {
            violations.add(
              '  INCREASED: $relPath has $count (was $allowed) — '
              'do not add new hardcoded colors',
            );
          }
        }
      }
    }

    if (violations.isNotEmpty) {
      fail(
        'Hardcoded colors ratchet check failed!\n'
        '${violations.join('\n')}\n\n'
        'Use context.appColors (AppColorScheme) for colors.\n'
        'If you migrated colors OUT of a file, lower its baseline in\n'
        'test/unit/lint/no_hardcoded_colors_test.dart',
      );
    }

    print(
      '✅ Hardcoded colors ratchet OK '
      '($totalHardcoded current, $baselineTotal baseline across '
      '${baseline.length} files)',
    );
  });

  test('no Colors.white / Colors.black in UI code (ratchet)', () {
    // Also catches hardcoded Colors.white / Colors.black which should
    // come from the theme instead.
    const colorsBaseline = <String, int>{
      'lib/features/board/ui/board_history_panel.dart': 2,
      'lib/features/board/ui/board_tools_panel.dart': 4,
      'lib/features/board/ui/board_panel_card.dart': 1,
      'lib/features/board/ui/board_view.dart': 0,
      'lib/features/board/ui/miro_panel_toolbar.dart': 1,
      'lib/ui/components/menus/miro_toolbar_primitives.dart': 2,
      'lib/features/settings/ui/settings_page.dart': 6,
      'lib/features/settings/ui/dialogs/color_picker_dialog.dart': 3,
      'lib/features/settings/ui/dialogs/key_capture_dialog.dart': 2,
      'lib/features/settings/ui/debug_ui/sections/component_showcase.dart': 2,
      'lib/features/settings/ui/debug_ui/sections/plectrum_debug.dart': 1,
      'lib/features/settings/ui/debug_ui/sections/voice_overlay_debug.dart': 5,
      'lib/features/board/plugins/builtin/file_preview_plugin.dart': 14,
      'lib/features/preview/widgets/markdown_document_preview.dart': 12,
      'lib/features/board/assistant/yolo_voice_overlay.dart': 11,
      'lib/features/board/chat/chat_panel_widget.dart': 8,
      'lib/features/board/plugins/builtin/kanban_plugin.dart': 7,
      'lib/features/updates/ui/update_banner.dart': 6,
      'lib/features/terminal/ui/terminal_panel.dart': 5,
      'lib/features/collaboration/ui/collaboration_button.dart': 3,
      'lib/features/board/ui/board_overview_preview.dart': 3,
      'lib/features/board/plugins/builtin/filetree_plugin.dart': 3,
      'lib/features/board/widgets/json_widget_renderer.dart': 3,
      'lib/features/workspaces/ui/worktree_section.dart': 3,
      'lib/features/search/ui/file_search_overlay.dart': 3,
      'lib/features/mindmap/nodes/presentation/agent_card.dart': 3,
      'lib/features/collaboration/ui/guest_terminal_view.dart': 2,
      'lib/features/board/assistant/yolo_assistant_widget.dart': 2,
      'lib/features/board/plugins/builtin/checklist_plugin.dart': 2,
      'lib/features/workspaces/ui/workspace_panel.dart': 2,
      'lib/ui/shell/main_shell.dart': 2,
      'lib/features/settings/ui/env_group_picker.dart': 1,
      'lib/features/settings/ui/setup_guide_page.dart': 1,
      'lib/features/collaboration/ui/guest_shell.dart': 1,
      'lib/features/collaboration/ui/web_mindmap_canvas.dart': 1,
      'lib/features/board/plugins/builtin/files_plugin.dart': 1,
      'lib/features/board/plugins/builtin/webpage_plugin.dart': 1,
      'lib/features/board/plugins/builtin/timer_plugin.dart': 1,
      'lib/features/board/plugins/builtin/markdown_note_plugin.dart': 1,
      'lib/features/board/plugins/builtin/playlist_plugin.dart': 1,
      'lib/features/board/plugins/builtin/custom_widget_plugin.dart': 1,
      'lib/features/workspaces/ui/new_agent_session_dialog.dart': 1,
      'lib/features/runs/ui/run_config_dialog.dart': 1,
      'lib/features/editor/ui/file_editor_panel.dart': 1,
    };

    final repoRoot = _findRepoRoot();
    final pattern = RegExp(r'Colors\.(white|black)\b');
    final violations = <String>[];

    for (final dir in ['lib/features/', 'lib/ui/']) {
      final absDir = Directory('$repoRoot/$dir');
      if (!absDir.existsSync()) continue;

      for (final entity in absDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final relPath = entity.path
            .replaceFirst('$repoRoot/', '')
            .replaceFirst('$repoRoot\\', '');
        if (['lib/core/theme/'].any((p) => relPath.startsWith(p))) continue;

        final content = entity.readAsStringSync();
        final count = pattern.allMatches(content).length;
        if (count == 0) continue;

        final allowed = colorsBaseline[relPath] ?? 0;
        if (count > allowed) {
          violations.add(
            '  ${allowed == 0 ? "NEW" : "INCREASED"}: '
            '$relPath has $count Colors.white/black (was $allowed)',
          );
        }
      }
    }

    if (violations.isNotEmpty) {
      fail(
        'Colors.white / Colors.black ratchet check failed!\n'
        '${violations.join('\n')}\n\n'
        'Use theme colors from context.appColors instead.',
      );
    }

    print('✅ Colors.white/black ratchet OK');
  });
}

String _findRepoRoot() {
  var dir = Directory.current;
  while (dir.path != dir.parent.path) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
    dir = dir.parent;
  }
  return Directory.current.path;
}
