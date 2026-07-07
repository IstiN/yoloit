import 'package:yoloit/core/remote/board_share_server_base.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';

class BoardShareServer extends BoardShareServerBase {
  BoardShareServer._();

  static final BoardShareServer instance = BoardShareServer._();

  @override
  bool get isRunning => false;

  @override
  BoardShareServerInfo? get info => null;

  @override
  Future<BoardShareServerInfo> start(
    BoardCubit cubit, {
    String host = '0.0.0.0',
    int port = 43110,
  }) async {
    throw UnsupportedError(
      'BoardShareServer is not supported on the web target.',
    );
  }

  @override
  Future<void> stop() async {
    throw UnsupportedError(
      'BoardShareServer is not supported on the web target.',
    );
  }
}
