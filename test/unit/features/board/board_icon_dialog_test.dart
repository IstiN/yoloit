import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_icon.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/services/board_icon_resolver.dart';
import 'package:yoloit/features/board/ui/dialogs/board_icon_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('board_icon_dialog_test');
    BoardIconResolver.instance.invalidate();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
    BoardIconResolver.instance.invalidate();
  });

  File createFile(String relative) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$relative');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(const [0x89, 0x50, 0x4E, 0x47]);
    return file;
  }

  Widget buildDialog(BoardDocument board) {
    return MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(body: BoardIconDialog(board: board)),
    );
  }

  testWidgets('shows folder candidates found by the resolver', (tester) async {
    final icon = createFile('assets/icon.png');
    final board = BoardDocument(
      id: 'b',
      name: 'Board',
      metadata: {'defaultFolder': tempDir.path},
    );
    await tester.pumpWidget(buildDialog(board));
    await tester.pumpAndSettle();

    expect(find.textContaining('Found in'), findsOneWidget);
    expect(
      find.byKey(Key('board-icon-candidate-${icon.path}')),
      findsOneWidget,
    );
  });

  testWidgets('hides folder candidates section when folder has none', (
    tester,
  ) async {
    final board = BoardDocument(
      id: 'b',
      name: 'Board',
      metadata: {'defaultFolder': tempDir.path},
    );
    await tester.pumpWidget(buildDialog(board));
    await tester.pumpAndSettle();

    expect(find.textContaining('Found in'), findsNothing);
    expect(find.text('Presets'), findsOneWidget);
  });

  testWidgets('selecting a folder candidate marks it and updates preview', (
    tester,
  ) async {
    final icon = createFile('assets/icon.png');
    final board = BoardDocument(
      id: 'b',
      name: 'Board',
      metadata: {'defaultFolder': tempDir.path},
    );
    await tester.pumpWidget(buildDialog(board));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('board-icon-candidate-${icon.path}')));
    await tester.pump();

    expect(find.text('Image: ${icon.path}'), findsOneWidget);
  });

  testWidgets('emoji picker opens and selects an emoji', (tester) async {
    const board = BoardDocument(id: 'b', name: 'Board');
    await tester.pumpWidget(buildDialog(board));
    await tester.pumpAndSettle();

    // Grid hidden initially.
    expect(find.text('🚀'), findsNothing);

    await tester.tap(find.byKey(const Key('board-icon-emoji-toggle')));
    await tester.pumpAndSettle();
    // Grid tile + text field hint both render the emoji.
    final gridEmoji = find.descendant(
      of: find.byType(Wrap),
      matching: find.text('🚀'),
    );
    expect(gridEmoji, findsOneWidget);

    await tester.tap(gridEmoji);
    await tester.pump();
    expect(find.text('Emoji 🚀'), findsOneWidget);
  });

  testWidgets('auto-detect resets selection', (tester) async {
    const board = BoardDocument(
      id: 'b',
      name: 'Board',
      metadata: {
        'icon': {'kind': 'emoji', 'value': '🚀'},
      },
    );
    await tester.pumpWidget(buildDialog(board));
    await tester.pumpAndSettle();
    expect(find.text('Emoji 🚀'), findsOneWidget);

    await tester.tap(find.text('Auto-detect'));
    await tester.pump();
    expect(find.text('Auto-detect from default folder'), findsOneWidget);
  });
}
