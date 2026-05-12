import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/plugins/builtin/filetree_plugin.dart';

void main() {
  const plugin = FileTreePlugin();

  test('typeId is board.filetree', () {
    expect(plugin.typeId, 'board.filetree');
    expect(FileTreePlugin.kTypeId, 'board.filetree');
  });

  test('displayName is File Tree', () {
    expect(plugin.displayName, 'File Tree');
  });

  test('icon is account_tree_outlined', () {
    expect(plugin.icon, Icons.account_tree_outlined);
  });

  test('accentColor is set', () {
    expect(plugin.accentColor, const Color(0xFF64748B));
  });

  test('defaultSize is 320x500', () {
    expect(plugin.defaultSize, const Size(320, 500));
  });

  test('initialState has expected keys', () {
    final state = plugin.initialState;
    expect(state.containsKey('rootPath'), isTrue);
    expect(state.containsKey('expandedDirs'), isTrue);
    expect(state.containsKey('selectedFile'), isTrue);
    expect(state['rootPath'], '');
    expect(state['expandedDirs'], <String>[]);
    expect(state['selectedFile'], '');
  });
}
