import 'package:yoloit/features/collaboration/collaboration_ports.dart';
import 'package:yoloit/features/collaboration/model/sync_message.dart';
import 'package:yoloit/features/collaboration/services/collaboration_cipher.dart';

/// Web stub — the browser cannot host a WebSocket server.
class CollaborationServer {
  CollaborationServer({
    required void Function(String, SyncMessage) onClientMessage,
    this.port = kDefaultWsPort,
    this.httpPort = kDefaultHttpPort,
    this.cipher,
  });

  final int port;
  final int httpPort;
  final CollaborationCipher? cipher;
  int get clientCount => 0;
  String get webClientUrl => '';
  String get localUrl => '';
  bool get isRunning => false;
  Future<String> start() async => throw UnsupportedError(
      'Hosting is not available in browser mode.');

  Future<void> stop() async {}

  void broadcastRaw(SyncMessage msg, {String? exclude}) {}
  void sendTo(String clientId, SyncMessage msg) {}
}
