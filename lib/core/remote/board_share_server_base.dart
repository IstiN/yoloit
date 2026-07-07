import 'package:yoloit/features/board/bloc/board_cubit.dart';

/// Connection details advertised by a running board-share server.
class BoardShareServerInfo {
  const BoardShareServerInfo({
    required this.url,
    required this.token,
    required this.host,
    required this.port,
  });

  final String url;
  final String token;
  final String host;
  final int port;
}

/// Shared contract for the board-share server on VM and web stub.
///
/// Concrete implementations are provided by conditional exports.
abstract class BoardShareServerBase {
  bool get isRunning;
  BoardShareServerInfo? get info;

  Future<BoardShareServerInfo> start(
    BoardCubit cubit, {
    String host = '0.0.0.0',
    int port = 43110,
  });

  Future<void> stop();
}
