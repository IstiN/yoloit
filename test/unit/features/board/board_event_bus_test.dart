import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/events/board_event_bus.dart';

void main() {
  group('BoardEventBus', () {
    test('instance is a singleton', () {
      expect(BoardEventBus.instance, same(BoardEventBus.instance));
    });

    test('emits events to all listeners', () async {
      final received = <BoardEvent>[];
      final sub = BoardEventBus.instance.stream.listen(received.add);
      addTearDown(sub.cancel);

      BoardEventBus.instance.emit(const BoardFileModifiedEvent('/tmp/foo.md'));

      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      expect(received.first, isA<BoardFileModifiedEvent>());
      expect((received.first as BoardFileModifiedEvent).path, '/tmp/foo.md');
    });

    test('on<T>() filters by event type', () async {
      final files = <String>[];
      final sub = BoardEventBus.instance.on<BoardFileModifiedEvent>().listen(
        (e) => files.add(e.path),
      );
      addTearDown(sub.cancel);

      BoardEventBus.instance.emit(const BoardFileModifiedEvent('/a.md'));
      BoardEventBus.instance.emit(const BoardFileModifiedEvent('/b.dart'));

      await Future<void>.delayed(Duration.zero);
      expect(files, ['/a.md', '/b.dart']);
    });

    test('fileModified() convenience emits BoardFileModifiedEvent', () async {
      final received = <BoardFileModifiedEvent>[];
      final sub =
          BoardEventBus.instance.on<BoardFileModifiedEvent>().listen(received.add);
      addTearDown(sub.cancel);

      BoardEventBus.instance.fileModified('/some/path/file.txt');

      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      expect(received.first.path, '/some/path/file.txt');
    });

    test('multiple subscribers each receive the event', () async {
      final received1 = <String>[];
      final received2 = <String>[];
      final sub1 = BoardEventBus.instance
          .on<BoardFileModifiedEvent>()
          .listen((e) => received1.add(e.path));
      final sub2 = BoardEventBus.instance
          .on<BoardFileModifiedEvent>()
          .listen((e) => received2.add(e.path));
      addTearDown(sub1.cancel);
      addTearDown(sub2.cancel);

      BoardEventBus.instance.fileModified('/shared.md');

      await Future<void>.delayed(Duration.zero);
      expect(received1, ['/shared.md']);
      expect(received2, ['/shared.md']);
    });

    test('cancelled subscription no longer receives events', () async {
      final received = <String>[];
      final sub = BoardEventBus.instance
          .on<BoardFileModifiedEvent>()
          .listen((e) => received.add(e.path));

      await sub.cancel();

      BoardEventBus.instance.fileModified('/after_cancel.md');
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
    });

    test('BoardFileModifiedEvent stores path correctly', () {
      const event = BoardFileModifiedEvent('/abs/path/to/notes.md');
      expect(event.path, '/abs/path/to/notes.md');
      expect(event, isA<BoardEvent>());
    });
  });
}
