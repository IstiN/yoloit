import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/widgets/session_history/session_history_list_tile.dart';
import 'package:yoloit/features/board/chat/widgets/session_history/session_history_list_view.dart';

void main() {
  group('SessionHistoryListView', () {
    final entries = <ChatSessionEntry>[
      ChatSessionEntry(
        id: 'panel-1',
        sessionName: 'Session One',
        provider: 'copilot',
        model: 'gpt-4',
        workingDir: '/tmp',
        createdAt: DateTime(2024, 6, 1),
        lastMessageAt: DateTime(2024, 6, 1, 12),
        messageCount: 3,
      ),
      ChatSessionEntry(
        id: 'panel-2',
        sessionName: 'Session Two',
        provider: 'openai',
        model: 'gpt-3',
        workingDir: '/tmp',
        createdAt: DateTime(2024, 6, 2),
        lastMessageAt: DateTime(2024, 6, 2, 12),
        messageCount: 7,
      ),
    ];

    Widget buildView({
      required Future<List<ChatSessionEntry>> future,
      String currentPanelId = 'panel-1',
      Widget Function(ChatSessionEntry, bool)? trailingActions,
      void Function(ChatSessionEntry)? onItemTap,
    }) {
      return MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: SessionHistoryListView(
            future: future,
            currentPanelId: currentPanelId,
            trailingActions: trailingActions,
            onItemTap: onItemTap,
          ),
        ),
      );
    }

    testWidgets('shows loading indicator while waiting', (tester) async {
      final completer = Completer<List<ChatSessionEntry>>();
      await tester.pumpWidget(buildView(future: completer.future));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      completer.complete(entries);
      await tester.pump();
    });

    testWidgets('shows empty message when no sessions', (tester) async {
      await tester.pumpWidget(buildView(future: Future.value([])));
      await tester.pump();

      expect(find.textContaining('No sessions yet'), findsOneWidget);
    });

    testWidgets('renders list of sessions', (tester) async {
      await tester.pumpWidget(buildView(future: Future.value(entries)));
      await tester.pump();

      expect(find.text('Session One'), findsOneWidget);
      expect(find.text('Session Two'), findsOneWidget);
    });

    testWidgets('marks current session correctly', (tester) async {
      await tester.pumpWidget(
        buildView(future: Future.value(entries), currentPanelId: 'panel-1'),
      );
      await tester.pump();

      final listTiles = find.byType(SessionHistoryListTile);
      expect(listTiles, findsNWidgets(2));
    });

    testWidgets('calls onItemTap with correct entry', (tester) async {
      ChatSessionEntry? tappedEntry;
      await tester.pumpWidget(
        buildView(
          future: Future.value(entries),
          currentPanelId: 'panel-1',
          onItemTap: (entry) => tappedEntry = entry,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Session Two'));
      expect(tappedEntry, isNotNull);
      expect(tappedEntry!.id, 'panel-2');
    });

    testWidgets('renders trailing actions', (tester) async {
      await tester.pumpWidget(
        buildView(
          future: Future.value(entries),
          trailingActions: (entry, isCurrent) => Icon(
            isCurrent ? Icons.star : Icons.star_border,
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsOneWidget);
    });
  });
}
