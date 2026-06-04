import 'package:flutter/material.dart';

import 'package:yoloit/core/ui/adaptive_dialog.dart';

/// Result data returned from [ConnectRemoteYoloitDialog].
class RemoteYoloitConnection {
  const RemoteYoloitConnection({required this.url, this.token});

  final String url;
  final String? token;
}

/// Dialog that prompts the user for a remote YoLoIT server URL and token.
class ConnectRemoteYoloitDialog extends StatefulWidget {
  const ConnectRemoteYoloitDialog({super.key});

  @override
  State<ConnectRemoteYoloitDialog> createState() =>
      _ConnectRemoteYoloitDialogState();
}

class _ConnectRemoteYoloitDialogState
    extends State<ConnectRemoteYoloitDialog> {
  final _url = TextEditingController(text: 'http://127.0.0.1:43110');
  final _token = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    Navigator.of(context).pop(
      RemoteYoloitConnection(
        url: url,
        token: _token.text.trim().isEmpty ? null : _token.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialogScaffold(
      title: 'Connect remote YoLoIT',
      icon: const Icon(Icons.cloud_outlined),
      maxWidth: 420,
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _url,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Remote URL',
                hintText: 'http://host:43110',
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _token,
              decoration: const InputDecoration(
                labelText: 'Token',
                hintText: 'Optional bearer token',
              ),
              obscureText: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.cloud_outlined),
          label: const Text('Connect'),
        ),
      ],
    );
  }
}
