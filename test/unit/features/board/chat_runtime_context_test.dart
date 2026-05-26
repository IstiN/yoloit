import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';

void main() {
  group('ChatRuntimeContext — snapshot fields', () {
    test('default values are null', () {
      const ctx = ChatRuntimeContext();
      expect(ctx.boardSnapshotPath, isNull);
      expect(ctx.boardSnapshotBase64, isNull);
      expect(ctx.boardId, isNull);
      expect(ctx.boardName, isNull);
      expect(ctx.panelId, isNull);
      expect(ctx.panelTitle, isNull);
      expect(ctx.panelType, isNull);
      expect(ctx.availableBoardsSummary, isNull);
      expect(ctx.currentBoardPanelsSummary, isNull);
      expect(ctx.viewportScale, isNull);
    });

    test('boardSnapshotPath can be set', () {
      const ctx = ChatRuntimeContext(boardSnapshotPath: '/tmp/board.png');
      expect(ctx.boardSnapshotPath, '/tmp/board.png');
    });

    test('boardSnapshotBase64 can be set', () {
      const ctx = ChatRuntimeContext(boardSnapshotBase64: 'iVBOR...');
      expect(ctx.boardSnapshotBase64, 'iVBOR...');
    });

    test('all fields can coexist', () {
      const ctx = ChatRuntimeContext(
        boardId: 'b1',
        boardName: 'Test Board',
        panelId: 'p1',
        panelTitle: 'Panel',
        panelType: 'board.chat',
        availableBoardsSummary: 'summary',
        currentBoardPanelsSummary: 'panels',
        viewportScale: 2.0,
        boardSnapshotPath: '/snap.png',
        boardSnapshotBase64: 'base64data',
      );
      expect(ctx.boardId, 'b1');
      expect(ctx.boardName, 'Test Board');
      expect(ctx.panelId, 'p1');
      expect(ctx.panelTitle, 'Panel');
      expect(ctx.panelType, 'board.chat');
      expect(ctx.availableBoardsSummary, 'summary');
      expect(ctx.currentBoardPanelsSummary, 'panels');
      expect(ctx.viewportScale, 2.0);
      expect(ctx.boardSnapshotPath, '/snap.png');
      expect(ctx.boardSnapshotBase64, 'base64data');
    });
  });
}
