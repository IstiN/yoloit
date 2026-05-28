from pathlib import Path

ROOT = Path('/Users/Uladzimir_Klyshevich/git/yoloit/yoloit')


def replace_once(text: str, old: str, new: str, path: str) -> str:
    if old not in text:
        raise RuntimeError(f'Missing pattern in {path}: {old[:80]!r}')
    return text.replace(old, new, 1)


def write_rel(path: str, transform):
    file_path = ROOT / path
    text = file_path.read_text()
    new_text = transform(text)
    if new_text != text:
        file_path.write_text(new_text)


write_rel(
    'lib/features/board/plugins/builtin/webpage_plugin.dart',
    lambda text: (
        lambda t: t
    )(
        replace_once(
            replace_once(
                replace_once(
                    replace_once(
                        replace_once(
                            replace_once(
                                replace_once(
                                    replace_once(
                                        replace_once(
                                            replace_once(
                                                replace_once(
                                                    replace_once(
                                                        replace_once(
                                                            replace_once(
                                                                replace_once(
                                                                    replace_once(
                                                                        replace_once(
                                                                            replace_once(
                                                                                replace_once(
                                                                                    replace_once(
                                                                                        text,
                                                                                        "import 'package:flutter/foundation.dart';\nimport 'package:flutter/material.dart';\nimport 'package:webview_flutter/webview_flutter.dart';\nimport 'package:yoloit/core/platform/platform_launcher.dart';\nimport 'package:yoloit/core/services/webview_zoom_service.dart';\n",
                                                                                        "import 'package:flutter/material.dart';\nimport 'package:webview_flutter/webview_flutter.dart';\nimport 'package:yoloit/core/platform/platform_launcher.dart';\nimport 'package:yoloit/core/services/webview_zoom_service.dart';\nimport 'package:yoloit/core/theme/app_color_scheme.dart';\nimport 'package:yoloit/core/theme/theme_manager.dart';\n",
                                                                                        'webpage_plugin.dart',
                                                                                    ),
                                                                                    "  Color get accentColor => const Color(0xFF0EA5E9);",
                                                                                    "  Color get accentColor =>\n      ThemeManager.instance.effectiveScheme.accentBlue;",
                                                                                    'webpage_plugin.dart',
                                                                                ),
                                                                                '  static const Color _accent = Color(0xFF0EA5E9);',
                                                                                '  Color get _accent => context.appColors.accentBlue;',
                                                                                'webpage_plugin.dart',
                                                                            ),
                                                                            '  Widget build(BuildContext context) {\n    final url = _currentUrl;\n',
                                                                            '  Widget build(BuildContext context) {\n    final colors = context.appColors;\n    final url = _currentUrl;\n',
                                                                            'webpage_plugin.dart',
                                                                        ),
                                                                        '                const Icon(Icons.link, size: 14, color: Color(0xFF0EA5E9)),',
                                                                        '                Icon(Icons.link, size: 14, color: colors.accentBlue),',
                                                                        'webpage_plugin.dart',
                                                                    ),
                                                                    '                        borderSide: const BorderSide(color: Color(0xFF0EA5E9)),',
                                                                    '                        borderSide: BorderSide(color: colors.accentBlue),',
                                                                    'webpage_plugin.dart',
                                                                ),
                                                                "                          color: Color(0xFF0EA5E9),\n",
                                                                "                          color: colors.accentBlue,\n",
                                                                'webpage_plugin.dart',
                                                            ),
                                                            "                     color: Color(0xFF64748B),\n",
                                                            "                     color: colors.textSecondary,\n",
                                                            'webpage_plugin.dart',
                                                        ),
                                                        "                           color: Color(0xFFE67E22),\n",
                                                        "                           color: colors.accentOrange,\n",
                                                        'webpage_plugin.dart',
                                                    ),
                                                    '_accent.withOpacity(0.4)',
                                                    '_accent.withValues(alpha: 0.4)',
                                                    'webpage_plugin.dart',
                                                ),
                                                "                             color: Color(0xFF64748B),\n",
                                                "                             color: colors.textSecondary,\n",
                                                'webpage_plugin.dart',
                                            ),
                                            '                  : Container(color: Colors.white),',
                                            '                  : ColoredBox(color: colors.surface),',
                                            'webpage_plugin.dart',
                                        ),
                                        "           child: Icon(icon, size: 15, color: const Color(0xFF94A3B8)),\n",
                                        "           child: Icon(icon, size: 15, color: colors.textMuted),\n",
                                        'webpage_plugin.dart',
                                    ),
                                    '  Widget build(BuildContext context) {\n    return Tooltip(\n',
                                    '  Widget build(BuildContext context) {\n    final colors = context.appColors;\n    return Tooltip(\n',
                                    'webpage_plugin.dart',
                                ),
                                '  Widget build(BuildContext context) {\n    return Dialog(\n',
                                '  Widget build(BuildContext context) {\n    final colors = context.appColors;\n    return Dialog(\n',
                                'webpage_plugin.dart',
                            ),
                            "                     color: Color(0xFFE67E22),\n",
                            "                     color: colors.accentOrange,\n",
                            'webpage_plugin.dart',
                        ),
                        "                             color: Colors.grey,\n",
                        "                             color: colors.textSecondary,\n",
                        'webpage_plugin.dart',
                    ),
                    '                  color: const Color(0xFFE67E22).withOpacity(0.1),',
                    '                  color: colors.accentOrange.withValues(alpha: 0.1),',
                    'webpage_plugin.dart',
                ),
                '                    color: const Color(0xFFE67E22).withOpacity(0.3),',
                '                    color: colors.accentOrange.withValues(alpha: 0.3),',
                'webpage_plugin.dart',
            ),
            '                      backgroundColor: const Color(0xFFE67E22),',
            '                      backgroundColor: colors.accentOrange,',
            'webpage_plugin.dart',
        )
    ),
)

write_rel(
    'lib/features/board/plugins/builtin/timer_plugin.dart',
    lambda text: (
        lambda t: t
    )(
        replace_once(
            replace_once(
                replace_once(
                    replace_once(
                        replace_once(
                            replace_once(
                                text,
                                "import 'package:flutter_bloc/flutter_bloc.dart';\nimport 'package:yoloit/core/theme/app_color_scheme.dart';\n",
                                "import 'package:flutter_bloc/flutter_bloc.dart';\nimport 'package:yoloit/core/theme/app_color_scheme.dart';\nimport 'package:yoloit/core/theme/theme_manager.dart';\n",
                                'timer_plugin.dart',
                            ),
                            "  Color get accentColor => const Color(0xFF3B82F6);",
                            "  Color get accentColor => ThemeManager.instance.effectiveScheme.accentBlue;",
                            'timer_plugin.dart',
                        ),
                        "  static const Color _accent = Color(0xFF3B82F6);\n  static const Color _completedColor = Color(0xFF10B981);\n  static const Color _warningColor = Color(0xFFF59E0B);\n",
                        "  Color get _accent => context.appColors.accentBlue;\n  Color get _completedColor => context.appColors.accentGreen;\n  Color get _warningColor => context.appColors.accentOrange;\n",
                        'timer_plugin.dart',
                    ),
                    '                    color: Colors.white,',
                    '                    color: colors.textPrimary,',
                    'timer_plugin.dart',
                ),
                '                 borderSide: const BorderSide(color: _accent, width: 1.5),',
                '                 borderSide: BorderSide(color: colors.accentBlue, width: 1.5),',
                'timer_plugin.dart',
            ),
            '                borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),',
            '                borderSide: BorderSide(color: colors.accentBlue, width: 1.5),',
            'timer_plugin.dart',
        )
    ),
)

write_rel(
    'lib/features/board/plugins/builtin/code_snippet_plugin.dart',
    lambda text: (
        lambda t: t
    )(
        replace_once(
            replace_once(
                replace_once(
                    replace_once(
                        replace_once(
                            replace_once(
                                replace_once(
                                    replace_once(
                                        text,
                                        "import 'package:highlight/languages/yaml.dart';\nimport 'package:yoloit/features/board/model/board_models.dart';\nimport 'package:yoloit/features/board/plugins/board_plugin.dart';\n",
                                        "import 'package:highlight/languages/yaml.dart';\nimport 'package:yoloit/core/theme/app_color_scheme.dart';\nimport 'package:yoloit/core/theme/theme_manager.dart';\nimport 'package:yoloit/features/board/model/board_models.dart';\nimport 'package:yoloit/features/board/plugins/board_plugin.dart';\n",
                                        'code_snippet_plugin.dart',
                                    ),
                                    '  Color get accentColor => const Color(0xFF10B981);',
                                    '  Color get accentColor => ThemeManager.instance.effectiveScheme.accentGreen;',
                                    'code_snippet_plugin.dart',
                                ),
                                '  static const Color _accent = Color(0xFF10B981);',
                                '  Color get _accent => context.appColors.accentGreen;',
                                'code_snippet_plugin.dart',
                            ),
                            '  Widget build(BuildContext context) {\n    return Column(\n',
                            '  Widget build(BuildContext context) {\n    final colors = context.appColors;\n    return Column(\n',
                            'code_snippet_plugin.dart',
                        ),
                        '_accent.withOpacity(0.08)',
                        '_accent.withValues(alpha: 0.08)',
                        'code_snippet_plugin.dart',
                    ),
                    '_accent.withOpacity(0.15)',
                    '_accent.withValues(alpha: 0.15)',
                    'code_snippet_plugin.dart',
                ),
                '              const Icon(Icons.code, size: 14, color: Color(0xFF10B981)),',
                '              Icon(Icons.code, size: 14, color: colors.accentGreen),',
                'code_snippet_plugin.dart',
            ),
            "                  style: const TextStyle(fontSize: 12, color: Color(0xFF10B981)),\n",
            "                  style: TextStyle(fontSize: 12, color: colors.accentGreen),\n",
            'code_snippet_plugin.dart',
        )
        .replace(
            '_copied ? Colors.greenAccent : const Color(0xFF94A3B8)',
            '_copied ? colors.accentGreen : colors.textMuted',
        )
    ),
)

write_rel(
    'lib/features/board/plugins/builtin/markdown_note_plugin.dart',
    lambda text: (
        lambda t: t
    )(
        replace_once(
            replace_once(
                replace_once(
                    replace_once(
                        replace_once(
                            replace_once(
                                replace_once(
                                    text,
                                    "import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';\nimport 'package:yoloit/features/preview/widgets/markdown_document_preview.dart';\nimport 'package:yoloit/features/board/model/board_models.dart';\nimport 'package:yoloit/features/board/plugins/board_plugin.dart';\n",
                                    "import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';\nimport 'package:yoloit/core/theme/app_color_scheme.dart';\nimport 'package:yoloit/core/theme/theme_manager.dart';\nimport 'package:yoloit/features/board/model/board_models.dart';\nimport 'package:yoloit/features/board/plugins/board_plugin.dart';\nimport 'package:yoloit/features/preview/widgets/markdown_document_preview.dart';\n",
                                    'markdown_note_plugin.dart',
                                ),
                                '  Color get accentColor => const Color(0xFFB46CFF);',
                                '  Color get accentColor => ThemeManager.instance.effectiveScheme.primaryLight;',
                                'markdown_note_plugin.dart',
                            ),
                            '  Widget build(BuildContext context) {\n    final markdown = widget.markdown.isEmpty ? \'*Empty note*\' : widget.markdown;\n',
                            '  Widget build(BuildContext context) {\n    final colors = context.appColors;\n    final markdown = widget.markdown.isEmpty ? \'*Empty note*\' : widget.markdown;\n',
                            'markdown_note_plugin.dart',
                        ),
                        '                                 ? Colors.green\n',
                        '                                 ? colors.accentGreen\n',
                        'markdown_note_plugin.dart',
                    ),
                    '                                   ? Colors.green\n',
                    '                                   ? colors.accentGreen\n',
                    'markdown_note_plugin.dart',
                ),
                '    Color picked = _selectedColor ?? const Color(0xFFB46CFF);',
                '    Color picked = _selectedColor ?? context.appColors.primaryLight;',
                'markdown_note_plugin.dart',
            ),
            '  Widget build(BuildContext context) {\n    return AlertDialog(\n',
            '  Widget build(BuildContext context) {\n    final colors = context.appColors;\n    return AlertDialog(\n',
            'markdown_note_plugin.dart',
        )
        .replace('const Color(0xFFB46CFF)', 'colors.primaryLight')
        .replace(
            'Colors.white.withAlpha(90)',
            'colors.textPrimary.withValues(alpha: 90 / 255)',
        )
    ),
)

write_rel(
    'lib/features/board/plugins/builtin/playlist_plugin.dart',
    lambda text: (
        lambda t: t
    )(
        replace_once(
            replace_once(
                replace_once(
                    replace_once(
                        replace_once(
                            replace_once(
                                replace_once(
                                    replace_once(
                                        replace_once(
                                            text,
                                            "import 'package:media_kit_video/media_kit_video.dart';\nimport 'package:yoloit/core/theme/app_color_scheme.dart';\n",
                                            "import 'package:media_kit_video/media_kit_video.dart';\nimport 'package:yoloit/core/theme/app_color_scheme.dart';\nimport 'package:yoloit/core/theme/theme_manager.dart';\n",
                                            'playlist_plugin.dart',
                                        ),
                                        '  Color get accentColor => const Color(0xFF8B5CF6);',
                                        '  Color get accentColor => ThemeManager.instance.effectiveScheme.primary;',
                                        'playlist_plugin.dart',
                                    ),
                                    '  static const Color _accent = Color(0xFF8B5CF6);',
                                    '  Color get _accent => context.appColors.primary;',
                                    'playlist_plugin.dart',
                                ),
                                '  static const Color _accent = Color(0xFF8B5CF6);\n  bool _hovered = false;\n',
                                '  Color get _accent => context.appColors.primary;\n  bool _hovered = false;\n',
                                'playlist_plugin.dart',
                            ),
                            '      barrierColor: Colors.black45,',
                            '      barrierColor: context.appColors.background.withValues(alpha: 0.45),',
                            'playlist_plugin.dart',
                        ),
                        '                          color: Colors.white,',
                        '                          color: colors.textPrimary,',
                        'playlist_plugin.dart',
                    ),
                    '_accent.withOpacity(0.12)',
                    '_accent.withValues(alpha: 0.12)',
                    'playlist_plugin.dart',
                ),
                '_accent.withOpacity(0.7)',
                '_accent.withValues(alpha: 0.7)',
                'playlist_plugin.dart',
            ),
            '_accent.withOpacity(0.35)',
            '_accent.withValues(alpha: 0.35)',
            'playlist_plugin.dart',
        )
        .replace('_accent.withOpacity(0.15)', '_accent.withValues(alpha: 0.15)')
        .replace('_accent.withOpacity(0.1)', '_accent.withValues(alpha: 0.1)')
        .replace('Colors.redAccent', 'colors.accentRed')
        .replace(
            "    ctrl.dispose();\n    nameCtrl.dispose();\n    if (confirmed != true) return;\n    final url = ctrl.text.trim();\n    if (url.isEmpty) return;\n    final name = nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : url.split('/').last;\n",
            "    final url = ctrl.text.trim();\n    final providedName = nameCtrl.text.trim();\n    ctrl.dispose();\n    nameCtrl.dispose();\n    if (confirmed != true) return;\n    if (url.isEmpty) return;\n    final name = providedName.isNotEmpty ? providedName : url.split('/').last;\n",
        )
    ),
)

for rel_path in [
    'lib/features/board/plugins/builtin/run_configs_plugin.dart',
    'lib/features/board/plugins/builtin/yolo_assistant_plugin.dart',
    'lib/features/board/chat/chat_panel_plugin.dart',
    'lib/features/board/terminal/board_terminal_panel_plugin.dart',
]:
    def _transform(text, rel_path=rel_path):
        text = replace_once(
            text,
            "import 'package:flutter/material.dart';\n",
            "import 'package:flutter/material.dart';\nimport 'package:yoloit/core/theme/theme_manager.dart';\n",
            rel_path,
        )
        mapping = {
            'run_configs_plugin.dart': 'ThemeManager.instance.effectiveScheme.accentGreen',
            'yolo_assistant_plugin.dart': 'ThemeManager.instance.effectiveScheme.primary',
            'chat_panel_plugin.dart': 'ThemeManager.instance.effectiveScheme.accentGreen',
            'board_terminal_panel_plugin.dart': 'ThemeManager.instance.effectiveScheme.accentGreen',
        }
        filename = rel_path.split('/')[-1]
        old_values = {
            'run_configs_plugin.dart': [
                '  Color get accentColor => const Color(0xFF22C55E);',
            ],
            'yolo_assistant_plugin.dart': [
                '  Color get accentColor => const Color(0xFF8B5CF6);',
            ],
            'chat_panel_plugin.dart': [
                '  Color get accentColor => const Color(0xFF34D399);',
            ],
            'board_terminal_panel_plugin.dart': [
                '  Color get accentColor => const Color(0xFF22C55E);',
            ],
        }[filename]
        for old in old_values:
            text = replace_once(text, old, f'  Color get accentColor => {mapping[filename]};', rel_path)
        return text
    write_rel(rel_path, _transform)

write_rel(
    'lib/features/board/plugins/board_plugin_registry.dart',
    lambda text: (
        lambda t: t
    )(
        replace_once(
            replace_once(
                text,
                "import 'package:flutter/material.dart';\nimport 'package:yoloit/features/board/chat/chat_panel_plugin.dart';\n",
                "import 'package:flutter/material.dart';\nimport 'package:yoloit/core/theme/app_color_scheme.dart';\nimport 'package:yoloit/features/board/chat/chat_panel_plugin.dart';\n",
                'board_plugin_registry.dart',
            ),
            "  Widget buildContent(context, panel, renderContext) => Center(\n    child: Text(\n      'Unknown panel type: ${panel.type}',\n      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),\n      textAlign: TextAlign.center,\n    ),\n  );\n",
            "  Widget buildContent(\n    BuildContext context,\n    panel,\n    renderContext,\n  ) {\n    final colors = context.appColors;\n    return Center(\n      child: Text(\n        'Unknown panel type: ${panel.type}',\n        style: TextStyle(color: colors.textMuted, fontSize: 12),\n        textAlign: TextAlign.center,\n      ),\n    );\n  }\n",
            'board_plugin_registry.dart',
        )
    ),
)

write_rel(
    'lib/features/board/tools/board_tool.dart',
    lambda text: (
        lambda t: t
    )(
        replace_once(
            replace_once(
                replace_once(
                    replace_once(
                        replace_once(
                            replace_once(
                                replace_once(
                                    text,
                                    "import 'package:flutter/material.dart';\nimport 'package:yoloit/features/board/model/board_models.dart'\n",
                                    "import 'package:flutter/material.dart';\nimport 'package:yoloit/core/theme/theme_manager.dart';\nimport 'package:yoloit/features/board/model/board_models.dart'\n",
                                    'board_tool.dart',
                                ),
                                '  Color get accentColor => const Color(0xFF60A5FA);',
                                '  Color get accentColor => ThemeManager.instance.effectiveScheme.accentBlue;',
                                'board_tool.dart',
                            ),
                            '  Color get accentColor => const Color(0xFFA78BFA);',
                            '  Color get accentColor => ThemeManager.instance.effectiveScheme.primaryLight;',
                            'board_tool.dart',
                        ),
                        '  Color get accentColor => const Color(0xFF34D399);',
                        '  Color get accentColor => ThemeManager.instance.effectiveScheme.accentGreen;',
                        'board_tool.dart',
                    ),
                    "class DrawSettings {\n  const DrawSettings({\n    this.strokeColor = const Color(0xFFE879F9),\n    this.strokeWidth = 3.0,\n  });\n\n  final Color strokeColor;\n",
                    "class DrawSettings {\n  DrawSettings({\n    Color? strokeColor,\n    this.strokeWidth = 3.0,\n  }) : strokeColor =\n           strokeColor ?? ThemeManager.instance.effectiveScheme.primaryLight;\n\n  final Color strokeColor;\n",
                    'board_tool.dart',
                ),
                "class ConnectSettings {\n  const ConnectSettings({\n    this.geometry = BoardLinkGeometry.bezier,\n    this.showArrow = true,\n    this.color = const Color(0xFF60A5FA),\n  });\n\n  final BoardLinkGeometry geometry;\n  final bool showArrow;\n  final Color color;\n",
                "class ConnectSettings {\n  ConnectSettings({\n    this.geometry = BoardLinkGeometry.bezier,\n    this.showArrow = true,\n    Color? color,\n  }) : color = color ?? ThemeManager.instance.effectiveScheme.accentBlue;\n\n  final BoardLinkGeometry geometry;\n  final bool showArrow;\n  final Color color;\n",
                'board_tool.dart',
            ),
            '    this.color = const Color(0xFF60A5FA),',
            '    Color? color,',
            'board_tool.dart',
        )
    ),
)

write_rel(
    'lib/features/board/model/board_models.dart',
    lambda text: (
        lambda t: t
    )(
        replace_once(
            replace_once(
                text,
                "import 'package:equatable/equatable.dart';\nimport 'package:flutter/material.dart';\n",
                "import 'package:equatable/equatable.dart';\nimport 'package:flutter/material.dart';\nimport 'package:yoloit/core/theme/theme_manager.dart';\n",
                'board_models.dart',
            ),
            "class BoardPanelLink extends Equatable {\n  const BoardPanelLink({\n    required this.id,\n    required this.fromPanelId,\n    required this.toPanelId,\n    this.style = BoardLinkStyle.arrow,\n    this.behavior = BoardLinkBehavior.fixed,\n    this.color = const Color(0xFF60A5FA),\n    this.geometry = BoardLinkGeometry.bezier,\n  });\n",
            "class BoardPanelLink extends Equatable {\n  BoardPanelLink({\n    required this.id,\n    required this.fromPanelId,\n    required this.toPanelId,\n    this.style = BoardLinkStyle.arrow,\n    this.behavior = BoardLinkBehavior.fixed,\n    Color? color,\n    this.geometry = BoardLinkGeometry.bezier,\n  }) : color = color ?? ThemeManager.instance.effectiveScheme.accentBlue;\n",
            'board_models.dart',
        )
    ),
)

write_rel(
    'lib/features/board/chat/provider_icon.dart',
    lambda text: (
        lambda t: t
    )(
        replace_once(
            replace_once(
                replace_once(
                    replace_once(
                        replace_once(
                            text,
                            "import 'package:flutter/material.dart';\nimport 'package:flutter_svg/flutter_svg.dart';\n",
                            "import 'package:flutter/material.dart';\nimport 'package:flutter_svg/flutter_svg.dart';\nimport 'package:yoloit/core/theme/app_color_scheme.dart';\n",
                            'provider_icon.dart',
                        ),
                        '    this.color = const Color(0xFF34D399),',
                        '    this.color,',
                        'provider_icon.dart',
                    ),
                    '  final Color color;\n',
                    '  final Color? color;\n',
                    'provider_icon.dart',
                ),
                '  Widget build(BuildContext context) {\n    return switch (provider) {\n',
                '  Widget build(BuildContext context) {\n    final resolvedColor = color ?? context.appColors.accentGreen;\n    return switch (provider) {\n',
                'provider_icon.dart',
            ),
            'ColorFilter.mode(color, BlendMode.srcIn)',
            'ColorFilter.mode(resolvedColor, BlendMode.srcIn)',
            'provider_icon.dart',
        )
        .replace('color: color,', 'color: resolvedColor,')
    ),
)

write_rel(
    'lib/features/board/terminal/board_terminal_panel_widget.dart',
    lambda text: (
        lambda t: t
    )(
        text.replace('const Color(0xFF34D399)', 'colors.accentGreen')
        .replace('Color(0xFFF87171)', 'colors.accentRed')
        .replace('Color(0xFF22C55E)', 'colors.accentGreen')
        .replace('Color(0xFF60A5FA)', 'colors.accentBlue')
        .replace('Color(0xFFF59E0B)', 'colors.accentOrange')
        .replace('foregroundColor: colors.surface,', 'foregroundColor: colors.textPrimary,')
    ),
)

write_rel(
    'lib/features/board/services/board_offscreen_renderer.dart',
    lambda text: (
        lambda t: t
    )(
        replace_once(
            replace_once(
                replace_once(
                    replace_once(
                        replace_once(
                            replace_once(
                                replace_once(
                                    text,
                                    "import 'package:flutter_bloc/flutter_bloc.dart';\n\nimport 'package:yoloit/core/theme/theme_manager.dart';\n",
                                    "import 'package:flutter_bloc/flutter_bloc.dart';\n\nimport 'package:yoloit/core/theme/app_color_scheme.dart';\nimport 'package:yoloit/core/theme/theme_manager.dart';\n",
                                    'board_offscreen_renderer.dart',
                                ),
                                '    final originalErrorBuilder = ErrorWidget.builder;\n',
                                '    final colors = ThemeManager.instance.effectiveScheme;\n    final originalErrorBuilder = ErrorWidget.builder;\n',
                                'board_offscreen_renderer.dart',
                            ),
                            '        color: Color(0x20808080),',
                            '        color: colors.textMuted.withValues(alpha: 0.13),',
                            'board_offscreen_renderer.dart',
                        ),
                        '            color: Color(0x80808080),',
                        '            color: colors.textSecondary.withValues(alpha: 0.5),',
                        'board_offscreen_renderer.dart',
                    ),
                    '    final theme = ThemeManager.instance.theme;\n',
                    '    final theme = ThemeManager.instance.theme;\n    final colors = theme.extension<AppColorScheme>() ?? ThemeManager.instance.effectiveScheme;\n',
                    'board_offscreen_renderer.dart',
                ),
                '                    color: Color(0xFFE0E0F0),',
                '                    color: colors.textPrimary,',
                'board_offscreen_renderer.dart',
            ),
            '                      color: Color(0xFF8888AA),',
            '                      color: colors.textSecondary,',
            'board_offscreen_renderer.dart',
        )
        .replace('                      color: const Color(0xFF0F0F1A),', '                      color: colors.background,')
    ),
)

write_rel(
    'lib/features/board/widgets/json_widget_renderer.dart',
    lambda text: (
        lambda t: t
    )(
        replace_once(
            replace_once(
                replace_once(
                    replace_once(
                        replace_once(
                            text,
                            "import 'package:flutter/material.dart';\n",
                            "import 'package:flutter/material.dart';\nimport 'package:yoloit/core/theme/app_color_scheme.dart';\nimport 'package:yoloit/core/theme/theme_manager.dart';\n",
                            'json_widget_renderer.dart',
                        ),
                        'class JsonWidgetRenderer {\n  const JsonWidgetRenderer({required this.onEvent});\n\n  /// Called when a user-triggered event fires (e.g. button tap).\n  final void Function(String actionId, Map<String, dynamic> payload) onEvent;\n\n  Widget build(Map<String, dynamic>? tree, [BuildContext? ctx]) {\n    if (tree == null) return const SizedBox.shrink();\n    return _build(tree);\n  }\n',
                        'class JsonWidgetRenderer {\n  JsonWidgetRenderer({required this.onEvent});\n\n  /// Called when a user-triggered event fires (e.g. button tap).\n  final void Function(String actionId, Map<String, dynamic> payload) onEvent;\n  AppColorScheme? _colors;\n\n  Widget build(Map<String, dynamic>? tree, [BuildContext? ctx]) {\n    _colors = ctx?.appColors ?? ThemeManager.instance.effectiveScheme;\n    if (tree == null) return const SizedBox.shrink();\n    return _build(tree);\n  }\n',
                        'json_widget_renderer.dart',
                    ),
                    '    color: _color(m[\'color\'] as String?) ?? const Color(0x33FFFFFF),',
                    '    color: _color(m[\'color\'] as String?) ?? (_colors ?? ThemeManager.instance.effectiveScheme).textPrimary.withValues(alpha: 0.2),',
                    'json_widget_renderer.dart',
                ),
                "    'white': Colors.white,\n    'black': Colors.black,\n",
                "    'white': (_colors ?? ThemeManager.instance.effectiveScheme).textPrimary,\n    'black': (_colors ?? ThemeManager.instance.effectiveScheme).background,\n",
                'json_widget_renderer.dart',
            ),
            '    final color = _color(m[\'color\'] as String? ?? \'#4ade80\') ?? Colors.greenAccent;',
            '    final color = _color(m[\'color\'] as String? ?? \'#4ade80\') ?? (_colors ?? ThemeManager.instance.effectiveScheme).accentGreen;',
            'json_widget_renderer.dart',
        )
        .replace(
            "      style: widget.style ?? const TextStyle(color: Colors.white, fontSize: 14),",
            "      style: widget.style ?? TextStyle(color: context.appColors.textPrimary, fontSize: 14),",
        )
        .replace(
            "        fillColor: const Color(0xFF1e293b),",
            "        fillColor: context.appColors.surface,",
        )
        .replace(
            "          borderSide: const BorderSide(color: Color(0xFF334155)),",
            "          borderSide: BorderSide(color: context.appColors.border),",
        )
        .replace(
            "          borderSide: const BorderSide(color: Color(0xFF3b82f6)),",
            "          borderSide: BorderSide(color: context.appColors.accentBlue),",
        )
    ),
)

write_rel(
    'lib/features/board/assistant/assistant_voice_visualizer.dart',
    lambda text: (
        lambda t: t
    )(
        replace_once(
            replace_once(
                replace_once(
                    replace_once(
                        text,
                        "import 'package:flutter/material.dart';\n",
                        "import 'package:flutter/material.dart';\nimport 'package:yoloit/core/theme/app_color_scheme.dart';\n",
                        'assistant_voice_visualizer.dart',
                    ),
                    '    this.color = const Color(0xFF8B5CF6),',
                    '    this.color,',
                    'assistant_voice_visualizer.dart',
                ),
                '  final Color color;\n',
                '  final Color? color;\n',
                'assistant_voice_visualizer.dart',
            ),
            '  Widget build(BuildContext context) {\n    return AnimatedBuilder(\n',
            '  Widget build(BuildContext context) {\n    final color = widget.color ?? context.appColors.primary;\n    return AnimatedBuilder(\n',
            'assistant_voice_visualizer.dart',
        )
        .replace('              color: widget.color,', '              color: color,')
    ),
)

write_rel(
    'lib/features/board/assistant/yolo_assistant_widget.dart',
    lambda text: (
        lambda t: t
    )(
        text.replace('  static const _kAccent = Color(0xFF8B5CF6);', '  Color get _kAccent => context.appColors.primary;')
        .replace('                    ? const Color(0x1434D399)', '                    ? colors.accentGreen.withValues(alpha: 0.08)')
        .replace('                      ? const Color(0x5534D399)', '                      ? colors.accentGreen.withValues(alpha: 0.33)')
        .replace('                        ? const Color(0xFF34D399)', '                        ? colors.accentGreen')
        .replace('                        colors: [Color(0xFF3B82F6), Color(0xFF6366F1)],', '                        colors: [colors.accentBlue, colors.primary],')
        .replace('                        color: Colors.white,', '                        color: colors.textPrimary,')
        .replace('                color: Colors.white,', '                color: colors.textPrimary,')
        .replace('                            color: const Color(0xFF34D399), width: 0.5)', '                            color: colors.accentGreen, width: 0.5)')
        .replace('                            ? const Color(0xFF34D399)', '                            ? colors.accentGreen')
        .replace('                                    ? const Color(0xFF34D399)', '                                    ? colors.accentGreen')
        .replace('                          color: const Color(0xFF60A5FA),', '                          color: colors.accentBlue,')
        .replace('                        color: const Color(0xFFF87171),', '                        color: colors.accentRed,')
    ),
)

write_rel(
    'lib/features/board/plugins/builtin/webpage_plugin.dart',
    lambda text: text.replace('Window.dispatchEvent', 'window.dispatchEvent'),
)

write_rel(
    'lib/features/board/ui/board_view.dart',
    lambda text: text.replace('  DrawSettings _drawSettings = const DrawSettings();\n  ConnectSettings _connectSettings = const ConnectSettings();\n', '  DrawSettings _drawSettings = DrawSettings();\n  ConnectSettings _connectSettings = ConnectSettings();\n'),
)
