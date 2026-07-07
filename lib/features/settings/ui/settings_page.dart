import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/settings/ui/cloud_providers_section.dart';
import 'package:yoloit/features/settings/ui/debug_ui/debug_ui_shell.dart';
import 'package:yoloit/features/settings/ui/global_env_groups_section.dart';
import 'package:yoloit/features/settings/ui/sections/about_section.dart';
import 'package:yoloit/features/settings/ui/sections/agent_settings_section.dart';
import 'package:yoloit/features/settings/ui/sections/chat_context_section.dart';
import 'package:yoloit/features/settings/ui/sections/ignored_tool_calls_section.dart';
import 'package:yoloit/features/settings/ui/sections/notifications_section.dart';
import 'package:yoloit/features/settings/ui/sections/prompts_section.dart';
import 'package:yoloit/features/settings/ui/sections/section_header.dart';
import 'package:yoloit/features/settings/ui/sections/session_settings_section.dart';
import 'package:yoloit/features/settings/ui/sections/shortcuts_table_section.dart';
import 'package:yoloit/features/settings/ui/sections/support_section.dart';
import 'package:yoloit/features/settings/ui/sections/terminal_renderer_settings.dart';
import 'package:yoloit/features/settings/ui/setup_guide_page.dart';
import 'package:yoloit/features/settings/ui/sync_section.dart';
import 'package:yoloit/features/settings/ui/widget_permissions_section.dart';
import 'package:yoloit/features/settings/ui/widgets/theme_selector.dart';
import 'package:yoloit/features/skills/bloc/skills_cubit.dart';
import 'package:yoloit/features/skills/ui/skills_panel.dart';
import 'package:yoloit/features/templates/ui/template_sources_section.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';


const _kDesktopCategories = [
  'Appearance',
  'AI & Models',
  'Prompts',
  'Environment',
  'Notifications',
  'Sessions',
  'Shortcuts',
  'Skills',
  'Sync',
  'Setup Guide',
  'Apps & Widgets',
  'Support',
  'About',
  'Templates',
];

const _kWebCategories = [
  'Appearance',
  'AI & Models',
  'Environment',
  'Notifications',
  'Shortcuts',
  'Skills',
  'Sync',
  'Support',
  'Templates',
];

List<String> get _kCategories =>
    kIsWeb ? _kWebCategories : _kDesktopCategories;

List<String> get _kDebugCategories =>
    kIsWeb ? [..._kWebCategories, 'Debug UI'] : [..._kDesktopCategories, 'Debug UI'];

class _SettingsDialogChild extends StatelessWidget {
  const _SettingsDialogChild({
    required this.dialogContext,
    this.initialCategory,
  });

  final BuildContext dialogContext;
  final String? initialCategory;

  @override
  Widget build(BuildContext context) {
    final child = SettingsPage(initialCategory: initialCategory);
    return ScaffoldMessenger(
      child: useFullscreenDialogs(dialogContext)
          ? Dialog.fullscreen(child: child)
          : Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 60,
                vertical: 40,
              ),
              child: child,
            ),
    );
  }
}

/// Settings overlay shown as a modal dialog with sidebar navigation.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.initialCategory});

  final String? initialCategory;

  static Future<void> show(BuildContext context, {String? initialCategory}) {
    final wsCubit = context.read<WorkspaceCubit>();
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      builder:
          (dialogContext) => BlocProvider(
            create: (_) => SkillsCubit(),
            child: BlocProvider.value(
              value: wsCubit,
              child: _SettingsDialogChild(
                initialCategory: initialCategory,
                dialogContext: dialogContext,
              ),
            ),
          ),
    );
  }

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedCategory = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCategory;
    if (initial == null || initial.isEmpty) {
      return;
    }
    final index = _kCategories.indexOf(initial);
    if (index >= 0) {
      _selectedCategory = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final fullscreen = useFullscreenDialogs(context);
    return Container(
      constraints:
          fullscreen
              ? null
              : const BoxConstraints(maxWidth: 900, maxHeight: 780),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(fullscreen ? 0 : 12),
        border: fullscreen ? null : Border.all(color: colors.border),
        boxShadow: [
          if (!fullscreen)
            BoxShadow(
              color: Colors.black.withAlpha(120),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          Divider(height: 1, color: colors.border),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSidebar(context),
                VerticalDivider(width: 1, color: colors.border),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          Text(
            'Settings',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 18,
              color: context.appColors.textMuted,
            ),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  List<String> get _categories => kDebugMode ? _kDebugCategories : _kCategories;

  Widget _buildSidebar(BuildContext context) {
    final colors = context.appColors;
    final cats = _categories;
    return SizedBox(
      width: 140,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: cats.length,
        itemBuilder: (context, index) {
          final isActive = index == _selectedCategory;
          return InkWell(
            onTap: () => setState(() => _selectedCategory = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: isActive ? colors.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                cats[index],
                style: TextStyle(
                  color:
                      isActive
                          ? colors.primary
                          : Theme.of(context).textTheme.bodyMedium?.color,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    final categories = _categories;
    final category = categories[_selectedCategory];

    // Skills panel needs full height, not scrollable wrapper
    if (category == 'Skills') {
      return const SkillsPanel();
    }

    final content = switch (category) {
      'Appearance' => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Appearance'),
          SizedBox(height: 12),
          ThemeSelector(),
        ],
      ),
      'AI \u0026 Models' => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Cloud Providers'),
          SizedBox(height: 12),
          CloudProvidersSection(),
          SizedBox(height: 24),
          SectionHeader(title: 'AI Agents'),
          SizedBox(height: 12),
          AgentSettingsSection(),
          SizedBox(height: 20),
          SectionHeader(title: 'Ignored Tool Calls'),
          SizedBox(height: 12),
          IgnoredToolCallsSection(),
          SizedBox(height: 20),
          SectionHeader(title: 'Chat Context'),
          SizedBox(height: 12),
          ChatContextSection(),
        ],
      ),
      'Prompts' => const PromptsSection(),
      'Environment' => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Environment'),
          SizedBox(height: 12),
          GlobalEnvGroupsSection(),
        ],
      ),
      'Notifications' => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Notifications'),
          SizedBox(height: 12),
          NotificationsSection(),
        ],
      ),
      'Sessions' => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Sessions'),
          SizedBox(height: 12),
          SessionSettings(),
        ],
      ),
      'Shortcuts' => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Keyboard Shortcuts'),
          SizedBox(height: 12),
          ShortcutsTable(),
        ],
      ),
      'Sync' => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Sync'),
          SizedBox(height: 12),
          SyncSection(),
        ],
      ),
      'Setup Guide' => const SetupGuideEmbedded(),
      'Apps \u0026 Widgets' => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Terminal'),
          SizedBox(height: 12),
          TerminalRendererSettings(),
          SizedBox(height: 24),
          SectionHeader(title: 'Widget API Permissions'),
          SizedBox(height: 12),
          WidgetPermissionsSection(),
        ],
      ),
      'Support' => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Support'),
          SizedBox(height: 12),
          SupportSection(),
        ],
      ),
      'About' => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'About'),
          SizedBox(height: 12),
          AboutSection(),
        ],
      ),
      'Templates' => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Templates'),
          SizedBox(height: 12),
          TemplateSourcesSection(),
        ],
      ),
      _ => kDebugMode ? const DebugUIShell() : const SizedBox.shrink(),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: content,
    );
  }
}
