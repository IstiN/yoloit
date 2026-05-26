import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_session_naming.dart';

void main() {
  test('keeps preferred name when it is unused', () {
    expect(
      makeUniqueChatSessionName('say hello', const ['other session']),
      'say hello',
    );
  });

  test('appends numeric suffix when preferred name is taken', () {
    expect(
      makeUniqueChatSessionName('say hello', const [
        'say hello',
        'say hello 2',
        'another',
      ]),
      'say hello 3',
    );
  });

  test('compares existing names case-insensitively', () {
    expect(
      makeUniqueChatSessionName('Say Hello', const ['say hello']),
      'Say Hello 2',
    );
  });
}
