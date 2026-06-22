import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/chat/widgets/cli_tools_picker_dialog.dart';

void main() {
  group('CliToolsPickerDialog', () {
    testWidgets('renders title and description', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: CliToolsPickerDialog(
            initialDisabled: const {},
            onPersist: (_) {},
            title: 'Custom Title',
            description: 'Custom Description',
          ),
        ),
      );

      expect(find.text('Custom Title'), findsOneWidget);
      expect(find.text('Custom Description'), findsOneWidget);
    });

    testWidgets('renders default title when not provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: CliToolsPickerDialog(
            initialDisabled: const {},
            onPersist: (_) {},
          ),
        ),
      );

      expect(find.text('YoLo tools'), findsOneWidget);
    });

    testWidgets('shows action buttons by default', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: CliToolsPickerDialog(
            initialDisabled: const {},
            onPersist: (_) {},
          ),
        ),
      );

      expect(find.text('Enable all'), findsOneWidget);
      expect(find.text('Disable all'), findsOneWidget);
      expect(find.text('Disable destructive'), findsOneWidget);
    });

    testWidgets('hides action buttons when flags are false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: CliToolsPickerDialog(
            initialDisabled: const {},
            onPersist: (_) {},
            showEnableAll: false,
            showDisableAll: false,
            showDisableDestructive: false,
          ),
        ),
      );

      expect(find.text('Enable all'), findsNothing);
      expect(find.text('Disable all'), findsNothing);
      expect(find.text('Disable destructive'), findsNothing);
    });

    testWidgets('displays enabled count when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: CliToolsPickerDialog(
            initialDisabled: const {},
            onPersist: (_) {},
            enabledCount: 5,
          ),
        ),
      );

      expect(find.textContaining('5/'), findsOneWidget);
    });

    testWidgets('calls onPersist when toggling a tool', (tester) async {
      Set<String>? persisted;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: CliToolsPickerDialog(
            initialDisabled: const {},
            onPersist: (disabled) => persisted = disabled,
          ),
        ),
      );

      // Find and tap the first checkbox
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(persisted, isNotNull);
    });

    testWidgets('filters tools by search query', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: CliToolsPickerDialog(
            initialDisabled: const {},
            onPersist: (_) {},
          ),
        ),
      );

      final initialCheckboxes = tester.widgetList(find.byType(Checkbox)).length;
      expect(initialCheckboxes, greaterThan(0));

      await tester.enterText(find.byType(TextField), 'xyz_no_match');
      await tester.pump();

      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('No tools match your search'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(
        tester.widgetList(find.byType(Checkbox)).length,
        initialCheckboxes,
      );
    });
  });
}
