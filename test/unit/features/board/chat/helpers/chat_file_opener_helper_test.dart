import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/helpers/chat_file_opener_helper.dart';

void main() {
  group('ChatFileOpener.open', () {
    test('returns immediately for an empty path', () async {
      var called = false;
      await ChatFileOpener.open(
        '',
        createPreviewPanel: (typeId, state, title) async {
          called = true;
          return null;
        },
      );
      expect(called, isFalse);
    });

    test('routes previewable media to the board preview panel', () async {
      String? capturedType;
      Map<String, dynamic>? capturedState;
      String? capturedTitle;
      await ChatFileOpener.open(
        '/tmp/shots/photo.PNG',
        createPreviewPanel: (typeId, state, title) async {
          capturedType = typeId;
          capturedState = state;
          capturedTitle = title;
          return 'panel-1';
        },
      );
      expect(capturedType, 'board.file.preview');
      expect(capturedState, <String, dynamic>{
        'path': '/tmp/shots/photo.PNG',
        'title': 'photo.PNG',
      });
      expect(capturedTitle, 'photo.PNG');
    });

    test('falls back to system open for non-previewable files', () async {
      var called = false;
      // A nonexistent path keeps the `open` fallback side-effect free: the
      // process exits non-zero without launching any UI.
      await ChatFileOpener.open(
        '/nonexistent-yoloit-dir/nope.txt',
        createPreviewPanel: (typeId, state, title) async {
          called = true;
          return null;
        },
      );
      expect(called, isFalse);
    });

    test('falls back to system open when no preview callback is given',
        () async {
      // Completes without throwing even though the file does not exist.
      await ChatFileOpener.open('/nonexistent-yoloit-dir/photo.png');
    });
  });
}
