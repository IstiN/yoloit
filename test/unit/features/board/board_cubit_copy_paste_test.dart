import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/calendar/data/calendar_event_storage.dart';
import 'package:yoloit/features/calendar/model/calendar_event.dart';

class _FakeClipboard implements ClipboardInterface {
  String? _text;

  @override
  Future<void> setText(String text) async => _text = text;

  @override
  Future<String?> getText() async => _text;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('board_cubit_copy_test');
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: tmpDir.path));
  });

  tearDown(() {
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
    PlatformDirs.setInstance(const MacosPlatformDirs());
  });

  Future<BoardCubit> createCubit({ClipboardInterface? clipboard}) async {
    final prefs = await SharedPreferences.getInstance();
    const board = BoardDocument(
      id: 'b1',
      name: 'Board 1',
      panels: [
        BoardPanelInstance(
          id: 'p1',
          type: 'board.note.markdown',
          title: 'Notes',
          bounds: BoardPanelBounds(x: 100, y: 100, width: 300, height: 200),
        ),
      ],
    );
    await prefs.setString(
      'board.documents.v1',
      jsonEncode([board.toJson()]),
    );
    await prefs.setString('board.active.id.v1', 'b1');
    final cubit = BoardCubit(clipboard: clipboard);
    await cubit.load();
    return cubit;
  }

  group('BoardCubit copy/paste/duplicate', () {
    test('copyPanels writes panel JSON to clipboard', () async {
      final fake = _FakeClipboard();
      final cubit = await createCubit(clipboard: fake);
      addTearDown(cubit.close);

      final copied = await cubit.copyPanels({'p1'});
      expect(copied, ['p1']);

      final payload = jsonDecode(fake._text ?? '{}') as Map<String, dynamic>;
      expect(payload['kind'], 'yoloit/panels');
      expect((payload['panels'] as List).length, 1);
      expect(
        ((payload['panels'] as List).first as Map<String, dynamic>)['id'],
        'p1',
      );
    });

    test('pastePanels creates new panels with new ids', () async {
      final fake = _FakeClipboard();
      final cubit = await createCubit(clipboard: fake);
      addTearDown(cubit.close);

      await cubit.copyPanels({'p1'});
      final pasted = await cubit.pastePanels();

      expect(pasted.length, 1);
      expect(pasted.first, isNot('p1'));
      final activeBoard = cubit.state.activeBoard;
      expect(activeBoard?.panels.length, 2);
      final original = activeBoard?.panels.firstWhere((p) => p.id == 'p1');
      final duplicate = activeBoard?.panels.firstWhere((p) => p.id == pasted.first);
      expect(duplicate?.title, original?.title);
      expect(duplicate?.bounds.x, original!.bounds.x + 40);
      expect(duplicate?.bounds.y, original.bounds.y + 40);
    });

    test('duplicatePanels creates copy without clipboard change', () async {
      final fake = _FakeClipboard();
      final cubit = await createCubit(clipboard: fake);
      addTearDown(cubit.close);

      cubit.selectPanels({'p1'});
      final duplicated = await cubit.duplicatePanels();

      expect(duplicated.length, 1);
      expect(cubit.state.activeBoard?.panels.length, 2);
    });

    test('pastePanels returns empty when clipboard is empty', () async {
      final fake = _FakeClipboard();
      final cubit = await createCubit(clipboard: fake);
      addTearDown(cubit.close);

      final pasted = await cubit.pastePanels();
      expect(pasted, isEmpty);
    });

    test('copy and paste preserve internal links with remapped ids', () async {
      final fake = _FakeClipboard();
      final prefs = await SharedPreferences.getInstance();
      const board = BoardDocument(
        id: 'b1',
        name: 'Board 1',
        panels: [
          BoardPanelInstance(
            id: 'p1',
            type: 'board.note.markdown',
            title: 'Source',
            bounds: BoardPanelBounds(x: 100, y: 100, width: 300, height: 200),
          ),
          BoardPanelInstance(
            id: 'p2',
            type: 'board.note.markdown',
            title: 'Target',
            bounds: BoardPanelBounds(x: 500, y: 100, width: 300, height: 200),
          ),
        ],
        links: [
          BoardPanelLink(
            id: 'l1',
            fromPanelId: 'p1',
            toPanelId: 'p2',
          ),
        ],
      );
      await prefs.setString('board.documents.v1', jsonEncode([board.toJson()]));
      await prefs.setString('board.active.id.v1', 'b1');
      final cubit = BoardCubit(clipboard: fake);
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.copyPanels({'p1', 'p2'});
      final pasted = await cubit.pastePanels();

      expect(pasted.length, 2);
      final activeBoard = cubit.state.activeBoard;
      expect(activeBoard?.links.length, 2);
      final copiedLink = activeBoard?.links.firstWhere((l) => l.id != 'l1');
      expect(copiedLink, isNotNull);
      expect(pasted, contains(copiedLink!.fromPanelId));
      expect(pasted, contains(copiedLink.toPanelId));
    });

    test('duplicate copies calendar event files', () async {
      final fake = _FakeClipboard();
      const storage = CalendarEventStorage();
      const board = BoardDocument(
        id: 'b1',
        name: 'Board 1',
        panels: [
          BoardPanelInstance(
            id: 'cal1',
            type: 'board.calendar',
            title: 'Calendar',
            bounds: BoardPanelBounds(x: 100, y: 100, width: 300, height: 200),
          ),
        ],
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('board.documents.v1', jsonEncode([board.toJson()]));
      await prefs.setString('board.active.id.v1', 'b1');
      await storage.upsertEvent(
        'cal1',
        CalendarEvent(
          id: 'ev-1',
          title: 'Standup',
          start: DateTime(2026, 6, 19, 10),
        ),
      );

      final cubit = BoardCubit(clipboard: fake);
      addTearDown(cubit.close);
      await cubit.load();
      cubit.selectPanels({'cal1'});
      final duplicated = await cubit.duplicatePanels();

      expect(duplicated.length, 1);
      final newId = duplicated.first;
      final copiedEvents = await storage.loadEvents(newId);
      expect(copiedEvents.length, 1);
      expect(copiedEvents.first.title, 'Standup');
    });
  });
}
