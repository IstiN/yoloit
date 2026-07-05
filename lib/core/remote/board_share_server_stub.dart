import 'package:yoloit/features/board/bloc/board_cubit.dart';

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

class BoardShareServer {
  BoardShareServer._();

  static final BoardShareServer instance = BoardShareServer._();

  bool get isRunning => false;

  BoardShareServerInfo? get info => null;

  Future<BoardShareServerInfo> start(
    BoardCubit cubit, {
    String host = '0.0.0.0',
    int port = 43110,
  }) async {
    throw UnsupportedError(
      'BoardShareServer is not supported on the web target.',
    );
  }

  Future<void> stop() async {
    throw UnsupportedError(
      'BoardShareServer is not supported on the web target.',
    );
  }
}
