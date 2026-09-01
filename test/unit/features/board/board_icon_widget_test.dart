import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_icon.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_icon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    BoardIcon.debugResolverOverride = null;
  });

  tearDown(() {
    BoardIcon.debugResolverOverride = null;
  });

  Widget wrap(BoardDocument board) {
    return MaterialApp(
      home: Scaffold(body: Center(child: BoardIcon(board: board, size: 24))),
    );
  }

  testWidgets('renders letter avatar fallback when no icon resolves', (
    tester,
  ) async {
    BoardIcon.debugResolverOverride = (_) => null;
    await tester.pumpWidget(wrap(const BoardDocument(id: 'b1', name: 'yoloit')));
    expect(find.text('Y'), findsOneWidget);
  });

  testWidgets('renders emoji icon', (tester) async {
    BoardIcon.debugResolverOverride =
        (_) => const BoardIconSpec(kind: BoardIconSpec.kindEmoji, value: '🚀');
    await tester.pumpWidget(wrap(const BoardDocument(id: 'b1', name: 'Board')));
    expect(find.text('🚀'), findsOneWidget);
  });

  testWidgets('renders fallback for missing image file', (tester) async {
    BoardIcon.debugResolverOverride =
        (_) => const BoardIconSpec(
          kind: BoardIconSpec.kindFile,
          value: '/definitely/missing/icon.png',
        );
    await tester.pumpWidget(wrap(const BoardDocument(id: 'b1', name: 'Board')));
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('renders builtin preset without errors', (tester) async {
    BoardIcon.debugResolverOverride =
        (_) => const BoardIconSpec(
          kind: BoardIconSpec.kindBuiltin,
          value: 'yoloit',
        );
    await tester.pumpWidget(wrap(const BoardDocument(id: 'b1', name: 'Board')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
