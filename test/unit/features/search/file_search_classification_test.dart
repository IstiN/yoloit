import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/search/ui/file_search_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const panelIcons = <String, IconData>{
    'board.chat': Icons.chat_outlined,
    'board.terminal': Icons.terminal,
    'board.filetree': Icons.account_tree_outlined,
    'board.file.preview': Icons.description_outlined,
    'board.diff.preview': Icons.difference_outlined,
    'board.note.markdown': Icons.article_outlined,
    'board.code.snippet': Icons.code,
    'board.run.configs': Icons.play_circle_outline,
    'board.webpage': Icons.language,
    'board.checklist': Icons.checklist,
    'board.kanban': Icons.view_kanban_outlined,
    'board.timer': Icons.timer_outlined,
    'board.custom.widget': Icons.widgets_outlined,
    'board.playlist': Icons.queue_music,
    'board.yolo.assistant': Icons.assistant_outlined,
  };
  const panelLabels = <String, String>{
    'board.chat': 'Chat Panel',
    'board.terminal': 'Terminal',
    'board.filetree': 'File Tree',
    'board.file.preview': 'File Preview',
    'board.diff.preview': 'Diff Preview',
    'board.note.markdown': 'Markdown Note',
    'board.code.snippet': 'Code Snippet',
    'board.run.configs': 'Run Configs',
    'board.webpage': 'Web Page',
    'board.checklist': 'Checklist',
    'board.kanban': 'Kanban Board',
    'board.timer': 'Timer',
    'board.custom.widget': 'Custom Widget',
    'board.playlist': 'Playlist',
    'board.yolo.assistant': 'Yolo Assistant',
  };

  test('panel type lookup preserves every icon and label', () {
    for (final entry in panelIcons.entries) {
      expect(
        debugFileSearchPanelTypeIcon(entry.key),
        entry.value,
        reason: entry.key,
      );
    }
    for (final entry in panelLabels.entries) {
      expect(
        debugFileSearchPanelTypeLabel(entry.key),
        entry.value,
        reason: entry.key,
      );
    }

    expect(
      debugFileSearchPanelTypeIcon('board.unknown'),
      Icons.dashboard_outlined,
    );
    expect(debugFileSearchPanelTypeLabel('board.unknown'), 'board.unknown');
  });

  test('file extension lookup preserves every icon and color', () {
    final colors = AppColorScheme.fromAccent(Colors.indigo);

    void expectExtensions(
      List<String> extensions,
      IconData icon,
      Color color,
    ) {
      for (final extension in extensions) {
        final result = debugFileSearchIconForExtension(extension, colors);
        expect(result.$1, icon, reason: extension);
        expect(result.$2, color, reason: extension);
      }
    }

    expectExtensions(['dart'], Icons.flutter_dash, colors.accentBlue);
    expectExtensions(['py'], Icons.code, colors.accentOrange);
    expectExtensions(
      ['js', 'ts', 'jsx', 'tsx'],
      Icons.javascript,
      colors.primaryLight,
    );
    expectExtensions(['swift'], Icons.apple, colors.accentRed);
    expectExtensions(['kt', 'java'], Icons.code, colors.accentOrange);
    expectExtensions(['go'], Icons.code, colors.accentBlue);
    expectExtensions(['rs'], Icons.code, colors.accentOrange);
    expectExtensions(['html', 'htm'], Icons.html, colors.accentRed);
    expectExtensions(['css', 'scss', 'sass'], Icons.style, colors.accentBlue);
    expectExtensions(
      ['json', 'yaml', 'yml', 'toml'],
      Icons.data_object,
      colors.accentOrange,
    );
    expectExtensions(['md', 'mdx'], Icons.article, colors.textMuted);
    expectExtensions(
      ['sh', 'bash', 'zsh'],
      Icons.terminal,
      colors.accentGreen,
    );
    expectExtensions(
      ['png', 'jpg', 'jpeg', 'gif', 'svg', 'webp'],
      Icons.image,
      colors.primaryLight,
    );

    for (final extension in ['unknown', '', 'DART']) {
      final result = debugFileSearchIconForExtension(extension, colors);
      expect(result.$1, Icons.insert_drive_file_outlined, reason: extension);
      expect(result.$2, colors.textMuted, reason: extension);
    }
  });
}
