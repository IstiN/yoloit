import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/widgets/js_widget_engine_message.dart';

void main() {
  group('JsWidgetMessage', () {
    test('tryParse returns null for unrelated strings', () {
      expect(JsWidgetMessage.tryParse('hello'), isNull);
      expect(JsWidgetMessage.tryParse('{"channel":"x"}'), isNull);
    });

    test('tryParse decodes a yoloit wire message', () {
      final message = JsWidgetMessage.tryParse(
        '__yoloit__{"channel":"__yoloit_render","payload":"{\\"type\\":\\"text\\"}"}',
      );
      expect(message, isNotNull);
      expect(message!.channel, '__yoloit_render');
      expect(message.payload, '{"type":"text"}');
    });

    test('encode produces a prefixed JSON string', () {
      final raw = JsWidgetMessage.encode(
        channel: '__yoloit_call_event',
        payload: {'actionId': 'tap', 'payload': {}},
      );
      expect(raw, startsWith('__yoloit__'));
      final message = JsWidgetMessage.tryParse(raw);
      expect(message!.channel, '__yoloit_call_event');
      expect(message.payload, {'actionId': 'tap', 'payload': {}});
    });
  });
}
