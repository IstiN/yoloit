import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/chat_header_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ChatHeaderMenu', () {
    const panel = BoardPanelInstance(
      id: 'chat-1',
      type: 'board.chat',
      title: 'AI Chat',
      bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 500),
      state: {'config': <String, dynamic>{}},
    );

    Widget buildMenu({
      VoidCallback? onEditColor,
      ValueChanged<Map<String, dynamic>>? onUpdateState,
    }) {
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      return MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: ChatHeaderMenu(
              panel: panel,
              onEditColor: onEditColor ?? () {},
              onUpdateState: onUpdateState,
            ),
          ),
        ),
      );
    }

    testWidgets('renders popup menu button', (tester) async {
      await tester.pumpWidget(buildMenu());
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    });

    testWidgets('menu contains all items', (tester) async {
      await tester.pumpWidget(buildMenu());
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();

      expect(find.text('Rename session'), findsOneWidget);
      expect(find.text('CLI settings'), findsOneWidget);
      expect(find.text('Session history'), findsOneWidget);
      expect(find.text('Change color'), findsOneWidget);
    });

    testWidgets('tapping Change color calls onEditColor', (tester) async {
      var called = false;
      await tester.pumpWidget(
        buildMenu(onEditColor: () => called = true),
      );
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change color'));
      await tester.pumpAndSettle();
      expect(called, isTrue);
    });

    testWidgets('tapping Rename session shows dialog', (tester) async {
      await tester.pumpWidget(buildMenu());
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename session'));
      await tester.pumpAndSettle();

      expect(find.text('Rename session'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('rename dialog cancel closes', (tester) async {
      await tester.pumpWidget(buildMenu());
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename session'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Rename session'), findsNothing);
    });

    testWidgets('rename dialog applies and calls onUpdateState', (tester) async {
      Map<String, dynamic>? updated;
      await tester.pumpWidget(
        buildMenu(
          onUpdateState: (v) => updated = v,
        ),
      );
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename session'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'New Session');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.text('Rename session'), findsNothing);
      expect(updated, isNotNull);
      expect(
        (updated!['config'] as Map<String, dynamic>)['sessionName'],
        'New Session',
      );
    });

    testWidgets('tapping Session history shows dialog', (tester) async {
      await tester.pumpWidget(buildMenu());
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Session history'));
      await tester.pumpAndSettle();

      expect(find.text('Session history'), findsOneWidget);
    });

    testWidgets('tapping CLI settings shows dialog', (tester) async {
      await tester.pumpWidget(buildMenu());
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CLI settings'));
      await tester.pumpAndSettle();

      expect(find.text('CLI Settings'), findsOneWidget);
      expect(find.text('Agent Mode'), findsOneWidget);
      expect(find.text('Reasoning effort'), findsOneWidget);
    });

    testWidgets('CLI settings dialog cancel closes', (tester) async {
      await tester.pumpWidget(buildMenu());
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CLI settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('CLI Settings'), findsNothing);
    });

    testWidgets('CLI settings dialog save calls onUpdateState', (tester) async {
      Map<String, dynamic>? updated;
      await tester.pumpWidget(
        buildMenu(onUpdateState: (v) => updated = v),
      );
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CLI settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('CLI Settings'), findsNothing);
      expect(updated, isNotNull);
    });
  });
}
