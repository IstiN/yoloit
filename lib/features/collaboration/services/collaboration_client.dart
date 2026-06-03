import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:yoloit/features/collaboration/model/sync_message.dart';
import 'package:yoloit/features/collaboration/services/collaboration_cipher.dart';

/// WebSocket client for the guest machine.
/// Sends JSON text frames and receives [SyncMessage] callbacks.
///
/// When [cipher] is set, every outgoing frame is AES-256-GCM encrypted
/// (`e:<base64>` wire format) and every incoming encrypted frame is decrypted
/// before [onMessage] is called.  Plain frames are still accepted so that
/// pairing errors produce a clear failure rather than a crash.
class CollaborationClient {
  CollaborationClient({required this.onMessage, this.cipher});

  final void Function(SyncMessage msg) onMessage;
  CollaborationCipher? cipher;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _disposed = false;

  bool get isConnected => _channel != null;

  Future<void> connect(String host, int port, {String clientId = '', String clientName = 'Remote Guest', String clientColor = '#60A5FA'}) async {
    final uri = Uri.parse('ws://$host:$port');
    _channel  = WebSocketChannel.connect(uri);
    await _channel!.ready; // throws if unreachable

    _sub = _channel!.stream.listen(
      (raw) {
        String text = raw as String;
        // Decrypt if frame is encrypted.
        if (cipher != null && text.startsWith('e:')) {
          text = cipher!.decryptWire(text) ?? '';
          if (text.isEmpty) return; // wrong key / tampered — drop silently
        }
        final msg = SyncMessage.decode(text);
        if (msg != null) onMessage(msg);
      },
      onDone: () {
        if (!_disposed) onMessage(SyncMessage.disconnected('server'));
        _channel = null;
      },
      onError: (_) => _channel = null,
      cancelOnError: true,
    );

    // Handshake with name and colour for presence display.
    final id = clientId.isNotEmpty
        ? clientId
        : 'guest_${DateTime.now().millisecondsSinceEpoch}';
    _send(SyncMessage.hello(
      clientId: id,
      clientName: clientName,
      clientColor: clientColor,
    ));
  }

  Future<void> disconnect() async {
    _disposed = true;
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }

  void sendMessage(SyncMessage msg) => _send(msg);

  void _send(SyncMessage msg) {
    try {
      final json = msg.encode();
      final wire = cipher != null ? cipher!.encryptWire(json) : json;
      _channel?.sink.add(wire);
    } catch (_) {}
  }
}
