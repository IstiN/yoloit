import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/settings/ui/sections/section_header.dart';

class PromptsSection extends StatefulWidget {
  const PromptsSection({super.key});

  @override
  State<PromptsSection> createState() => PromptsSectionState();
}

class PromptsSectionState extends State<PromptsSection> {
  late Future<Map<String, String>> _promptsFuture;

  static const _yoloChatAsset = 'assets/prompts/yolo_chat_system_prompt.md';
  static const _cliGuidanceAsset = 'assets/prompts/cli_agent_guidance.md';

  @override
  void initState() {
    super.initState();
    _promptsFuture = _loadPrompts();
  }

  Future<Map<String, String>> _loadPrompts() async {
    final chat = await rootBundle.loadString(_yoloChatAsset);
    final guidance = await rootBundle.loadString(_cliGuidanceAsset);
    final help = await CliGuidanceService.instance.fetchHelp();
    return {
      'yolochat': chat.trim(),
      'agents': guidance.trim(),
      'help': help ?? '(yoloit binary not found or help unavailable)',
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _promptsFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final prompts = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'YoloChat System Prompt'),
            const SizedBox(height: 4),
            const Text(
              'Injected as the system prompt for every YoloChat LLM session.',
              style: TextStyle(color: Color(0xFF8C8D9E), fontSize: 12),
            ),
            const SizedBox(height: 12),
            PromptCard(
              label: 'assets/prompts/yolo_chat_system_prompt.md',
              content: prompts['yolochat']!,
            ),
            const SizedBox(height: 28),
            const SectionHeader(title: 'CLI Agent Guidance'),
            const SizedBox(height: 4),
            const Text(
              'Prepended to every user message sent to Copilot, Cursor, and OpenCode agents.',
              style: TextStyle(color: Color(0xFF8C8D9E), fontSize: 12),
            ),
            const SizedBox(height: 12),
            PromptCard(
              label: 'assets/prompts/cli_agent_guidance.md',
              content: prompts['agents']!,
            ),
            const SizedBox(height: 28),
            const SectionHeader(title: 'YoLoIT CLI Help (injected)'),
            const SizedBox(height: 4),
            const Text(
              'Output of `yoloit help --format short` — appended to the first message in every agent session.',
              style: TextStyle(color: Color(0xFF8C8D9E), fontSize: 12),
            ),
            const SizedBox(height: 12),
            PromptCard(
              label: 'yoloit help --format short',
              content: prompts['help']!,
            ),
          ],
        );
      },
    );
  }
}

class PromptCard extends StatelessWidget {
  const PromptCard({required this.label, required this.content});

  final String label;
  final String content;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar with filename + copy button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.40),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 15),
                  tooltip: 'Copy to clipboard',
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(4),
                    minimumSize: const Size(28, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    copyToClipboard(content);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: colors.border.withValues(alpha: 0.25),
          ),
          // Scrollable content
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                content,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 12.5,
                  fontFamily: 'monospace',
                  height: 1.55,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
