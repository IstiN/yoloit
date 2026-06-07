import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

void main() {
  group('Workspace model', () {
    const workspace = Workspace(
      id: 'ws_1',
      name: 'my-project',
      paths: ['/Users/dev/my-project'],
      gitBranch: 'main',
      addedLines: 150,
      removedLines: 50,
    );

    test('copyWith preserves unchanged fields', () {
      final copy = workspace.copyWith(isActive: true);
      expect(copy.id, workspace.id);
      expect(copy.name, workspace.name);
      expect(copy.path, workspace.path);
      expect(copy.gitBranch, workspace.gitBranch);
      expect(copy.addedLines, workspace.addedLines);
      expect(copy.removedLines, workspace.removedLines);
      expect(copy.isActive, true);
    });

    test('copyWith changes only specified fields', () {
      final copy = workspace.copyWith(gitBranch: 'develop', addedLines: 200);
      expect(copy.gitBranch, 'develop');
      expect(copy.addedLines, 200);
      expect(copy.removedLines, workspace.removedLines);
    });

    test('toJson produces correct map', () {
      final json = workspace.toJson();
      expect(json['id'], 'ws_1');
      expect(json['name'], 'my-project');
      expect(json['paths'], ['/Users/dev/my-project']);
      expect(json['gitBranch'], 'main');
      expect(json['addedLines'], 150);
      expect(json['removedLines'], 50);
    });

    test('fromJson round-trips correctly', () {
      final json = workspace.toJson();
      final restored = Workspace.fromJson(json);
      expect(restored.id, workspace.id);
      expect(restored.name, workspace.name);
      expect(restored.path, workspace.path);
      expect(restored.gitBranch, workspace.gitBranch);
      expect(restored.addedLines, workspace.addedLines);
      expect(restored.removedLines, workspace.removedLines);
      // isActive is not serialized (session state only)
      expect(restored.isActive, false);
    });

    test('fromJson handles missing optional fields gracefully', () {
      final minimal = Workspace.fromJson({'id': 'x', 'name': 'x', 'path': '/x'});
      expect(minimal.gitBranch, isNull);
      expect(minimal.addedLines, 0);
      expect(minimal.removedLines, 0);
    });

    test('equality is based on props', () {
      const same = Workspace(
        id: 'ws_1',
        name: 'my-project',
        paths: ['/Users/dev/my-project'],
        gitBranch: 'main',
        addedLines: 150,
        removedLines: 50,
      );
      expect(workspace, same);
    });

    test('workspaces with different ids are not equal', () {
      const other = Workspace(id: 'ws_2', name: 'my-project', paths: ['/Users/dev/my-project']);
      expect(workspace, isNot(equals(other)));
    });
  });
}
