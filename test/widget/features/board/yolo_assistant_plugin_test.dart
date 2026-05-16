import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/plugins/builtin/yolo_assistant_plugin.dart';

void main() {
  const plugin = YoloAssistantPlugin();

  test('typeId is board.yolo_assistant', () {
    expect(plugin.typeId, 'board.yolo_assistant');
    expect(YoloAssistantPlugin.kTypeId, 'board.yolo_assistant');
  });

  test('displayName is YoLo Assistant', () {
    expect(plugin.displayName, 'YoLo Assistant');
  });

  test('icon is smart_toy', () {
    expect(plugin.icon, Icons.auto_awesome);
  });

  test('accentColor is set', () {
    expect(plugin.accentColor, const Color(0xFF8B5CF6));
  });

  test('defaultSize is 420x560', () {
    expect(plugin.defaultSize, const Size(420, 560));
  });

  test('hasEditor is false', () {
    expect(plugin.hasEditor, isFalse);
  });

  test('initialState has expected keys', () {
    final state = plugin.initialState;
    expect(state.containsKey('messages'), isTrue);
    expect(state.containsKey('activeSkills'), isTrue);
    expect(state.containsKey('mode'), isTrue);
    expect(state.containsKey('isListening'), isTrue);
    expect(state.containsKey('isSpeaking'), isTrue);
    expect(state['messages'], <Map<String, dynamic>>[]);
    expect(state['activeSkills'], ['Terminal', 'Board Control', 'Web Search']);
    expect(state['mode'], 'text');
    expect(state['isListening'], false);
    expect(state['isSpeaking'], false);
  });
}
