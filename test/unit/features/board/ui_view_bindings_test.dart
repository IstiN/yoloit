import 'package:flutter_test/flutter_test.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';

void main() {
  test('resolveString replaces storage placeholders', () {
    final resolved = UiViewBindings.resolveString(
      'Clicks: {{taps}} — {{message}}',
      <String, dynamic>{'taps': 3, 'message': 'Hi'},
    );
    expect(resolved, 'Clicks: 3 — Hi');
  });

  test('applyEventToStorage increments taps and stores payload', () {
    final next = UiViewBindings.applyEventToStorage(
      storage: <String, dynamic>{'taps': 2},
      actionId: 'btn1',
      payload: <String, dynamic>{'message': 'Clicked'},
    );
    expect(next['taps'], 3);
    expect(next['lastAction'], 'btn1');
    expect(next['message'], 'Clicked');
  });
}
