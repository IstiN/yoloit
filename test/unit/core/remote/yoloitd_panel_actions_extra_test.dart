import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_models.dart';
import 'package:yoloit/core/remote/yoloitd_panel_actions.dart';

RemotePanel _panel(String type, Map<String, dynamic> state) => RemotePanel(
  id: 'p-${type.replaceAll('.', '-')}',
  type: type,
  title: type,
  bounds: const RemotePanelBounds(x: 0, y: 0, width: 320, height: 240),
  state: state,
);

void main() {
  group('board.webpage actions', () {
    RemotePanel panel() => _panel('board.webpage', {
      'url': 'https://example.com',
      'title': 'Example',
      'favicon': 'https://example.com/favicon.ico',
    });

    test('get returns url, title, and favicon', () {
      final result = handleRemotePanelAction(panel(), 'get', {});
      expect(result.ok, isTrue);
      expect(result.data['url'], 'https://example.com');
      expect(result.data['title'], 'Example');
      expect(result.data['favicon'], 'https://example.com/favicon.ico');
    });

    test('open updates the url', () {
      final result = handleRemotePanelAction(
        panel(),
        'open',
        {'url': 'https://flutter.dev'},
      );
      expect(result.ok, isTrue);
      expect(result.stateUpdate['url'], 'https://flutter.dev');
      expect(result.stateUpdate.containsKey('title'), isFalse);
    });

    test('open also sets the title when provided', () {
      final result = handleRemotePanelAction(
        panel(),
        'open',
        {'url': 'https://dart.dev', 'title': 'Dart'},
      );
      expect(result.stateUpdate['url'], 'https://dart.dev');
      expect(result.stateUpdate['title'], 'Dart');
    });

    test('open without url fails', () {
      final result = handleRemotePanelAction(panel(), 'open', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('url'));
    });

    test('open with an empty url fails', () {
      final result = handleRemotePanelAction(panel(), 'open', {'url': ''});
      expect(result.ok, isFalse);
      expect(result.message, contains('url'));
    });

    test('unknown action fails', () {
      final result = handleRemotePanelAction(panel(), 'reload', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('Unknown action'));
    });
  });

  group('board.playlist remove', () {
    RemotePanel panel() => _panel('board.playlist', {
      'tracks': [
        {'path': '/music/a.mp3', 'title': 'A'},
        {'path': '/music/b.mp3', 'title': 'B'},
      ],
      'currentIndex': 1,
      'playing': true,
    });

    test('remove deletes the track and resets currentIndex', () {
      final result = handleRemotePanelAction(panel(), 'remove', {'index': 0});
      expect(result.ok, isTrue);
      final tracks = result.stateUpdate['tracks'] as List<dynamic>;
      expect(tracks, hasLength(1));
      final remaining = tracks.single as Map<String, dynamic>;
      expect(remaining['path'], '/music/b.mp3');
      expect(result.stateUpdate['currentIndex'], 0);
    });

    test('remove the last track sets currentIndex to -1', () {
      final result = handleRemotePanelAction(panel(), 'remove', {'index': 1});
      final second = handleRemotePanelAction(
        _panel('board.playlist', {
          'tracks': [
            {'path': '/music/a.mp3', 'title': 'A'},
          ],
        }),
        'remove',
        {'index': 0},
      );
      final tracks = result.stateUpdate['tracks'] as List<dynamic>;
      expect(tracks, hasLength(1));
      expect(second.stateUpdate['tracks'], isEmpty);
      expect(second.stateUpdate['currentIndex'], -1);
    });

    test('remove without index fails', () {
      final result = handleRemotePanelAction(panel(), 'remove', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('not found'));
    });

    test('remove with out-of-range index fails', () {
      final result = handleRemotePanelAction(panel(), 'remove', {'index': 5});
      expect(result.ok, isFalse);
      expect(result.message, contains('track'));
      final negative = handleRemotePanelAction(
        panel(),
        'remove',
        {'index': -1},
      );
      expect(negative.ok, isFalse);
    });

    test('remove accepts a numeric string index', () {
      final result = handleRemotePanelAction(panel(), 'remove', {'index': '1'});
      expect(result.ok, isTrue);
      final tracks = result.stateUpdate['tracks'] as List<dynamic>;
      expect(tracks, hasLength(1));
      final remaining = tracks.single as Map<String, dynamic>;
      expect(remaining['path'], '/music/a.mp3');
    });
  });

  group('board.playlist next/prev', () {
    RemotePanel panel(int currentIndex) => _panel('board.playlist', {
      'tracks': [
        {'path': '/music/a.mp3', 'title': 'A'},
        {'path': '/music/b.mp3', 'title': 'B'},
        {'path': '/music/c.mp3', 'title': 'C'},
      ],
      'currentIndex': currentIndex,
    });

    test('next advances to the following track', () {
      final result = handleRemotePanelAction(panel(0), 'next', {});
      expect(result.ok, isTrue);
      expect(result.stateUpdate['currentIndex'], 1);
      expect(result.stateUpdate['playing'], isTrue);
    });

    test('next wraps around from the last track', () {
      final result = handleRemotePanelAction(panel(2), 'next', {});
      expect(result.stateUpdate['currentIndex'], 0);
    });

    test('prev moves to the previous track', () {
      final result = handleRemotePanelAction(panel(2), 'prev', {});
      expect(result.stateUpdate['currentIndex'], 1);
      expect(result.stateUpdate['playing'], isTrue);
    });

    test('prev wraps around from the first track', () {
      final result = handleRemotePanelAction(panel(0), 'prev', {});
      expect(result.stateUpdate['currentIndex'], 2);
    });

    test('next on an empty playlist fails', () {
      final empty = _panel('board.playlist', {'tracks': <dynamic>[]});
      final result = handleRemotePanelAction(empty, 'next', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('not found'));
    });

    test('prev on an empty playlist fails', () {
      final empty = _panel('board.playlist', {'tracks': <dynamic>[]});
      final result = handleRemotePanelAction(empty, 'prev', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('not found'));
    });

    test('next defaults currentIndex to 0 when missing', () {
      final noIndex = _panel('board.playlist', {
        'tracks': [
          {'path': '/music/a.mp3', 'title': 'A'},
          {'path': '/music/b.mp3', 'title': 'B'},
        ],
      });
      final result = handleRemotePanelAction(noIndex, 'next', {});
      expect(result.stateUpdate['currentIndex'], 1);
    });
  });

  group('board.calendar scroll-to-time', () {
    RemotePanel panel() => _panel('board.calendar', {
      'view': 'week',
      'events': <dynamic>[],
    });

    test('scroll-to-time sets the scroll hour and keeps state', () {
      final result = handleRemotePanelAction(panel(), 'scroll-to-time', {
        'hour': 9,
      });
      expect(result.ok, isTrue);
      expect(result.stateUpdate['scrollHour'], 9);
      expect(result.stateUpdate['view'], 'week');
    });

    test('scroll-to-time accepts a numeric string hour', () {
      final result = handleRemotePanelAction(panel(), 'scroll-to-time', {
        'hour': '18',
      });
      expect(result.ok, isTrue);
      expect(result.stateUpdate['scrollHour'], 18);
    });

    test('scroll-to-time accepts boundary hours 0 and 23', () {
      final zero = handleRemotePanelAction(panel(), 'scroll-to-time', {
        'hour': 0,
      });
      expect(zero.ok, isTrue);
      expect(zero.stateUpdate['scrollHour'], 0);
      final last = handleRemotePanelAction(panel(), 'scroll-to-time', {
        'hour': 23,
      });
      expect(last.ok, isTrue);
      expect(last.stateUpdate['scrollHour'], 23);
    });

    test('scroll-to-time without hour fails', () {
      final result = handleRemotePanelAction(panel(), 'scroll-to-time', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('hour'));
    });

    test('scroll-to-time with a non-numeric hour fails', () {
      final result = handleRemotePanelAction(panel(), 'scroll-to-time', {
        'hour': 'morning',
      });
      expect(result.ok, isFalse);
      expect(result.message, contains('hour'));
    });

    test('scroll-to-time rejects hours outside 0-23', () {
      final negative = handleRemotePanelAction(panel(), 'scroll-to-time', {
        'hour': -1,
      });
      expect(negative.ok, isFalse);
      expect(negative.message, contains('hour (0-23)'));
      final tooBig = handleRemotePanelAction(panel(), 'scroll-to-time', {
        'hour': 24,
      });
      expect(tooBig.ok, isFalse);
      expect(tooBig.message, contains('hour (0-23)'));
    });
  });

  group('board.diff.preview actions', () {
    RemotePanel panel() => _panel('board.diff.preview', {
      'filePath': '/tmp/old.txt',
      'rootPath': '/tmp',
    });

    test('open updates the file path', () {
      final result = handleRemotePanelAction(
        panel(),
        'open',
        {'path': '/tmp/new.txt'},
      );
      expect(result.ok, isTrue);
      expect(result.stateUpdate['filePath'], '/tmp/new.txt');
      expect(result.stateUpdate.containsKey('title'), isFalse);
    });

    test('open accepts the filePath alias and an optional title', () {
      final result = handleRemotePanelAction(
        panel(),
        'open',
        {'filePath': '/tmp/other.txt', 'title': 'Other diff'},
      );
      expect(result.stateUpdate['filePath'], '/tmp/other.txt');
      expect(result.stateUpdate['title'], 'Other diff');
    });

    test('open without path fails', () {
      final result = handleRemotePanelAction(panel(), 'open', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('path'));
    });

    test('set-root updates the root path', () {
      final result = handleRemotePanelAction(
        panel(),
        'set-root',
        {'rootPath': '/var'},
      );
      expect(result.ok, isTrue);
      expect(result.stateUpdate['rootPath'], '/var');
    });

    test('set-root accepts the path alias', () {
      final result = handleRemotePanelAction(
        panel(),
        'set-root',
        {'path': '/home'},
      );
      expect(result.stateUpdate['rootPath'], '/home');
    });

    test('set-root without rootPath fails', () {
      final result = handleRemotePanelAction(panel(), 'set-root', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('rootPath'));
    });

    test('unknown action fails', () {
      final result = handleRemotePanelAction(panel(), 'refresh', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('Unknown action'));
    });
  });

  group('board.playlist list/add', () {
    RemotePanel panel() => _panel('board.playlist', {
      'tracks': [
        {'path': '/music/a.mp3', 'title': 'A'},
      ],
      'currentIndex': 0,
      'playing': true,
    });

    test('list returns tracks, currentIndex, and playing', () {
      final result = handleRemotePanelAction(panel(), 'list', {});
      expect(result.ok, isTrue);
      final tracks = result.data['tracks'] as List<dynamic>;
      expect(tracks, hasLength(1));
      expect(result.data['currentIndex'], 0);
      expect(result.data['playing'], isTrue);
    });

    test('add appends a track with an explicit title', () {
      final result = handleRemotePanelAction(panel(), 'add', {
        'path': '/music/b.mp3',
        'title': 'B',
      });
      expect(result.ok, isTrue);
      final tracks = result.stateUpdate['tracks'] as List<dynamic>;
      expect(tracks, hasLength(2));
      final added = tracks.last as Map<String, dynamic>;
      expect(added['path'], '/music/b.mp3');
      expect(added['title'], 'B');
    });

    test('add accepts the url alias and falls back to the file name', () {
      final result = handleRemotePanelAction(panel(), 'add', {
        'url': 'https://example.com/audio/mix.mp3',
      });
      final tracks = result.stateUpdate['tracks'] as List<dynamic>;
      final added = tracks.last as Map<String, dynamic>;
      expect(added['path'], 'https://example.com/audio/mix.mp3');
      expect(added['title'], 'mix.mp3');
    });

    test('add without path or url fails', () {
      final result = handleRemotePanelAction(panel(), 'add', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('path or url'));
    });
  });

  group('board.playlist play/pause/stop', () {
    RemotePanel panel({int? currentIndex}) => _panel('board.playlist', {
      'tracks': [
        {'path': '/music/a.mp3', 'title': 'A'},
        {'path': '/music/b.mp3', 'title': 'B'},
        {'path': '/music/c.mp3', 'title': 'C'},
      ],
      'currentIndex': ?currentIndex,
    });

    test('play on an empty playlist fails', () {
      final empty = _panel('board.playlist', {'tracks': <dynamic>[]});
      final result = handleRemotePanelAction(empty, 'play', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('not found'));
    });

    test('play selects the requested track', () {
      final result = handleRemotePanelAction(panel(currentIndex: 0), 'play', {
        'index': 2,
      });
      expect(result.ok, isTrue);
      expect(result.stateUpdate['currentIndex'], 2);
      expect(result.stateUpdate['playing'], isTrue);
    });

    test('play defaults to the stored currentIndex', () {
      final result = handleRemotePanelAction(panel(currentIndex: 1), 'play', {});
      expect(result.stateUpdate['currentIndex'], 1);
      expect(result.stateUpdate['playing'], isTrue);
    });

    test('play clamps an out-of-range index', () {
      final high = handleRemotePanelAction(panel(), 'play', {'index': 9});
      expect(high.stateUpdate['currentIndex'], 2);
      final low = handleRemotePanelAction(panel(), 'play', {'index': -3});
      expect(low.stateUpdate['currentIndex'], 0);
    });

    test('pause stops playback without touching the track', () {
      final result = handleRemotePanelAction(panel(currentIndex: 2), 'pause', {});
      expect(result.ok, isTrue);
      expect(result.stateUpdate, {'playing': false});
    });

    test('stop resets to the first track', () {
      final result = handleRemotePanelAction(panel(currentIndex: 2), 'stop', {});
      expect(result.stateUpdate, {'playing': false, 'currentIndex': 0});
    });
  });

  group('board.calendar events', () {
    test('events returns the events and their count', () {
      final panel = _panel('board.calendar', {
        'events': [
          {'id': 'ev-1', 'title': 'Standup'},
          {'id': 'ev-2', 'title': 'Review'},
        ],
      });
      final result = handleRemotePanelAction(panel, 'events', {});
      expect(result.ok, isTrue);
      final events = result.data['events'] as List<dynamic>;
      expect(events, hasLength(2));
      expect(result.data['count'], 2);
    });
  });

  group('board.calendar create-event', () {
    RemotePanel panel() => _panel('board.calendar', {'events': <dynamic>[]});

    test('create-event without a title fails', () {
      final result = handleRemotePanelAction(panel(), 'create-event', {
        'start': '2026-01-01T09:00:00Z',
      });
      expect(result.ok, isFalse);
      expect(result.message, contains('title'));
    });

    test('create-event with a missing or invalid start fails', () {
      final missing = handleRemotePanelAction(panel(), 'create-event', {
        'title': 'Sync',
      });
      expect(missing.ok, isFalse);
      expect(missing.message, contains('start'));
      final invalid = handleRemotePanelAction(panel(), 'create-event', {
        'title': 'Sync',
        'start': 'not-a-date',
      });
      expect(invalid.ok, isFalse);
      expect(invalid.message, contains('start'));
    });

    test('create-event builds an event with a generated id and defaults', () {
      final result = handleRemotePanelAction(panel(), 'create-event', {
        'title': 'Sync',
        'start': '2026-01-01T09:00:00Z',
      });
      expect(result.ok, isTrue);
      final event = result.data['event'] as Map<String, dynamic>;
      expect(event['id'] as String, startsWith('ev-'));
      expect(event['title'], 'Sync');
      expect(event['start'], '2026-01-01T09:00:00.000Z');
      expect(event['end'], isNull);
      expect(event['allDay'], isFalse);
      expect(event['description'], '');
      expect(event['color'], '');
      expect(event['meetingUrl'], '');
      expect(result.stateUpdate['eventCount'], 1);
    });

    test('add-event alias parses end, allDay string, and url alias', () {
      final result = handleRemotePanelAction(panel(), 'add-event', {
        'title': 'Offsite',
        'start': '2026-02-02T10:00:00Z',
        'end': '2026-02-02T18:30:00Z',
        'allDay': 'true',
        'description': 'Team offsite',
        'color': '#FF0000',
        'url': 'https://meet.example.com/x',
      });
      expect(result.ok, isTrue);
      final event = result.data['event'] as Map<String, dynamic>;
      expect(event['end'], '2026-02-02T18:30:00.000Z');
      expect(event['allDay'], isTrue);
      expect(event['description'], 'Team offsite');
      expect(event['color'], '#FF0000');
      expect(event['meetingUrl'], 'https://meet.example.com/x');
      final events = result.stateUpdate['events'] as List<dynamic>;
      expect(events, hasLength(1));
    });
  });

  group('board.calendar delete-event', () {
    RemotePanel panel() => _panel('board.calendar', {
      'events': [
        {'id': 'ev-1', 'title': 'Standup'},
        {'id': 'ev-2', 'title': 'Review'},
      ],
    });

    test('delete-event without an eventId fails', () {
      final result = handleRemotePanelAction(panel(), 'delete-event', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('eventId'));
    });

    test('delete-event with an unknown id keeps the events', () {
      final result = handleRemotePanelAction(panel(), 'delete-event', {
        'eventId': 'ev-99',
      });
      expect(result.ok, isTrue);
      final events = result.stateUpdate['events'] as List<dynamic>;
      expect(events, hasLength(2));
      expect(result.stateUpdate['eventCount'], 2);
    });

    test('delete-event removes the matching event via the id alias', () {
      final result = handleRemotePanelAction(panel(), 'delete-event', {
        'id': 'ev-1',
      });
      final events = result.stateUpdate['events'] as List<dynamic>;
      expect(events, hasLength(1));
      final remaining = events.single as Map<String, dynamic>;
      expect(remaining['id'], 'ev-2');
      expect(result.stateUpdate['eventCount'], 1);
    });
  });

  group('board.calendar set-view / focus-date', () {
    RemotePanel panel() => _panel('board.calendar', {
      'view': 'week',
      'events': <dynamic>[],
    });

    test('set-view updates the view and keeps the state', () {
      final result = handleRemotePanelAction(panel(), 'set-view', {
        'view': 'day',
      });
      expect(result.ok, isTrue);
      expect(result.stateUpdate['view'], 'day');
      expect(result.stateUpdate['events'], isEmpty);
    });

    test('set-view rejects a missing or unknown view', () {
      final missing = handleRemotePanelAction(panel(), 'set-view', {});
      expect(missing.ok, isFalse);
      expect(missing.message, contains('Invalid view'));
      final unknown = handleRemotePanelAction(panel(), 'set-view', {
        'view': 'year',
      });
      expect(unknown.ok, isFalse);
      expect(unknown.message, contains('Invalid view'));
    });

    test('focus-date stores the date-only focused date', () {
      final result = handleRemotePanelAction(panel(), 'focus-date', {
        'date': '2026-03-04T15:30:00Z',
      });
      expect(result.ok, isTrue);
      final focused = DateTime.parse(
        result.stateUpdate['focusedDate'] as String,
      ).toLocal();
      expect(focused.year, 2026);
      expect(focused.month, 3);
      expect(focused.day, 4);
      expect(focused.hour, 0);
    });

    test('focus-date accepts the focusedDate alias', () {
      final result = handleRemotePanelAction(panel(), 'focus-date', {
        'focusedDate': '2026-03-05',
      });
      expect(result.ok, isTrue);
      final focused = DateTime.parse(
        result.stateUpdate['focusedDate'] as String,
      ).toLocal();
      expect(focused.month, 3);
      expect(focused.day, 5);
    });

    test('focus-date with a missing or invalid date fails', () {
      final missing = handleRemotePanelAction(panel(), 'focus-date', {});
      expect(missing.ok, isFalse);
      expect(missing.message, contains('date'));
      final invalid = handleRemotePanelAction(panel(), 'focus-date', {
        'date': 'tomorrow-ish',
      });
      expect(invalid.ok, isFalse);
      expect(invalid.message, contains('date'));
    });
  });

  group('board.note actions', () {
    RemotePanel panel({String markdown = ''}) =>
        _panel('board.note.markdown', {'markdown': markdown});

    test('set replaces the markdown via the text or markdown alias', () {
      final viaText = handleRemotePanelAction(panel(), 'set', {
        'text': '# Hello',
      });
      expect(viaText.ok, isTrue);
      expect(viaText.stateUpdate['markdown'], '# Hello');
      final viaMarkdown = handleRemotePanelAction(panel(), 'set', {
        'markdown': 'body',
      });
      expect(viaMarkdown.stateUpdate['markdown'], 'body');
    });

    test('set without text or markdown fails', () {
      final result = handleRemotePanelAction(panel(), 'set', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('text or markdown'));
    });

    test('append writes to an empty note and newline-joins otherwise', () {
      final empty = handleRemotePanelAction(panel(), 'append', {
        'text': 'first',
      });
      expect(empty.stateUpdate['markdown'], 'first');
      final appended = handleRemotePanelAction(
        panel(markdown: 'first'),
        'append',
        {'text': 'second'},
      );
      expect(appended.stateUpdate['markdown'], 'first\nsecond');
    });

    test('append without text fails', () {
      final result = handleRemotePanelAction(panel(), 'append', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('text'));
    });

    test('wrap and nowrap toggle auto-height', () {
      final wrap = handleRemotePanelAction(panel(), 'wrap', {});
      expect(wrap.ok, isTrue);
      expect(wrap.stateUpdate['autoHeight'], isTrue);
      final nowrap = handleRemotePanelAction(panel(), 'nowrap', {});
      expect(nowrap.stateUpdate['autoHeight'], isFalse);
    });
  });

  group('board.sticky actions', () {
    RemotePanel panel({String text = ''}) =>
        _panel('board.sticky', {'text': text});

    test('set without any fields fails', () {
      final result = handleRemotePanelAction(panel(), 'set', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('sticky fields'));
    });

    test('set updates the provided fields only', () {
      final result = handleRemotePanelAction(panel(), 'set', {
        'text': 'Note',
        'color': '#FF0000',
        'fontSize': 24,
      });
      expect(result.ok, isTrue);
      expect(result.stateUpdate, {
        'text': 'Note',
        'color': '#FF0000',
        'fontSize': 24,
      });
    });

    test('append writes to an empty sticky and newline-joins otherwise', () {
      final empty = handleRemotePanelAction(panel(), 'append', {
        'text': 'one',
      });
      expect(empty.stateUpdate['text'], 'one');
      final appended = handleRemotePanelAction(panel(text: 'one'), 'append', {
        'text': 'two',
      });
      expect(appended.stateUpdate['text'], 'one\ntwo');
    });

    test('color without color, textColor, or fontSize fails', () {
      final result = handleRemotePanelAction(panel(), 'color', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('color, textColor, or fontSize'));
    });

    test('color maps color and textColor to nullable update keys', () {
      final result = handleRemotePanelAction(panel(), 'color', {
        'color': '#00FF00',
        'textColor': '#111111',
      });
      expect(result.ok, isTrue);
      expect(result.stateUpdate['color?'], '#00FF00');
      expect(result.stateUpdate['textColor?'], '#111111');
      expect(result.stateUpdate.containsKey('fontSize'), isFalse);
    });

    test('color accepts the fillColor alias and a fontSize', () {
      final result = handleRemotePanelAction(panel(), 'color', {
        'fillColor': '#0000FF',
        'fontSize': 20,
      });
      expect(result.stateUpdate['color?'], '#0000FF');
      expect(result.stateUpdate['fontSize'], 20);
    });
  });

  group('board.shape actions', () {
    RemotePanel panel() => _panel('board.shape', {'shape': 'rectangle'});

    test('set without any fields fails', () {
      final result = handleRemotePanelAction(panel(), 'set', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('shape fields'));
    });

    test('set updates the provided fields only', () {
      final result = handleRemotePanelAction(panel(), 'set', {
        'shape': 'ellipse',
        'text': 'Node',
        'strokeWidth': 4,
      });
      expect(result.ok, isTrue);
      expect(result.stateUpdate, {
        'shape': 'ellipse',
        'text': 'Node',
        'strokeWidth': 4,
      });
    });

    test('non-set actions fail', () {
      final result = handleRemotePanelAction(panel(), 'resize', {});
      expect(result.ok, isFalse);
      expect(result.message, contains('Unknown action'));
    });
  });

  group('board.code.snippet actions', () {
    RemotePanel panel() =>
        _panel('board.code.snippet', {'language': 'dart', 'code': ''});

    test('set without code fails', () {
      final result = handleRemotePanelAction(panel(), 'set', {
        'language': 'rust',
      });
      expect(result.ok, isFalse);
      expect(result.message, contains('code'));
    });

    test('set updates the code and keeps the language untouched', () {
      final result = handleRemotePanelAction(panel(), 'set', {
        'code': 'void main() {}',
      });
      expect(result.ok, isTrue);
      expect(result.stateUpdate, {'code': 'void main() {}'});
    });

    test('set updates the language when provided', () {
      final result = handleRemotePanelAction(panel(), 'set', {
        'code': 'fn main() {}',
        'language': 'rust',
      });
      expect(result.stateUpdate, {'code': 'fn main() {}', 'language': 'rust'});
    });
  });
}
