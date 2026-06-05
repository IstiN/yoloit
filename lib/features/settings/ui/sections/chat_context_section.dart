import 'package:flutter/material.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/settings/ui/sections/toggle_row.dart';

class ChatContextSection extends StatefulWidget {
  const ChatContextSection({super.key});

  @override
  State<ChatContextSection> createState() => ChatContextSectionState();
}

class ChatContextSectionState extends State<ChatContextSection> {
  bool _injectCliHelp = true;
  bool _boardSnapshot = false;

  @override
  void initState() {
    super.initState();
    SessionPrefs.isInjectCliHelpEnabled().then((v) {
      if (mounted) setState(() => _injectCliHelp = v);
    });
    SessionPrefs.isBoardSnapshotEnabled().then((v) {
      if (mounted) setState(() => _boardSnapshot = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          ToggleRow(
            icon: Icons.integration_instructions_outlined,
            title: 'Inject CLI help on first message',
            subtitle:
                'Prepends yoloit command reference to the first Copilot message',
            value: _injectCliHelp,
            onChanged: (v) async {
              await SessionPrefs.saveInjectCliHelpEnabled(v);
              CliGuidanceService.instance.clearCache();
              if (mounted) setState(() => _injectCliHelp = v);
            },
          ),
          Divider(height: 1, color: colors.border),
          ToggleRow(
            icon: Icons.screenshot_monitor_outlined,
            title: 'Attach board snapshot',
            subtitle:
                'Sends a compressed screenshot of the current board view with each message',
            value: _boardSnapshot,
            onChanged: (v) async {
              await SessionPrefs.saveBoardSnapshotEnabled(v);
              if (mounted) setState(() => _boardSnapshot = v);
            },
          ),
        ],
      ),
    );
  }
}
