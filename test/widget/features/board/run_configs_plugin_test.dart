import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/plugins/builtin/run_configs_plugin.dart';

void main() {
  const plugin = RunConfigsPlugin();

  test('typeId is board.run_configs', () {
    expect(plugin.typeId, 'board.run_configs');
    expect(RunConfigsPlugin.kTypeId, 'board.run_configs');
  });

  test('displayName is Run Configs', () {
    expect(plugin.displayName, 'Run Configs');
  });

  test('icon is play_circle_outline', () {
    expect(plugin.icon, Icons.play_circle_outline);
  });

  test('accentColor is set', () {
    expect(plugin.accentColor, const Color(0xFF22C55E));
  });

  test('defaultSize is 600x400', () {
    expect(plugin.defaultSize, const Size(600, 400));
  });

  test('initialState is empty (state managed by RunBridge)', () {
    final state = plugin.initialState;
    expect(state, isEmpty);
  });
}
