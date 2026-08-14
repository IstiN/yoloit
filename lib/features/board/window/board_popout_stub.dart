import 'package:yoloit/features/board/model/board_models.dart';

/// Stub for test/web environments where desktop_multi_window is unavailable.
Future<void> createBoardPopoutWindow(BoardDocument board) async {
  throw UnsupportedError('Pop-out is not available in this environment');
}
