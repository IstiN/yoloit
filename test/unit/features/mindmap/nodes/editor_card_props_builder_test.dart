import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/editor_card_props_builder.dart';

/// Mimics the FileEditorCubit state shape read via dynamic access.
class _FakeEditorState {
  _FakeEditorState({required this.tabs, this.activeIndex});

  final List<dynamic> tabs;
  final dynamic activeIndex;
}

/// Mimics a tab object exposing filePath/content getters (non-Map tab).
class _FakeTab {
  _FakeTab({this.filePath, this.content});

  final String? filePath;
  final String? content;
}

const _data = EditorNodeData(
  id: 'node-1',
  filePath: '/repo/main.dart',
  content: 'node content',
  language: 'dart',
);

void main() {
  group('buildEditorCardProps', () {
    test('falls back to node data when there is no editor state', () {
      final props = buildEditorCardProps(data: _data, editorState: null);
      expect(props.filePath, '/repo/main.dart');
      expect(props.content, 'node content');
      expect(props.language, 'dart');
      expect(props.tabs, isEmpty);
    });

    test('reads the active tab content from map tabs', () {
      final state = _FakeEditorState(
        activeIndex: 1,
        tabs: <dynamic>[
          <String, dynamic>{'filePath': '/repo/a.dart', 'content': 'aaa'},
          <String, dynamic>{'filePath': '/repo/b.dart', 'content': 'bbb'},
        ],
      );

      final props = buildEditorCardProps(data: _data, editorState: state);

      expect(props.filePath, '/repo/b.dart');
      expect(props.content, 'bbb');
      expect(props.tabs, hasLength(2));
      expect(props.tabs[0].path, '/repo/a.dart');
      expect(props.tabs[0].isActive, isFalse);
      expect(props.tabs[1].isActive, isTrue);
    });

    test('clamps an out-of-range active index to the last tab', () {
      final state = _FakeEditorState(
        activeIndex: 99,
        tabs: <dynamic>[
          <String, dynamic>{'filePath': '/repo/a.dart', 'content': 'aaa'},
          <String, dynamic>{'filePath': '/repo/b.dart', 'content': 'bbb'},
        ],
      );

      final props = buildEditorCardProps(data: _data, editorState: state);

      expect(props.filePath, '/repo/b.dart');
      expect(props.tabs[1].isActive, isTrue);
    });

    test('clamps a negative active index to the first tab', () {
      final state = _FakeEditorState(
        activeIndex: -3,
        tabs: <dynamic>[
          <String, dynamic>{'filePath': '/repo/a.dart', 'content': 'aaa'},
          <String, dynamic>{'filePath': '/repo/b.dart', 'content': 'bbb'},
        ],
      );

      final props = buildEditorCardProps(data: _data, editorState: state);

      expect(props.filePath, '/repo/a.dart');
      expect(props.tabs[0].isActive, isTrue);
    });

    test('uses tab zero when the active index is not an int', () {
      final state = _FakeEditorState(
        activeIndex: 'oops',
        tabs: <dynamic>[
          <String, dynamic>{'filePath': '/repo/a.dart', 'content': 'aaa'},
          <String, dynamic>{'filePath': '/repo/b.dart', 'content': 'bbb'},
        ],
      );

      final props = buildEditorCardProps(data: _data, editorState: state);

      expect(props.filePath, '/repo/a.dart');
      expect(props.tabs[0].isActive, isTrue);
    });

    test('reads filePath/content from object tabs', () {
      final state = _FakeEditorState(
        activeIndex: 0,
        tabs: <dynamic>[
          _FakeTab(filePath: '/repo/obj.dart', content: 'obj content'),
        ],
      );

      final props = buildEditorCardProps(data: _data, editorState: state);

      expect(props.filePath, '/repo/obj.dart');
      expect(props.content, 'obj content');
    });

    test('falls back to node filePath when the active tab path is empty', () {
      final state = _FakeEditorState(
        activeIndex: 0,
        tabs: <dynamic>[
          <String, dynamic>{'filePath': '', 'content': 'draft'},
        ],
      );

      final props = buildEditorCardProps(data: _data, editorState: state);

      expect(props.filePath, '/repo/main.dart');
      expect(props.content, 'draft');
    });

    test('treats a state whose tabs getter throws as having no tabs', () {
      final props = buildEditorCardProps(
        data: _data,
        editorState: _ThrowingEditorState(),
      );
      expect(props.filePath, '/repo/main.dart');
      expect(props.content, 'node content');
      expect(props.tabs, isEmpty);
    });
  });
}

class _ThrowingEditorState {
  List<dynamic> get tabs => throw StateError('no tabs');
  int get activeIndex => throw StateError('no index');
}
