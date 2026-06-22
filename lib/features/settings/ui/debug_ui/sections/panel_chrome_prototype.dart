import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/ui/components/buttons/header_icon_button.dart';
import 'package:yoloit/ui/components/buttons/toolbar_button.dart';
import 'package:yoloit/ui/components/chips/panel_id_chip.dart';
import 'package:yoloit/ui/components/layout/panel_content_toolbar.dart';
import 'package:yoloit/ui/components/layout/showcase_scaffold.dart';
import 'package:yoloit/ui/components/menus/hover_overflow_menu.dart';
import 'package:yoloit/ui/components/typography/section_title.dart';

/// Debug UI prototype for the redesigned panel chrome.
///
/// Goal: unify the floating toolbar and the panel header into a single,
/// always-visible header. Primary actions are shown inline; secondary actions
/// appear in a hover-reveal overflow menu.
class PanelChromePrototype extends StatelessWidget {
  const PanelChromePrototype({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ShowcaseScaffold(
      children: [
        const SectionTitle('Selected panel — full chrome'),
        const SizedBox(height: 8),
        _MockPanel(
          title: 'Table',
          icon: Icons.table_chart_outlined,
          accentColor: colors.accentGreen,
          isSelected: true,
          onClose: () {},
        ),
        const SizedBox(height: 24),
        const SectionTitle('Unselected panel — chrome dimmed'),
        const SizedBox(height: 8),
        _MockPanel(
          title: 'Chart',
          icon: Icons.bar_chart,
          accentColor: colors.accentBlue,
          isSelected: false,
          onClose: () {},
        ),
        const SizedBox(height: 24),
        const SectionTitle('Locked panel'),
        const SizedBox(height: 8),
        _MockPanel(
          title: 'Board notes',
          icon: Icons.note_outlined,
          accentColor: colors.accentOrange,
          isSelected: true,
          initialLocked: true,
          onClose: () {},
        ),
        const SizedBox(height: 24),
        const SectionTitle('Content toolbar — primary + hover overflow'),
        const SizedBox(height: 8),
        PanelContentToolbar(
          children: [
            ToolbarButton(
              icon: Icons.add,
              label: 'Row',
              onPressed: () {},
            ),
            ToolbarButton(
              icon: Icons.remove,
              label: 'Row',
              onPressed: () {},
            ),
            ToolbarButton(
              icon: Icons.view_column,
              label: 'Col',
              onPressed: () {},
            ),
            const HoverOverflowMenu(
              items: [
                HoverOverflowItem(icon: Icons.delete_outline, label: 'Remove col'),
                HoverOverflowItem(icon: Icons.clear_all, label: 'Clear rows'),
                HoverOverflowItem(icon: Icons.file_download, label: 'Export'),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionTitle('Panel ID chip — editable / copyable'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PanelIdChip(id: 'sales-data', onEdit: () {}, onCopy: () {}),
            PanelIdChip(id: 'panel-abc123', onEdit: () {}, onCopy: () {}),
          ],
        ),
        const SizedBox(height: 24),
        const SectionTitle('Selected panel — voice input badge'),
        const SizedBox(height: 8),
        const _MockPanelWithVoiceBadge(),
      ],
    );
  }
}

class _MockPanel extends StatefulWidget {
  const _MockPanel({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.isSelected,
    required this.onClose,
    this.initialLocked = false,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final bool isSelected;
  final VoidCallback onClose;
  final bool initialLocked;

  @override
  State<_MockPanel> createState() => _MockPanelState();
}

class _MockPanelState extends State<_MockPanel> {
  late bool _locked;

  @override
  void initState() {
    super.initState();
    _locked = widget.initialLocked;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.isSelected ? colors.primary : colors.border,
        ),
        boxShadow: widget.isSelected
            ? [
                BoxShadow(
                  color: colors.textMuted.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? colors.surfaceElevated
                    : colors.surface,
                border: Border(
                  bottom: BorderSide(color: colors.border),
                ),
              ),
              child: Row(
                children: [
                  HeaderIconButton(
                    icon: Icons.drag_indicator,
                    tooltip: 'Drag',
                    onPressed: () {},
                  ),
                  const SizedBox(width: 8),
                  Icon(widget.icon, size: 16, color: widget.accentColor),
                  const SizedBox(width: 8),
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  HeaderIconButton(
                    icon: Icons.copy,
                    tooltip: 'Duplicate',
                    onPressed: () {},
                  ),
                  HeaderIconButton(
                    icon: Icons.format_color_fill,
                    tooltip: 'Color',
                    onPressed: () {},
                    swatch: widget.accentColor,
                  ),
                  HoverOverflowMenu(
                    items: [
                      HoverOverflowItem(
                        icon: _locked ? Icons.lock : Icons.lock_open,
                        label: _locked ? 'Unlock' : 'Lock',
                        onTap: () => setState(() => _locked = !_locked),
                      ),
                      HoverOverflowItem(
                        icon: Icons.flip_to_front,
                        label: 'Bring to front',
                        onTap: () {},
                      ),
                      HoverOverflowItem(
                        icon: Icons.flip_to_back,
                        label: 'Send to back',
                        onTap: () {},
                      ),
                      HoverOverflowItem(
                        icon: Icons.open_in_full,
                        label: 'Fullscreen',
                        onTap: () {},
                      ),
                      HoverOverflowItem(
                        icon: Icons.settings,
                        label: 'Settings',
                        onTap: () {},
                      ),
                      HoverOverflowItem(
                        icon: Icons.delete_outline,
                        label: 'Delete',
                        onTap: () {},
                      ),
                    ],
                  ),
                  HeaderIconButton(
                    icon: Icons.close,
                    tooltip: 'Close',
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            Container(
              height: 120,
              color: colors.surface,
              child: Center(
                child: Text(
                  'Panel body placeholder',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class _MockPanelWithVoiceBadge extends StatefulWidget {
  const _MockPanelWithVoiceBadge();

  @override
  State<_MockPanelWithVoiceBadge> createState() =>
      _MockPanelWithVoiceBadgeState();
}

class _MockPanelWithVoiceBadgeState extends State<_MockPanelWithVoiceBadge> {
  bool _listening = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _MockPanel(
          title: 'Terminal agent',
          icon: Icons.terminal,
          accentColor: colors.accentBlue,
          isSelected: true,
          onClose: () {},
        ),
        Positioned(
          left: -18,
          bottom: -18,
          child: _VoiceInputBadge(
            isListening: _listening,
            onTap: () => setState(() => _listening = !_listening),
          ),
        ),
        if (_listening)
          const Positioned(
            left: 44,
            bottom: 44,
            child: _VoiceListeningBubble(),
          ),
      ],
    );
  }
}

class _VoiceInputBadge extends StatelessWidget {
  const _VoiceInputBadge({required this.isListening, required this.onTap});

  final bool isListening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tooltip(
          message:
              isListening
                  ? 'Tap to stop listening'
                  : 'Voice input for this panel',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colors.textMuted.withValues(alpha: 0.25),
                  blurRadius: 10,
                  spreadRadius: -2,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: SvgPicture.asset(
              'assets/images/yolo_voice_badge.svg',
              width: 36,
              height: 36,
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceListeningBubble extends StatelessWidget {
  const _VoiceListeningBubble();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.textMuted.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WaveformBars(color: colors.primary),
          const SizedBox(height: 6),
          Text(
            'Listening...',
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _WaveformBars extends StatelessWidget {
  const _WaveformBars({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    const heights = <double>[8, 16, 10, 18, 12];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final height in heights)
          Container(
            width: 4,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}
