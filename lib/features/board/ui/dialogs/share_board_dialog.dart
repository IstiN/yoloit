import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yoloit/core/remote/board_share_server.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

/// Dialog that shows the current board-sharing URL and token.
class ShareBoardDialog extends StatefulWidget {
  const ShareBoardDialog({super.key, required this.info});

  final BoardShareServerInfo info;

  @override
  State<ShareBoardDialog> createState() => _ShareBoardDialogState();
}

class _ShareBoardDialogState extends State<ShareBoardDialog> {
  bool _copiedUrl = false;
  bool _copiedToken = false;
  bool _stopping = false;

  Future<void> _copy(String text, ValueChanged<bool> setCopied) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => setCopied(true));
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => setCopied(false));
  }

  Future<void> _stopSharing() async {
    setState(() => _stopping = true);
    await BoardShareServer.instance.stop();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialogScaffold(
      title: 'Share board',
      icon: const Icon(Icons.ios_share_outlined),
      maxWidth: 520,
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Caption(
              'Use Connect remote YoLoIT on another device and paste this URL and token.',
              fontSize: 12,
            ),
            const SizedBox(height: 16),
            _ShareValueRow(
              label: 'URL',
              value: widget.info.url,
              copied: _copiedUrl,
              onCopy: () => _copy(widget.info.url, (value) => _copiedUrl = value),
            ),
            const SizedBox(height: 10),
            _ShareValueRow(
              label: 'Token',
              value: widget.info.token,
              copied: _copiedToken,
              onCopy: () => _copy(
                widget.info.token,
                (value) => _copiedToken = value,
              ),
            ),
            const SizedBox(height: 12),
            const Caption(
              'The app must stay open. If the other Mac cannot connect, allow incoming connections in macOS Firewall.',
              fontSize: 12,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _stopping ? null : _stopSharing,
          child: Text(_stopping ? 'Stopping...' : 'Stop sharing'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _ShareValueRow extends StatelessWidget {
  const _ShareValueRow({
    required this.label,
    required this.value,
    required this.copied,
    required this.onCopy,
  });

  final String label;
  final String value;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  value,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: copied ? 'Copied' : 'Copy $label',
              onPressed: onCopy,
              icon: Icon(copied ? Icons.check : Icons.copy, size: 18),
            ),
          ],
        ),
      ],
    );
  }
}
