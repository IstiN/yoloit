import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/remote/board_share_server.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/ui/dialogs/share_board_dialog.dart';
import 'package:yoloit/ui/components/cards/settings_card.dart';
import 'package:yoloit/ui/components/input/labeled_text_field.dart';

/// Settings section for connecting to a remote YoLoIT server (yoloitd or
/// yoloit-hub) and for sharing this device on the LAN.
class RemoteSection extends StatefulWidget {
  const RemoteSection({super.key});

  @override
  State<RemoteSection> createState() => _RemoteSectionState();
}

class _RemoteSectionState extends State<RemoteSection> {
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _connecting = false;
  bool _shareBusy = false;
  bool _copiedUrl = false;
  bool _copiedToken = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _connect() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _snack('Enter the server URL');
      return;
    }
    final token = _tokenCtrl.text.trim();
    setState(() => _connecting = true);
    try {
      final boards = await context.read<BoardCubit>().connectRemoteBoards(
        url: url,
        token: token.isEmpty ? null : token,
      );
      _urlCtrl.clear();
      _tokenCtrl.clear();
      _snack(
        'Connected ${boards.length} board${boards.length == 1 ? '' : 's'} '
        'from $url',
      );
    } catch (error) {
      _snack('Connection failed: $error');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect(String url) async {
    await context.read<BoardCubit>().disconnectRemoteBoardsForUrl(url);
    _snack('Disconnected from $url');
  }

  Future<void> _startSharing() async {
    setState(() => _shareBusy = true);
    try {
      await BoardShareServer.instance.start(context.read<BoardCubit>());
    } catch (error) {
      _snack('Share failed: $error');
    } finally {
      if (mounted) setState(() => _shareBusy = false);
    }
  }

  Future<void> _stopSharing() async {
    setState(() => _shareBusy = true);
    await BoardShareServer.instance.stop();
    if (mounted) setState(() => _shareBusy = false);
  }

  Future<void> _copy(String text, ValueChanged<bool> setCopied) async {
    await copyToClipboard(text);
    if (!mounted) return;
    setState(() => setCopied(true));
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => setCopied(false));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildConnectCard(colors),
        const SizedBox(height: 20),
        _buildShareCard(colors),
      ],
    );
  }

  Widget _buildConnectCard(AppColorScheme colors) {
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect to a YoLoIT server',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'yoloitd, yoloit-hub or another device that shares its boards. '
            'Remote boards stay connected across restarts.',
            style: TextStyle(color: colors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          LabeledTextField(
            controller: _urlCtrl,
            label: 'Server URL',
            hint: 'http://192.168.1.10:43110',
          ),
          const SizedBox(height: 10),
          LabeledTextField(
            controller: _tokenCtrl,
            label: 'Token (optional)',
            hint: 'Shared access token',
            obscureText: true,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _connecting ? null : _connect,
            icon:
                _connecting
                    ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.link, size: 16),
            label: Text(_connecting ? 'Connecting...' : 'Connect'),
          ),
          const SizedBox(height: 16),
          _buildConnectedList(colors),
        ],
      ),
    );
  }

  Widget _buildConnectedList(AppColorScheme colors) {
    return BlocBuilder<BoardCubit, BoardState>(
      builder: (context, state) {
        final byUrl = <String, int>{};
        for (final board in state.boards) {
          final remote = remoteInfoForBoard(board);
          if (remote == null) continue;
          byUrl[remote.url] = (byUrl[remote.url] ?? 0) + 1;
        }
        if (byUrl.isEmpty) {
          return Text(
            'No remote servers connected.',
            style: TextStyle(color: colors.textMuted, fontSize: 11),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connected servers',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            for (final entry in byUrl.entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.cloud_done_outlined,
                  size: 18,
                  color: colors.accentGreen,
                ),
                title: Text(
                  entry.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                subtitle: Text(
                  '${entry.value} board${entry.value == 1 ? '' : 's'}',
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                ),
                trailing: TextButton(
                  onPressed: () => _disconnect(entry.key),
                  child: const Text('Disconnect'),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildShareCard(AppColorScheme colors) {
    final info = BoardShareServer.instance.info;
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Share this device',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            info == null
                ? 'Start a LAN server so other devices can connect to this '
                    'app with the URL and token below.'
                : 'Sharing is on. Enter this URL and token on the other '
                    'device (Settings → Remote → Connect).',
            style: TextStyle(color: colors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          if (info == null)
            FilledButton.icon(
              onPressed: _shareBusy ? null : _startSharing,
              icon:
                  _shareBusy
                      ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.ios_share_outlined, size: 16),
              label: Text(_shareBusy ? 'Starting...' : 'Start sharing'),
            )
          else ...[
            ShareValueRow(
              label: 'URL',
              value: info.url,
              copied: _copiedUrl,
              onCopy: () => _copy(info.url, (value) => _copiedUrl = value),
            ),
            const SizedBox(height: 10),
            ShareValueRow(
              label: 'Token',
              value: info.token,
              copied: _copiedToken,
              onCopy: () => _copy(info.token, (value) => _copiedToken = value),
            ),
            const SizedBox(height: 12),
            Text(
              'The app must stay open. If the other device cannot connect, '
              'allow incoming connections in the firewall.',
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _shareBusy ? null : _stopSharing,
              icon: const Icon(Icons.stop_circle_outlined, size: 16),
              label: Text(_shareBusy ? 'Stopping...' : 'Stop sharing'),
            ),
          ],
        ],
      ),
    );
  }
}
