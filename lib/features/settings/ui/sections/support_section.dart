import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/web_cache_clearer.dart';
import 'package:yoloit/core/services/app_logger.dart';
import 'package:yoloit/core/services/support_log_service.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/ui/components/cards/settings_card.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

class SupportSection extends StatefulWidget {
  const SupportSection({super.key});

  @override
  State<SupportSection> createState() => SupportSectionState();
}

class SupportSectionState extends State<SupportSection> {
  bool _copying = false;
  String? _logPath;

  @override
  void initState() {
    super.initState();
    AppLogger.instance.logPath.then((path) {
      if (mounted) setState(() => _logPath = path);
    });
  }

  Future<void> _copyLogs() async {
    setState(() => _copying = true);
    try {
      final payload = await SupportLogService.instance.buildCopyPayload();
      await copyToClipboard(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Support logs copied')));
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  void _clearRecentEvents() {
    SupportLogService.instance.clearMemoryLog();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recent support events cleared')),
    );
    setState(() {});
  }

  Future<void> _clearPageCache() async {
    await clearWebPageCache();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final recent = SupportLogService.instance.memoryLog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(
          padding: const EdgeInsets.all(12),
          borderRadius: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.support_outlined, size: 18, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Diagnostics',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _copying ? null : _copyLogs,
                    icon:
                        _copying
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.copy, size: 16),
                    label: Text(_copying ? 'Copying...' : 'Copy logs'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Caption(
                'Board navigation diagnostics capture trackpad scroll, pan/zoom, canvas locks, and viewport interaction events.',
                fontSize: 12,
              ),
              const SizedBox(height: 8),
              Caption('App log: ${_logPath ?? 'loading...'}'),
              if (kIsWeb) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _clearPageCache,
                    icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                    label: const Text('Clear page cache'),
                  ),
                ),
                const SizedBox(height: 4),
                const Caption(
                  'Clears cached page resources and reloads from the latest deployed version. Board data in browser storage is preserved.',
                  fontSize: 12,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Recent support events',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _clearRecentEvents,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Clear recent'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 180, maxHeight: 320),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              recent,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
