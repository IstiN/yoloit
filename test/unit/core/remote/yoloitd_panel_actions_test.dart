import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_models.dart';
import 'package:yoloit/core/remote/yoloitd_panel_actions.dart';

RemotePanel _tablePanel() => const RemotePanel(
  id: 'p-table',
  type: 'board.table',
  title: 'Table',
  bounds: RemotePanelBounds(
    x: 0,
    y: 0,
    width: 520,
    height: 360,
  ),
  state: {
    'columns': [
      {'id': 'month', 'title': 'Month', 'type': 'text'},
      {'id': 'sales', 'title': 'Sales', 'type': 'number'},
    ],
    'rows': [
      {'id': 'r-1', 'month': 'Jan', 'sales': 120},
    ],
  },
);

RemotePanel _panel(String type, Map<String, dynamic> state) => RemotePanel(
  id: 'p-${type.replaceAll('.', '-')}',
  type: type,
  title: type,
  bounds: const RemotePanelBounds(x: 0, y: 0, width: 320, height: 240),
  state: state,
);

void main() {
  group('board.table actions', () {
    test('add-row puts cells keyed by column id', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'add-row',
        {'cells': {'month': 'Feb', 'sales': 200}},
      );
      expect(result.ok, isTrue);
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      expect(rows, hasLength(2));
      final added = rows.last as Map<String, dynamic>;
      expect(added['month'], 'Feb');
      expect(added['sales'], 200);
    });

    test('add-row maps column titles to ids', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'add-row',
        {
          'cells': {'Month': 'Feb', 'Sales': 200},
        },
      );
      expect(result.ok, isTrue);
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      expect(rows, hasLength(2));
      final added = rows.last as Map<String, dynamic>;
      expect(added['month'], 'Feb');
      expect(added['sales'], 200);
    });

    test('add-row defaults missing cells to type defaults', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'add-row',
        <String, dynamic>{},
      );
      expect(result.ok, isTrue);
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      final added = rows.last as Map<String, dynamic>;
      expect(added['month'], '');
      expect(added['sales'], 0);
    });

    test('update-row maps column titles to ids', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'update-row',
        {
          'rowId': 'r-1',
          'cells': {'Month': 'Apr', 'Sales': 999},
        },
      );
      expect(result.ok, isTrue);
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      final updated = rows.single as Map<String, dynamic>;
      expect(updated['month'], 'Apr');
      expect(updated['sales'], 999);
    });

    test('update-row changes only provided cells', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'update-row',
        {'rowId': 'r-1', 'cells': {'sales': 999}},
      );
      expect(result.ok, isTrue);
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      final updated = rows.single as Map<String, dynamic>;
      expect(updated['month'], 'Jan');
      expect(updated['sales'], 999);
    });

    test('remove-row deletes by id', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'remove-row',
        {'rowId': 'r-1'},
      );
      expect(result.ok, isTrue);
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      expect(rows, isEmpty);
    });

    test('add-column adds default cells to existing rows', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'add-column',
        {'id': 'region', 'title': 'Region', 'type': 'text'},
      );
      expect(result.ok, isTrue);
      final columns = result.stateUpdate['columns'] as List<dynamic>;
      expect(columns, hasLength(3));
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      final row = rows.single as Map<String, dynamic>;
      expect(row.containsKey('region'), isTrue);
      expect(row['region'], '');
    });

    test('rename-column updates title', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'rename-column',
        {'id': 'month', 'title': 'Period'},
      );
      expect(result.ok, isTrue);
      final columns = (result.stateUpdate['columns'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      final month = columns.firstWhere(
        (column) => column['id'] == 'month',
      );
      expect(month['title'], 'Period');
    });

    test('remove-column removes cells from rows', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'remove-column',
        {'id': 'sales'},
      );
      expect(result.ok, isTrue);
      final columns = result.stateUpdate['columns'] as List<dynamic>;
      expect(columns, hasLength(1));
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      final row = rows.single as Map<String, dynamic>;
      expect(row.containsKey('sales'), isFalse);
    });

    test('clear removes all rows but keeps columns', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(panel, 'clear', {});
      expect(result.ok, isTrue);
      expect(result.stateUpdate['rows'], isEmpty);
      expect(result.stateUpdate.containsKey('columns'), isFalse);
    });
  });

  group('board.files actions', () {
    RemotePanel panel() => _panel('board.files', {
      'selectedPath': '/tmp/a.txt',
      'files': [
        {'id': 'f-1', 'path': '/tmp/a.txt', 'name': 'a.txt'},
      ],
    });

    test('get returns selectedPath and files', () {
      final result = handleRemotePanelAction(panel(), 'get', {});
      expect(result.ok, isTrue);
      expect(result.data['selectedPath'], '/tmp/a.txt');
      expect(result.data['files'], hasLength(1));
    });

    test('open updates selectedPath', () {
      final result = handleRemotePanelAction(
        panel(),
        'open',
        {'path': '/tmp/b.txt'},
      );
      expect(result.stateUpdate['selectedPath'], '/tmp/b.txt');
    });

    test('open without path fails', () {
      final result = handleRemotePanelAction(panel(), 'open', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('path'));
    });

    test('add appends a file with derived name', () {
      final result = handleRemotePanelAction(
        panel(),
        'add',
        {'path': '/tmp/dir/c.md'},
      );
      final files = result.stateUpdate['files'] as List<dynamic>;
      expect(files, hasLength(2));
      final added = files.last as Map<String, dynamic>;
      expect(added['path'], '/tmp/dir/c.md');
      expect(added['name'], 'c.md');
      expect(added['id'], isNotNull);
    });

    test('add without path fails', () {
      final result = handleRemotePanelAction(panel(), 'add', {});
      expect(result.ok, isFalse);
    });

    test('remove deletes by id and path', () {
      final byId = handleRemotePanelAction(panel(), 'remove', {'id': 'f-1'});
      expect(byId.stateUpdate['files'], isEmpty);
      final byPath = handleRemotePanelAction(
        panel(),
        'remove',
        {'path': '/tmp/a.txt'},
      );
      expect(byPath.stateUpdate['files'], isEmpty);
    });

    test('clear empties the file list', () {
      final result = handleRemotePanelAction(panel(), 'clear', {});
      expect(result.stateUpdate['files'], isEmpty);
    });

    test('unknown action fails', () {
      final result = handleRemotePanelAction(panel(), 'nope', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('Unknown action'));
    });
  });

  group('board.terminal actions', () {
    RemotePanel panel() =>
        _panel('board.terminal', {
          'config': {'workingDir': '/tmp', 'sessionId': 's-1'},
        });

    test('config returns the current config', () {
      final result = handleRemotePanelAction(panel(), 'config', {});
      final config = result.data['config'] as Map<String, dynamic>;
      expect(config['workingDir'], '/tmp');
      expect(config['sessionId'], 's-1');
    });

    test('set-dir updates workingDir and keeps other keys', () {
      final result = handleRemotePanelAction(
        panel(),
        'set-dir',
        {'dir': '/var'},
      );
      final config = result.stateUpdate['config'] as Map<String, dynamic>;
      expect(config['workingDir'], '/var');
      expect(config['sessionId'], 's-1');
    });

    test('set-dir without dir fails', () {
      final result = handleRemotePanelAction(panel(), 'set-dir', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('dir'));
    });

    test('set-session updates sessionId', () {
      final result = handleRemotePanelAction(
        panel(),
        'set-session',
        {'sessionId': 's-2'},
      );
      final config = result.stateUpdate['config'] as Map<String, dynamic>;
      expect(config['sessionId'], 's-2');
      expect(config['workingDir'], '/tmp');
    });

    test('set-session without sessionId fails', () {
      final result = handleRemotePanelAction(panel(), 'set-session', {});
      expect(result.ok, isFalse);
    });

    test('unknown action fails', () {
      final result = handleRemotePanelAction(panel(), 'boom', {});
      expect(result.ok, isFalse);
    });
  });

  group('board.timer actions', () {
    RemotePanel panel() => _panel('board.timer', {
      'duration': 600,
      'remaining': 120,
      'isRunning': true,
      'isPaused': false,
      'completed': false,
      'label': 'Focus',
    });

    test('status returns the timer content', () {
      final result = handleRemotePanelAction(panel(), 'status', {});
      expect(result.data['duration'], 600);
      expect(result.data['remaining'], 120);
      expect(result.data['isRunning'], isTrue);
      expect(result.data['label'], 'Focus');
    });

    test('set resets the timer to a stopped state', () {
      final result = handleRemotePanelAction(
        panel(),
        'set',
        {'duration': 60, 'label': 'Short'},
      );
      final update = result.stateUpdate;
      expect(update['duration'], 60);
      expect(update['remaining'], 60);
      expect(update['isRunning'], isFalse);
      expect(update['isPaused'], isFalse);
      expect(update['completed'], isFalse);
      expect(update['label'], 'Short');
    });

    test('set without duration keeps the current duration', () {
      final result = handleRemotePanelAction(panel(), 'set', {});
      expect(result.stateUpdate['duration'], 600);
    });

    test('start marks the timer running', () {
      final result = handleRemotePanelAction(
        panel(),
        'start',
        {'duration': 30},
      );
      final update = result.stateUpdate;
      expect(update['isRunning'], isTrue);
      expect(update['remaining'], 30);
      expect(update['lastTick'], isA<int>());
    });

    test('pause and resume toggle running state', () {
      final paused = handleRemotePanelAction(panel(), 'pause', {});
      expect(paused.stateUpdate['isRunning'], isFalse);
      expect(paused.stateUpdate['isPaused'], isTrue);
      final resumed = handleRemotePanelAction(panel(), 'resume', {});
      expect(resumed.stateUpdate['isRunning'], isTrue);
      expect(resumed.stateUpdate['isPaused'], isFalse);
      expect(resumed.stateUpdate['lastTick'], isA<int>());
    });

    test('reset restores remaining from duration', () {
      final result = handleRemotePanelAction(panel(), 'reset', {});
      expect(result.stateUpdate['remaining'], 600);
      expect(result.stateUpdate['isRunning'], isFalse);
      expect(result.stateUpdate['completed'], isFalse);
    });

    test('unknown action fails', () {
      final result = handleRemotePanelAction(panel(), 'tick', {});
      expect(result.ok, isFalse);
    });
  });

  group('board.chat actions', () {
    RemotePanel panel() => _panel('board.chat', {
      'config': {'provider': 'kimi'},
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
      'configured': true,
    });

    test('messages returns all messages with a total', () {
      final result = handleRemotePanelAction(panel(), 'messages', {});
      expect(result.data['messages'], hasLength(1));
      expect(result.data['total'], 1);
    });

    test('send appends a user message and marks configured', () {
      final result = handleRemotePanelAction(
        panel(),
        'send',
        {'text': 'hello'},
      );
      final messages = result.stateUpdate['messages'] as List<dynamic>;
      expect(messages, hasLength(2));
      final added = messages.last as Map<String, dynamic>;
      expect(added['role'], 'user');
      expect(added['content'], 'hello');
      expect(added['createdAt'], isA<String>());
      expect(result.stateUpdate['configured'], isTrue);
    });

    test('send without text fails', () {
      final result = handleRemotePanelAction(panel(), 'send', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('text'));
    });

    test('config merges existing and new settings', () {
      final result = handleRemotePanelAction(
        panel(),
        'config',
        {'model': 'k2', 'config': {'workingDir': '/tmp'}},
      );
      final config = result.stateUpdate['config'] as Map<String, dynamic>;
      expect(config['provider'], 'kimi');
      expect(config['model'], 'k2');
      expect(config['workingDir'], '/tmp');
      expect(result.stateUpdate['configured'], isTrue);
      expect(result.data['config'], isNotNull);
    });

    test('clear empties the messages', () {
      final result = handleRemotePanelAction(panel(), 'clear', {});
      expect(result.stateUpdate['messages'], isEmpty);
    });

    test('status reports the message count', () {
      final result = handleRemotePanelAction(panel(), 'status', {});
      expect(result.data['messageCount'], 1);
      expect(result.data['isProcessing'], isFalse);
    });

    test('unknown action fails', () {
      final result = handleRemotePanelAction(panel(), 'typing', {});
      expect(result.ok, isFalse);
    });
  });

  group('board.setup_guide actions', () {
    RemotePanel panel() =>
        _panel('board.setup_guide', {
          'selectedPackageIds': ['git'],
        });

    test('select adds a package id once', () {
      final result = handleRemotePanelAction(
        panel(),
        'select',
        {'packageId': 'docker'},
      );
      expect(result.stateUpdate['selectedPackageIds'], ['git', 'docker']);
      final again = handleRemotePanelAction(
        panel(),
        'select',
        {'packageId': 'git'},
      );
      expect(again.stateUpdate['selectedPackageIds'], ['git']);
    });

    test('select without packageId fails', () {
      final result = handleRemotePanelAction(panel(), 'select', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('packageId'));
    });

    test('unselect removes a package id', () {
      final result = handleRemotePanelAction(
        panel(),
        'unselect',
        {'packageId': 'git'},
      );
      expect(result.stateUpdate['selectedPackageIds'], isEmpty);
    });

    test('unselect without packageId fails', () {
      final result = handleRemotePanelAction(panel(), 'unselect', {});
      expect(result.ok, isFalse);
    });

    test('set-selected replaces the whole selection', () {
      final result = handleRemotePanelAction(
        panel(),
        'set-selected',
        {'packageIds': ['a', 'b']},
      );
      expect(result.stateUpdate['selectedPackageIds'], ['a', 'b']);
    });

    test('unknown action fails', () {
      final result = handleRemotePanelAction(panel(), 'install', {});
      expect(result.ok, isFalse);
    });
  });

  group('board.run actions', () {
    RemotePanel panel() => _panel('board.run', {
      'group': 'default',
      'activeSessionId': 's-1',
      'command': 'make',
    });

    test('get returns the panel state', () {
      final result = handleRemotePanelAction(panel(), 'get', {});
      expect(result.data['group'], 'default');
      expect(result.data['command'], 'make');
    });

    test('set-group updates the group', () {
      final result = handleRemotePanelAction(
        panel(),
        'set-group',
        {'group': 'builds'},
      );
      expect(result.stateUpdate['group'], 'builds');
    });

    test('set-group without group fails', () {
      final result = handleRemotePanelAction(panel(), 'set-group', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('group'));
    });

    test('select-session sets the active session', () {
      final result = handleRemotePanelAction(
        panel(),
        'select-session',
        {'sessionId': 's-2'},
      );
      expect(result.stateUpdate['activeSessionId'], 's-2');
    });

    test('select-session without sessionId fails', () {
      final result = handleRemotePanelAction(panel(), 'select-session', {});
      expect(result.ok, isFalse);
    });

    test('clear-session clears the active session', () {
      final result = handleRemotePanelAction(panel(), 'clear-session', {});
      expect(result.stateUpdate.containsKey('activeSessionId'), isTrue);
      expect(result.stateUpdate['activeSessionId'], isNull);
    });

    test('board.run_configs uses the same handlers', () {
      final configsPanel = _panel('board.run_configs', {'group': 'default'});
      final result = handleRemotePanelAction(
        configsPanel,
        'set-group',
        {'group': 'ci'},
      );
      expect(result.stateUpdate['group'], 'ci');
    });

    test('unknown action fails', () {
      final result = handleRemotePanelAction(panel(), 'stop', {});
      expect(result.ok, isFalse);
    });
  });

  group('board.calendar update-event', () {
    RemotePanel panel() => _panel('board.calendar', {
      'events': [
        {
          'id': 'ev-1',
          'title': 'Standup',
          'start': '2026-08-03T09:00:00.000Z',
          'end': '2026-08-03T09:30:00.000Z',
          'allDay': false,
          'description': 'daily',
          'color': '#fff',
          'meetingUrl': 'https://meet.example/x',
        },
      ],
    });

    test('update-event patches only provided fields', () {
      final result = handleRemotePanelAction(panel(), 'update-event', {
        'eventId': 'ev-1',
        'title': 'Sync',
        'allDay': true,
      });
      expect(result.ok, isTrue);
      final events = result.stateUpdate['events'] as List<dynamic>;
      final event = events.single as Map<String, dynamic>;
      expect(event['title'], 'Sync');
      expect(event['allDay'], isTrue);
      expect(event['start'], '2026-08-03T09:00:00.000Z');
      expect(event['description'], 'daily');
      expect(result.stateUpdate['eventCount'], 1);
      expect(result.data['event'], isNotNull);
    });

    test('update-event can move start and end', () {
      final result = handleRemotePanelAction(panel(), 'update-event', {
        'id': 'ev-1',
        'start': '2026-08-04T10:00:00.000Z',
        'end': '2026-08-04T11:00:00.000Z',
        'meetingUrl': 'https://meet.example/y',
      });
      final events = result.stateUpdate['events'] as List<dynamic>;
      final event = events.single as Map<String, dynamic>;
      expect(event['start'], '2026-08-04T10:00:00.000Z');
      expect(event['end'], '2026-08-04T11:00:00.000Z');
      expect(event['meetingUrl'], 'https://meet.example/y');
    });

    test('update-event with invalid start keeps the existing start', () {
      final result = handleRemotePanelAction(panel(), 'update-event', {
        'eventId': 'ev-1',
        'start': 'not-a-date',
      });
      final events = result.stateUpdate['events'] as List<dynamic>;
      final event = events.single as Map<String, dynamic>;
      expect(event['start'], '2026-08-03T09:00:00.000Z');
    });

    test('update-event without id fails', () {
      final result = handleRemotePanelAction(panel(), 'update-event', {
        'title': 'X',
      });
      expect(result.ok, isFalse);
      expect(result.message, contains('eventId'));
    });

    test('update-event for a missing event fails', () {
      final result = handleRemotePanelAction(panel(), 'update-event', {
        'eventId': 'ev-404',
        'title': 'X',
      });
      expect(result.ok, isFalse);
      expect(result.message, contains('not found'));
    });
  });

  group('board.chart set-options', () {
    RemotePanel panel() => _panel('board.chart', {
      'type': 'line',
      'xKey': 'month',
      'yKey': 'sales',
      'animated': true,
    });

    test('set-options updates keys and animated flag', () {
      final result = handleRemotePanelAction(panel(), 'set-options', {
        'xKey': 'day',
        'yKey': 'count',
        'groupKey': 'region',
        'animated': false,
      });
      final update = result.stateUpdate;
      expect(update['xKey'], 'day');
      expect(update['yKey'], 'count');
      expect(update['groupKey'], 'region');
      expect(update['animated'], isFalse);
      expect(update['type'], 'line');
    });

    test('set-options accepts x/y/group aliases', () {
      final result = handleRemotePanelAction(panel(), 'set-options', {
        'x': 'day',
        'y': 'count',
        'group': 'region',
      });
      expect(result.stateUpdate['xKey'], 'day');
      expect(result.stateUpdate['yKey'], 'count');
      expect(result.stateUpdate['groupKey'], 'region');
    });

    test('set-options without args keeps the existing options', () {
      final result = handleRemotePanelAction(panel(), 'set-options', {});
      expect(result.stateUpdate['xKey'], 'month');
      expect(result.stateUpdate['yKey'], 'sales');
      expect(result.stateUpdate['animated'], isTrue);
    });
  });

  group('board.yolo_assistant actions', () {
    RemotePanel panel() => _panel('board.yolo_assistant', {
      'mode': 'voice',
      'assistantStatus': 'idle',
      'messages': [
        {'role': 'user', 'content': 'hey'},
      ],
      'voiceDraft': 'draft',
      'voiceResponse': 'response',
    });

    test('get returns the panel state', () {
      final result = handleRemotePanelAction(panel(), 'get', {});
      expect(result.data['mode'], 'voice');
      expect(result.data['assistantStatus'], 'idle');
    });

    test('set-mode updates the mode', () {
      final result = handleRemotePanelAction(
        panel(),
        'set-mode',
        {'mode': 'text'},
      );
      expect(result.stateUpdate['mode'], 'text');
    });

    test('set-mode without mode fails', () {
      final result = handleRemotePanelAction(panel(), 'set-mode', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('mode'));
    });

    test('set-status updates the assistant status', () {
      final result = handleRemotePanelAction(
        panel(),
        'set-status',
        {'status': 'listening'},
      );
      expect(result.stateUpdate['assistantStatus'], 'listening');
    });

    test('set-status without status fails', () {
      final result = handleRemotePanelAction(panel(), 'set-status', {});
      expect(result.ok, isFalse);
    });

    test('clear resets messages and voice state', () {
      final result = handleRemotePanelAction(panel(), 'clear', {});
      expect(result.stateUpdate['messages'], isEmpty);
      expect(result.stateUpdate['voiceDraft'], '');
      expect(result.stateUpdate['voiceResponse'], '');
    });

    test('unknown action fails', () {
      final result = handleRemotePanelAction(panel(), 'speak', {});
      expect(result.ok, isFalse);
    });
  });

  group('board.widget.custom actions', () {
    RemotePanel panel() => _panel('board.widget.custom', {
      'widgetId': 'w-1',
      'config': {'theme': 'dark'},
      'extra': 42,
    });

    test('get returns the panel state', () {
      final result = handleRemotePanelAction(panel(), 'get', {});
      expect(result.data['widgetId'], 'w-1');
      expect(result.data['extra'], 42);
    });

    test('set-widget updates the widget id', () {
      final result = handleRemotePanelAction(
        panel(),
        'set-widget',
        {'widgetId': 'w-2'},
      );
      expect(result.stateUpdate['widgetId'], 'w-2');
    });

    test('set-widget without widgetId fails', () {
      final result = handleRemotePanelAction(panel(), 'set-widget', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('widgetId'));
    });

    test('set-config merges configs', () {
      final result = handleRemotePanelAction(panel(), 'set-config', {
        'config': {'size': 'large'},
      });
      final config = result.stateUpdate['config'] as Map<String, dynamic>;
      expect(config['theme'], 'dark');
      expect(config['size'], 'large');
    });

    test('set applies arbitrary state updates', () {
      final result = handleRemotePanelAction(panel(), 'set', {
        'action': 'set',
        'extra': 43,
        'title': 'Custom',
      });
      expect(result.stateUpdate['extra'], 43);
      expect(result.stateUpdate['title'], 'Custom');
      expect(result.stateUpdate.containsKey('action'), isFalse);
    });

    test('unknown action fails', () {
      final result = handleRemotePanelAction(panel(), 'reload', {});
      expect(result.ok, isFalse);
    });
  });
}
