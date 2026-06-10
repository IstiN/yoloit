import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/settings/ui/debug_ui/sections/chat_message_showcase.dart';
import 'package:yoloit/features/settings/ui/debug_ui/sections/color_showcase.dart';
import 'package:yoloit/features/settings/ui/debug_ui/sections/component_showcase.dart';
import 'package:yoloit/features/settings/ui/debug_ui/sections/plectrum_debug.dart';
import 'package:yoloit/features/settings/ui/debug_ui/sections/typography_showcase.dart';
import 'package:yoloit/features/settings/ui/debug_ui/sections/voice_overlay_debug.dart';

/// Debug UI shell with a submenu of component groups.
///
/// Replaces the monolithic `_DebugUISection` (500+ lines) in settings_page.dart.
class DebugUIShell extends StatefulWidget {
  const DebugUIShell({super.key});

  @override
  State<DebugUIShell> createState() => _DebugUIShellState();
}

class _DebugUIShellState extends State<DebugUIShell> {
  int _selectedIndex = 0;

  static const _sections = [
    ('Plectrum & Shapes', PlectrumDebug()),
    ('Voice Overlay', VoiceOverlayDebug()),
    ('Typography', TypographyShowcase()),
    ('Colors', ColorShowcase()),
    ('Components', ComponentShowcase()),
    ('Chat Messages', ChatMessageShowcase()),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.hasBoundedHeight;
        final content = AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(
            key: ValueKey<int>(_selectedIndex),
            child: _sections[_selectedIndex].$2,
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sub-menu chips
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _sections.length; i++)
                    ChoiceChip(
                      label: Text(_sections[i].$1),
                      selected: _selectedIndex == i,
                      onSelected: (_) => setState(() => _selectedIndex = i),
                      selectedColor: colors.primary,
                      labelStyle: TextStyle(
                        color: _selectedIndex == i ? colors.textHighlight : colors.textSecondary,
                        fontSize: 12,
                      ),
                      backgroundColor: colors.surface,
                      side: BorderSide(
                        color: _selectedIndex == i ? colors.primary : colors.border,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Active section — Expanded only when parent gives bounded height
            if (hasBoundedHeight) Expanded(child: content) else content,
          ],
        );
      },
    );
  }
}
