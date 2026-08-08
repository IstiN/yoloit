import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/widgets/session_history_picker_dialog.dart';

void main() {
  group('SessionHistoryPickerDialog', () {
    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: const SessionHistoryPickerDialog(
            title: 'History',
            currentPanelId: 'panel-1',
          ),
        ),
      );

      expect(find.text('History'), findsOneWidget);
    });

    testWidgets('renders with currentPanelId', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: const SessionHistoryPickerDialog(
            title: 'Test History',
            currentPanelId: 'panel-1',
          ),
        ),
      );

      expect(find.text('Test History'), findsOneWidget);
      expect(find.byType(SessionHistoryPickerDialog), findsOneWidget);
    });

    testWidgets('uses custom dimensions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: const SessionHistoryPickerDialog(
            title: 'History',
            currentPanelId: 'panel-1',
            width: 500,
            height: 600,
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(
        find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 500 && w.height == 600,
        ),
      );
      expect(sizedBox.width, 500);
      expect(sizedBox.height, 600);
    });

    testWidgets('close button is present', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: const SessionHistoryPickerDialog(
            title: 'History',
            currentPanelId: 'panel-1',
          ),
        ),
      );

      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('onRestore callback has correct signature', (tester) async {
      ChatSessionEntry? restoredEntry;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: SessionHistoryPickerDialog(
            title: 'History',
            currentPanelId: 'panel-1',
            onRestore: (entry, msgs) => restoredEntry = entry,
          ),
        ),
      );

      expect(find.byType(SessionHistoryPickerDialog), findsOneWidget);
      expect(restoredEntry, isNull);
    });

    testWidgets('renders history icon in title', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: const SessionHistoryPickerDialog(
            title: 'History',
            currentPanelId: 'panel-1',
          ),
        ),
      );

      expect(find.byIcon(Icons.history), findsOneWidget);
    });
  });
}
