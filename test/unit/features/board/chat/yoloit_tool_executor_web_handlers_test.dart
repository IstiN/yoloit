import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_executor_web.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/calendar/data/calendar_event_storage.dart';

import '../../../../helpers/fake_board_cubit.dart';

/// Coverage-focused tests for the calendar, group, and YoLo chat command
/// handlers in `yoloit_tool_executor_web_handlers.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BoardPanelInstance fakePanel(
    String id,
    String type,
    String title, {
    Map<String, dynamic> state = const {},
  }) {
    return BoardPanelInstance(
      id: id,
      type: type,
      title: title,
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      state: state,
    );
  }

  Map<String, dynamic> decode(String result) =>
      jsonDecode(result) as Map<String, dynamic>;

  group('YoloitWebToolExecutor handlers', () {
    late FakeBoardCubit cubit;
    late YoloitWebToolExecutor executor;

    setUp(() {
      cubit = FakeBoardCubit();
      executor = YoloitWebToolExecutor();
    });

    Future<String> invoke(String functionName, Map<String, Object?> args) {
      return executor.invoke(
        functionName,
        args,
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
    }

    Future<String> addCalendarEvent(
      String panelTitle,
      Map<String, Object?> extra,
    ) {
      return invoke('yoloit_calendar_add_event', {
        'panel': panelTitle,
        'title': 'Standup',
        'start': DateTime(2026, 7, 7, 10).toIso8601String(),
        ...extra,
      });
    }

    group('calendar', () {
      // CalendarEventStorage is file-backed; wipe each panel's store so
      // results do not depend on previous runs.
      const calendarPanelIds = <String>[
        'p-cal-a',
        'p-cal-b',
        'p-cal-c',
        'p-cal-d',
        'p-cal-e',
        'p-cal-f',
        'p-cal-g',
        'p-cal-h',
        'p-cal-i',
        'p-cal-j',
      ];

      Future<void> clearCalendarStores() async {
        for (final id in calendarPanelIds) {
          await const CalendarEventStorage().clearEvents(id);
        }
      }

      setUp(clearCalendarStores);
      tearDown(clearCalendarStores);

      test('calendar:add-event stores all optional fields', () async {
        cubit.addFakePanel(fakePanel('p-cal-a', 'board.calendar', 'CalA'));

        final result = await addCalendarEvent('CalA', {
          'end': DateTime(2026, 7, 7, 11).toIso8601String(),
          'allDay': true,
          'description': 'Daily sync',
          'color': '#FF0000',
        });
        expect(decode(result)['ok'], isTrue);

        final eventsResult = await invoke('yoloit_calendar_events', {
          'panel': 'CalA',
        });
        final events = decode(eventsResult)['events'] as List;
        expect(events.length, 1);
        final event = events.first as Map<String, dynamic>;
        expect(event['title'], 'Standup');
        expect(event['allDay'], isTrue);
        expect(event['description'], 'Daily sync');
        expect(event['color'], isNotNull);
        expect(event['end'], isNotNull);
      });

      test('calendar:add-event accepts a DateTime start value', () async {
        cubit.addFakePanel(fakePanel('p-cal-b', 'board.calendar', 'CalB'));

        final result = await invoke('yoloit_calendar_add_event', {
          'panel': 'CalB',
          'title': 'DateTime start',
          'start': DateTime(2026, 7, 8, 9),
        });
        expect(decode(result)['ok'], isTrue);
      });

      test('calendar:add-event returns error when title missing', () async {
        cubit.addFakePanel(fakePanel('p-cal-c', 'board.calendar', 'CalC'));

        final result = await invoke('yoloit_calendar_add_event', {
          'panel': 'CalC',
          'start': DateTime(2026, 7, 7).toIso8601String(),
        });
        final decoded = decode(result);
        expect(decoded['ok'], isFalse);
        expect(decoded['error'], contains('Missing event title'));
      });

      test('calendar:add-event returns error for invalid start', () async {
        cubit.addFakePanel(fakePanel('p-cal-d', 'board.calendar', 'CalD'));

        final badString = await invoke('yoloit_calendar_add_event', {
          'panel': 'CalD',
          'title': 'X',
          'start': 'not-a-date',
        });
        expect(decode(badString)['error'], contains('invalid start time'));

        final emptyString = await invoke('yoloit_calendar_add_event', {
          'panel': 'CalD',
          'title': 'X',
          'start': '   ',
        });
        expect(decode(emptyString)['error'], contains('invalid start time'));

        final wrongType = await invoke('yoloit_calendar_add_event', {
          'panel': 'CalD',
          'title': 'X',
          'start': 42,
        });
        expect(decode(wrongType)['error'], contains('invalid start time'));
      });

      test('calendar:update-event updates provided fields only', () async {
        cubit.addFakePanel(fakePanel('p-cal-e', 'board.calendar', 'CalE'));
        final addResult = await addCalendarEvent('CalE', {
          'description': 'Old',
        });
        final eventId = decode(addResult)['id'] as String;

        final updateResult = await invoke('yoloit_calendar_update_event', {
          'panel': 'CalE',
          'eventId': eventId,
          'title': 'Renamed',
          'start': DateTime(2026, 7, 9, 12).toIso8601String(),
          'end': DateTime(2026, 7, 9, 13).toIso8601String(),
          'allDay': true,
          'description': 'New',
          'color': '#00FF00',
        });
        expect(decode(updateResult)['ok'], isTrue);

        final showResult = await invoke('yoloit_calendar_show_event', {
          'panel': 'CalE',
          'eventId': eventId,
        });
        final event = decode(showResult)['event'] as Map<String, dynamic>;
        expect(event['title'], 'Renamed');
        expect(event['allDay'], isTrue);
        expect(event['description'], 'New');
        expect(event['color'], isNotNull);
        expect(event['end'], isNotNull);
      });

      test('calendar:update-event keeps existing values when args omitted', () async {
        cubit.addFakePanel(fakePanel('p-cal-f', 'board.calendar', 'CalF'));
        final addResult = await addCalendarEvent('CalF', {
          'description': 'Keep me',
        });
        final eventId = decode(addResult)['id'] as String;

        final updateResult = await invoke('yoloit_calendar_update_event', {
          'panel': 'CalF',
          'eventId': eventId,
        });
        expect(decode(updateResult)['ok'], isTrue);

        final showResult = await invoke('yoloit_calendar_show_event', {
          'panel': 'CalF',
          'eventId': eventId,
        });
        final event = decode(showResult)['event'] as Map<String, dynamic>;
        expect(event['title'], 'Standup');
        expect(event['description'], 'Keep me');
      });

      test('calendar:update-event validates the event id', () async {
        cubit.addFakePanel(fakePanel('p-cal-g', 'board.calendar', 'CalG'));

        final missing = await invoke('yoloit_calendar_update_event', {
          'panel': 'CalG',
          'title': 'X',
        });
        expect(decode(missing)['error'], contains('Missing event id'));

        final unknown = await invoke('yoloit_calendar_update_event', {
          'panel': 'CalG',
          'eventId': 'no-such-event',
          'title': 'X',
        });
        expect(decode(unknown)['error'], contains('Event not found'));
      });

      test('calendar:focus-date sets focusedDate and validates input', () async {
        cubit.addFakePanel(fakePanel('p-cal-h', 'board.calendar', 'CalH'));

        final result = await invoke('yoloit_calendar_focus_date', {
          'panel': 'CalH',
          'date': '2026-07-15',
        });
        expect(decode(result)['ok'], isTrue);
        expect(
          cubit.updatedPanels['p-cal-h']?.state['focusedDate'],
          contains('2026-07-15'),
        );

        final invalid = await invoke('yoloit_calendar_focus_date', {
          'panel': 'CalH',
          'date': 'junk',
        });
        expect(decode(invalid)['error'], contains('invalid date'));
      });

      test('calendar:scroll-to-time sets scrollHour and validates input', () async {
        cubit.addFakePanel(fakePanel('p-cal-i', 'board.calendar', 'CalI'));

        final result = await invoke('yoloit_calendar_scroll_to_time', {
          'panel': 'CalI',
          'hour': 14,
        });
        expect(decode(result)['ok'], isTrue);
        expect(cubit.updatedPanels['p-cal-i']?.state['scrollHour'], 14);

        final missing = await invoke('yoloit_calendar_scroll_to_time', {
          'panel': 'CalI',
        });
        expect(decode(missing)['error'], contains('Missing hour'));
      });

      test('calendar:scroll-to-event focuses the event date', () async {
        cubit.addFakePanel(fakePanel('p-cal-j', 'board.calendar', 'CalJ'));
        final addResult = await addCalendarEvent('CalJ', {});
        final eventId = decode(addResult)['id'] as String;

        final result = await invoke('yoloit_calendar_scroll_to_event', {
          'panel': 'CalJ',
          'eventId': eventId,
        });
        expect(decode(result)['ok'], isTrue);
        final state = cubit.updatedPanels['p-cal-j']?.state;
        expect(state?['selectedEventId'], eventId);
        expect(state?['focusedDate'], contains('2026-07-07'));
      });
    });

    group('groups', () {
      test('group:create stores color and panel ids', () async {
        cubit.addFakePanel(fakePanel('p-gc1', 'board.note.markdown', 'Member'));

        final result = await invoke('yoloit_group_create', {
          'name': 'Colored',
          'panels': 'Member',
          'color': '#FF0000',
        });
        expect(decode(result)['ok'], isTrue);
        final group = cubit.createdGroups.first;
        expect(group.color, isNotNull);
        expect(group.panelIds, contains('p-gc1'));
      });

      test('group:delete removes the group', () async {
        await invoke('yoloit_group_create', {'name': 'Doomed'});

        final result = await invoke('yoloit_group_delete', {
          'group': 'group-0',
        });
        expect(decode(result)['ok'], isTrue);
        expect(cubit.state.activeBoard?.groups, isEmpty);
      });

      test('group handlers return error when group not found', () async {
        final result = await invoke('yoloit_group_delete', {
          'group': 'Missing',
        });
        final decoded = decode(result);
        expect(decoded['ok'], isFalse);
        expect(decoded['error'], contains('Group not found'));
      });

      test('group:rename returns error when new name missing', () async {
        await invoke('yoloit_group_create', {'name': 'Named'});

        final result = await invoke('yoloit_group_rename', {'group': 'Named'});
        final decoded = decode(result);
        expect(decoded['ok'], isFalse);
        expect(decoded['error'], contains('Missing new name'));
      });

      test('group:color sets and clears the color', () async {
        await invoke('yoloit_group_create', {'name': 'Painted'});

        final setResult = await invoke('yoloit_group_color', {
          'group': 'Painted',
          'color': '#00FF00',
        });
        expect(decode(setResult)['ok'], isTrue);
        expect(cubit.state.activeBoard?.groups.first.color, isNotNull);

        final clearResult = await invoke('yoloit_group_color', {
          'group': 'Painted',
          'color': 'not-a-color',
        });
        expect(decode(clearResult)['ok'], isTrue);
        expect(cubit.state.activeBoard?.groups.first.color, isNull);
      });

      test('group:add and group:remove update membership', () async {
        cubit.addFakePanel(fakePanel('p-ga1', 'board.note.markdown', 'One'));
        cubit.addFakePanel(fakePanel('p-ga2', 'board.note.markdown', 'Two'));
        await invoke('yoloit_group_create', {'name': 'Membership'});

        final addResult = await invoke('yoloit_group_add', {
          'group': 'Membership',
          'panels': 'One,Two',
        });
        expect(decode(addResult)['ok'], isTrue);
        expect(
          cubit.state.activeBoard?.groups.first.panelIds,
          containsAll(<String>['p-ga1', 'p-ga2']),
        );

        final removeResult = await invoke('yoloit_group_remove', {
          'group': 'Membership',
          'panels': 'One',
        });
        expect(decode(removeResult)['ok'], isTrue);
        expect(
          cubit.state.activeBoard?.groups.first.panelIds,
          isNot(contains('p-ga1')),
        );
      });

      test('group:add and group:remove require panels', () async {
        await invoke('yoloit_group_create', {'name': 'Empty'});

        final addResult = await invoke('yoloit_group_add', {'group': 'Empty'});
        expect(decode(addResult)['error'], contains('No panels to add'));

        final removeResult = await invoke('yoloit_group_remove', {
          'group': 'Empty',
        });
        expect(decode(removeResult)['error'], contains('No panels to remove'));
      });

      test('group:collapse and group:expand are idempotent', () async {
        await invoke('yoloit_group_create', {'name': 'Idem'});

        final expandResult = await invoke('yoloit_group_expand', {
          'group': 'Idem',
        });
        expect(decode(expandResult)['ok'], isTrue);
        expect(cubit.state.activeBoard?.groups.first.collapsed, isFalse);

        await invoke('yoloit_group_collapse', {'group': 'Idem'});
        final collapseResult = await invoke('yoloit_group_collapse', {
          'group': 'Idem',
        });
        expect(decode(collapseResult)['ok'], isTrue);
        expect(cubit.state.activeBoard?.groups.first.collapsed, isTrue);
      });

      test('group:move shifts every member panel', () async {
        cubit.addFakePanel(fakePanel('p-gm1', 'board.note.markdown', 'Mover'));
        await invoke('yoloit_group_create', {
          'name': 'Moved',
          'panels': 'Mover',
        });

        final result = await invoke('yoloit_group_move', {
          'group': 'Moved',
          'dx': 10,
          'dy': 20,
        });
        expect(decode(result)['ok'], isTrue);
        final panel = cubit.state.activeBoard?.panels.firstWhere(
          (p) => p.id == 'p-gm1',
        );
        expect(panel?.bounds.x, closeTo(10, 0.01));
        expect(panel?.bounds.y, closeTo(20, 0.01));
      });

      test('group:cycle-focus succeeds', () async {
        await invoke('yoloit_group_create', {'name': 'Cycled'});

        final result = await invoke('yoloit_group_cycle_focus', {
          'group': 'Cycled',
          'direction': 1,
        });
        expect(decode(result)['ok'], isTrue);
      });
    });

    group('yolochat', () {
      test('yolochat:send returns error when chat panel missing', () async {
        final result = await invoke('yoloit_yolochat_send', {'text': 'Hi'});
        final decoded = decode(result);
        expect(decoded['ok'], isFalse);
        expect(decoded['error'], contains('AI Chat panel not found'));
      });

      test('yolochat:send returns error when text missing', () async {
        cubit.addFakePanel(fakePanel('p-ch-s', 'board.chat', 'ChatS'));

        final result = await invoke('yoloit_yolochat_send', {
          'panel': 'ChatS',
          'text': '   ',
        });
        final decoded = decode(result);
        expect(decoded['ok'], isFalse);
        expect(decoded['error'], contains('Missing message text'));
      });

      test('yolochat:messages reads persisted panel state', () async {
        cubit.addFakePanel(
          fakePanel('p-ch-m', 'board.chat', 'ChatM', state: {
            'messages': <Map<String, dynamic>>[
              {'role': 'user', 'content': 'hello'},
            ],
          }),
        );

        final result = await invoke('yoloit_yolochat_messages', {
          'panel': 'ChatM',
        });
        final decoded = decode(result);
        expect(decoded['ok'], isTrue);
        final messages = decoded['messages'] as List;
        expect(messages.length, 1);
        expect((messages.first as Map<String, dynamic>)['content'], 'hello');
      });

      test('yolochat:clear empties panel messages', () async {
        cubit.addFakePanel(
          fakePanel('p-ch-c', 'board.chat', 'ChatC', state: {
            'messages': <Map<String, dynamic>>[
              {'role': 'user', 'content': 'hello'},
            ],
          }),
        );

        final result = await invoke('yoloit_yolochat_clear', {
          'panel': 'ChatC',
        });
        expect(decode(result)['ok'], isTrue);
        expect(
          cubit.updatedPanels['p-ch-c']?.state['messages'],
          isEmpty,
        );
      });

      test('yolochat:stop succeeds without an active session', () async {
        cubit.addFakePanel(fakePanel('p-ch-t', 'board.chat', 'ChatT'));

        final result = await invoke('yoloit_yolochat_stop', {'panel': 'ChatT'});
        expect(decode(result)['ok'], isTrue);
      });

      test('yolochat:sessions lists active session ids', () async {
        final result = await invoke('yoloit_yolochat_sessions', {});
        final decoded = decode(result);
        expect(decoded['ok'], isTrue);
        expect(decoded['sessions'], isA<List<dynamic>>());
      });

      test('yolochat:config updates the model and persists state', () async {
        cubit.addFakePanel(
          fakePanel('p-ch-cfg', 'board.chat', 'ChatCfg', state: {
            'config': {'sessionName': 'chat', 'provider': 'copilot'},
          }),
        );

        try {
          final result = await invoke('yoloit_yolochat_config', {
            'panel': 'ChatCfg',
            'model': 'gpt-5',
          });
          final decoded = decode(result);
          expect(decoded['ok'], isTrue);
          expect(
            (decoded['config'] as Map<String, dynamic>)['model'],
            'gpt-5',
          );
          expect(
            ChatSessionManager.instance.activeSessionIds,
            contains('p-ch-cfg'),
          );

          final messagesResult = await invoke('yoloit_yolochat_messages', {
            'panel': 'ChatCfg',
          });
          expect(decode(messagesResult)['messages'], isEmpty);

          final stopResult = await invoke('yoloit_yolochat_stop', {
            'panel': 'ChatCfg',
          });
          expect(decode(stopResult)['ok'], isTrue);
        } finally {
          ChatSessionManager.instance.remove('p-ch-cfg');
        }
      });
    });
  });
}
