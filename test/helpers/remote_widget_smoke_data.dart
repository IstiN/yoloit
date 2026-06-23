import 'package:yoloit/core/remote/yoloitd_panel_catalog.dart';

Map<String, dynamic> remoteWidgetSmokeBoardJson({
  String id = 'remote-widget-smoke',
  String name = 'Remote Widget Smoke',
}) {
  return {
    'id': id,
    'name': name,
    'viewport': {
      'scale': 1.0,
      'translation': {'dx': 0, 'dy': 0},
    },
    'panels': [
      for (var i = 0; i < yoloitdPanelTypes.length; i++)
        _panelJson(i, yoloitdPanelTypes[i]),
    ],
    'links': <Map<String, Object?>>[],
    'drawings': <Map<String, Object?>>[],
    'metadata': {'historyRevision': 1},
  };
}

Map<String, Object?> _panelJson(int index, Map<String, dynamic> descriptor) {
  final type = descriptor['type'] as String;
  final size = descriptor['defaultSize'] as Map<String, dynamic>;
  return {
    'id': 'remote-widget-$index',
    'type': type,
    'title': 'Remote $type',
    'bounds': {
      'x': 80 + (index % 4) * 360,
      'y': 80 + (index ~/ 4) * 280,
      'width': size['width'],
      'height': size['height'],
    },
    'params': <String, Object?>{},
    'state': remoteWidgetSmokeState(type),
    'zIndex': index,
    'hidden': false,
    'locked': false,
    'pinned': false,
  };
}

Map<String, Object?> remoteWidgetSmokeState(String type) {
  return switch (type) {
    'board.note.markdown' => {
      'markdown': '## Remote markdown\nDocker smoke',
      'autoHeight': false,
      'autoScroll': false,
    },
    'board.sticky' => {
      'text': 'Remote sticky',
      'color': '#FEF08A',
      'textColor': '#1F2937',
      'fontSize': 18,
    },
    'board.shape' => {
      'shape': 'diamond',
      'text': 'Remote shape',
      'fillColor': '#00000000',
      'strokeColor': '#93C5FD',
      'textColor': '#E2E8F0',
      'strokeWidth': 3,
      'fontSize': 18,
      'textHAlign': 'center',
      'textVAlign': 'center',
      'textOrientation': 'horizontal',
    },
    'board.kanban' => {
      'columns': ['Todo', 'Done'],
      'cards': [
        {'id': 'card-1', 'title': 'Remote card', 'column': 'Todo'},
      ],
    },
    'board.webpage' => {
      'url': 'https://example.com',
      'title': 'Example',
      'favicon': '',
    },
    'board.code.snippet' => {'code': 'void main() {}', 'language': 'dart'},
    'board.checklist' => {
      'title': 'Remote checklist',
      'items': [
        {'id': 'item-1', 'text': 'Round trip state', 'done': true},
      ],
    },
    'board.files' => {
      'files': [
        {'id': 'file-1', 'path': '/data/README.md', 'name': 'README.md'},
      ],
    },
    'board.file.preview' => {'path': '/data/README.md', 'title': 'README.md'},
    'board.playlist' => {
      'tracks': <Map<String, Object?>>[],
      'currentIndex': 0,
      'repeat': false,
      'shuffle': false,
    },
    'board.run' => {'group': 'default', 'activeSessionId': null},
    'board.run_configs' => {'group': 'default'},
    'board.setup_guide' => {
      'selectedPackageIds': ['git', 'tmux', 'codex'],
    },
    'board.chat' => {
      'configured': false,
      'config': {'sessionName': '', 'workingDir': ''},
    },
    'board.terminal' => {
      'config': {'sessionId': '', 'sessionName': '', 'workingDir': ''},
    },
    'board.filetree' => {
      'rootPath': '/data',
      'expandedDirs': <String>[],
      'selectedFile': '',
    },
    'board.diff.preview' => {'filePath': '', 'rootPath': '', 'title': 'Diff'},
    'board.yolo_assistant' => {
      'messages': <Map<String, Object?>>[],
      'activeSkills': ['Terminal', 'Board Control', 'Web Search'],
      'mode': 'text',
      'isListening': false,
      'isSpeaking': false,
    },
    'board.widget.custom' => {
      'widgetId': 'yolo-hello',
      'config': <String, Object?>{},
    },
    'board.timer' => {
      'duration': 300,
      'remaining': 300,
      'isRunning': false,
      'isPaused': false,
      'completed': false,
      'label': 'Remote timer',
      'lastTick': 0,
    },
    'board.table' => {
      'columns': [
        {'id': 'month', 'title': 'Month', 'type': 'text'},
        {'id': 'sales', 'title': 'Sales', 'type': 'number'},
      ],
      'rows': [
        {'id': 'r-1', 'month': 'Jan', 'sales': 120},
        {'id': 'r-2', 'month': 'Feb', 'sales': 190},
      ],
    },
    'board.calendar' => {
      'view': 'month',
      'events': <Map<String, Object?>>[],
      'eventCount': 0,
    },
    'board.chart' => {
      'type': 'line',
      'data': [
        {'month': 'Jan', 'sales': 120},
        {'month': 'Feb', 'sales': 190},
      ],
      'xKey': 'month',
      'yKey': 'sales',
      'animated': true,
    },
    _ => <String, Object?>{},
  };
}

List<Map<String, Object?>> remoteWidgetSmokeActions(String type) {
  return switch (type) {
    'board.note.markdown' => [
      {'action': 'set', 'markdown': '## Updated remote markdown'},
      {'action': 'append', 'text': 'Appended over remote'},
      {'action': 'wrap'},
    ],
    'board.sticky' => [
      {'action': 'set', 'text': 'Updated sticky', 'fontSize': 22},
      {'action': 'append', 'text': 'Second line'},
      {'action': 'color', 'color': '#F472B6', 'textColor': '#111827'},
    ],
    'board.shape' => [
      {
        'action': 'set',
        'shape': 'triangle',
        'text': 'Remote triangle',
        'strokeWidth': 7,
        'textHAlign': 'right',
      },
    ],
    'board.kanban' => [
      {'action': 'add-column', 'name': 'Review'},
      {
        'action': 'add-card',
        'id': 'remote-card-1',
        'column': 'Review',
        'title': 'Remote card',
      },
      {'action': 'move-card', 'cardId': 'remote-card-1', 'to': 'Done'},
      {
        'action': 'update-card',
        'cardId': 'remote-card-1',
        'description': 'Done remotely',
      },
    ],
    'board.webpage' => [
      {'action': 'open', 'url': 'https://example.org', 'title': 'Example Org'},
    ],
    'board.code.snippet' => [
      {'action': 'set', 'code': 'print("remote")', 'language': 'python'},
    ],
    'board.checklist' => [
      {'action': 'add', 'id': 'remote-item-2', 'text': 'Remote item'},
      {'action': 'check', 'id': 'remote-item-2'},
      {
        'action': 'rename',
        'id': 'remote-item-2',
        'text': 'Remote item renamed',
      },
    ],
    'board.files' => [
      {'action': 'open', 'path': '/data'},
      {
        'action': 'add',
        'id': 'remote-file-2',
        'path': '/data/TODO.md',
        'name': 'TODO.md',
      },
    ],
    'board.file.preview' => [
      {'action': 'open', 'path': '/data/TODO.md', 'title': 'TODO.md'},
    ],
    'board.playlist' => [
      {'action': 'add', 'path': '/music/remote.mp3', 'title': 'Remote track'},
      {'action': 'play', 'index': 0},
      {'action': 'pause'},
    ],
    'board.run' || 'board.run_configs' => [
      {'action': 'set-group', 'group': 'remote'},
      {'action': 'select-session', 'sessionId': 'session-remote'},
    ],
    'board.setup_guide' => [
      {'action': 'select', 'packageId': 'node'},
      {'action': 'unselect', 'packageId': 'tmux'},
    ],
    'board.chat' => [
      {'action': 'config', 'provider': 'codex', 'model': 'gpt-5.4'},
      {'action': 'send', 'text': 'remote hello'},
    ],
    'board.terminal' => [
      {'action': 'set-dir', 'dir': '/workspace'},
      {'action': 'set-session', 'sessionId': 'remote-terminal'},
    ],
    'board.filetree' => [
      {'action': 'set-root', 'path': '/workspace'},
      {'action': 'expand', 'dir': '/workspace/lib'},
      {'action': 'open', 'path': '/workspace/lib/main.dart'},
    ],
    'board.diff.preview' => [
      {'action': 'set-root', 'rootPath': '/workspace'},
      {
        'action': 'open',
        'filePath': '/workspace/lib/main.dart',
        'title': 'main.dart',
      },
    ],
    'board.yolo_assistant' => [
      {'action': 'set-mode', 'mode': 'voice'},
      {'action': 'set-status', 'status': 'ready'},
    ],
    'board.widget.custom' => [
      {'action': 'set-widget', 'widgetId': 'remote-widget'},
      {
        'action': 'set-config',
        'config': {'theme': 'remote'},
      },
    ],
    'board.timer' => [
      {'action': 'set', 'duration': 900, 'label': 'Remote timer'},
      {'action': 'start'},
      {'action': 'pause'},
    ],
    'board.table' => [
      {
        'action': 'add-column',
        'id': 'region',
        'title': 'Region',
        'type': 'text',
      },
      {'action': 'add-row', 'cells': {'month': 'Mar', 'sales': 210}},
      {
        'action': 'update-row',
        'rowId': 'r-1',
        'cells': {'month': 'January', 'sales': 121},
      },
      {'action': 'remove-row', 'rowId': 'r-2'},
    ],
    'board.calendar' => [
      {
        'action': 'create-event',
        'title': 'Remote standup',
        'start': '2026-06-19T10:00:00.000Z',
        'allDay': false,
      },
      {'action': 'set-view', 'view': 'week'},
    ],
    'board.chart' => [
      {
        'action': 'set-data',
        'data': [
          {'month': 'Mar', 'sales': 210},
          {'month': 'Apr', 'sales': 240},
        ],
      },
      {'action': 'set-type', 'type': 'bar'},
    ],
    _ => [
      {'action': 'set', 'remoteSmoke': true},
    ],
  };
}
