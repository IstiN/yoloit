import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/widgets/session_history/session_history_list_tile.dart';

void main() {
  group('SessionHistoryListTile', () {
    final entry = ChatSessionEntry(
      id: 'session-1',
      sessionName: 'Test Session',
      provider: 'copilot',
      model: 'gpt-4',
      workingDir: '/tmp',
      createdAt: DateTime(2024, 6, 1, 12, 0),
      lastMessageAt: DateTime(2024, 6, 1, 12, 30),
      messageCount: 5,
    );

    Widget buildTile({
      required ChatSessionEntry entry,
      required bool isCurrent,
      VoidCallback? onTap,
      Widget? trailing,
      String fallbackName = 'Unnamed session',
      bool showModel = true,
      bool borderNonCurrent = false,
    }) {
      return MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: SessionHistoryListTile(
            entry: entry,
            isCurrent: isCurrent,
            onTap: onTap,
            trailing: trailing,
            fallbackName: fallbackName,
            showModel: showModel,
            borderNonCurrent: borderNonCurrent,
          ),
        ),
      );
    }

    testWidgets('renders session name and subtitle with model', (tester) async {
      await tester.pumpWidget(buildTile(entry: entry, isCurrent: false));

      expect(find.text('Test Session'), findsOneWidget);
      expect(find.text('copilot • gpt-4 • 5 msgs'), findsOneWidget);
    });

    testWidgets('renders subtitle without model when showModel is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTile(entry: entry, isCurrent: false, showModel: false),
      );

      expect(find.text('copilot • 5 msgs'), findsOneWidget);
    });

    testWidgets('uses fallback name when session name is empty', (tester) async {
      final emptyEntry = ChatSessionEntry(
        id: 'session-2',
        sessionName: '',
        provider: 'openai',
        model: 'gpt-3',
        workingDir: '/tmp',
        createdAt: DateTime(2024, 6, 1),
        messageCount: 0,
      );
      await tester.pumpWidget(
        buildTile(entry: emptyEntry, isCurrent: false),
      );

      expect(find.text('Unnamed session'), findsOneWidget);
    });

    testWidgets('applies custom fallback name', (tester) async {
      final emptyEntry = ChatSessionEntry(
        id: 'session-3',
        sessionName: '',
        provider: 'openai',
        model: 'gpt-3',
        workingDir: '/tmp',
        createdAt: DateTime(2024, 6, 1),
        messageCount: 0,
      );
      await tester.pumpWidget(
        buildTile(
          entry: emptyEntry,
          isCurrent: false,
          fallbackName: 'Custom Fallback',
        ),
      );

      expect(find.text('Custom Fallback'), findsOneWidget);
    });

    testWidgets('renders trailing widget', (tester) async {
      await tester.pumpWidget(
        buildTile(
          entry: entry,
          isCurrent: false,
          trailing: const Icon(Icons.delete),
        ),
      );

      expect(find.byIcon(Icons.delete), findsOneWidget);
    });

    testWidgets('calls onTap when tapped and not current', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        buildTile(
          entry: entry,
          isCurrent: false,
          onTap: () => tapped = true,
        ),
      );

      await tester.tap(find.text('Test Session'));
      expect(tapped, isTrue);
    });

    testWidgets('does not call onTap when current', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        buildTile(
          entry: entry,
          isCurrent: true,
          onTap: () => tapped = true,
        ),
      );

      await tester.tap(find.text('Test Session'));
      expect(tapped, isFalse);
    });

    testWidgets('renders without GestureDetector when onTap is null', (
      tester,
    ) async {
      await tester.pumpWidget(buildTile(entry: entry, isCurrent: false));

      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('renders with GestureDetector when onTap is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTile(entry: entry, isCurrent: false, onTap: () {}),
      );

      expect(find.byType(GestureDetector), findsOneWidget);
    });

    testWidgets('applies border for non-current when borderNonCurrent is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTile(
          entry: entry,
          isCurrent: false,
          borderNonCurrent: true,
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
    });

    testWidgets('does not apply border for non-current by default', (
      tester,
    ) async {
      await tester.pumpWidget(buildTile(entry: entry, isCurrent: false));

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNull);
    });
  });
}
