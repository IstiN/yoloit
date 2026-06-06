import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/ui/sections/toggle_row.dart';

void main() {
  group('ToggleRow', () {
    testWidgets('renders title and subtitle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            body: ToggleRow(
              icon: Icons.dark_mode,
              title: 'Dark Mode',
              subtitle: 'Enable dark theme',
              value: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Dark Mode'), findsOneWidget);
      expect(find.text('Enable dark theme'), findsOneWidget);
    });

    testWidgets('renders icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            body: ToggleRow(
              icon: Icons.notifications,
              title: 'Notifications',
              subtitle: 'Push alerts',
              value: false,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.notifications), findsOneWidget);
    });

    testWidgets('switch reflects value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            body: ToggleRow(
              icon: Icons.toggle_on,
              title: 'Feature',
              subtitle: 'A feature',
              value: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isTrue);
    });

    testWidgets('calls onChanged when toggled', (tester) async {
      bool? newValue;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            body: ToggleRow(
              icon: Icons.toggle_on,
              title: 'Feature',
              subtitle: 'A feature',
              value: false,
              onChanged: (v) => newValue = v,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      expect(newValue, isTrue);
    });

    testWidgets('disables switch when enabled is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            body: ToggleRow(
              icon: Icons.block,
              title: 'Blocked',
              subtitle: 'Cannot change',
              value: true,
              enabled: false,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.onChanged, isNull);
    });

    testWidgets('switch value is false when enabled is false regardless of value', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            body: ToggleRow(
              icon: Icons.block,
              title: 'Blocked',
              subtitle: 'Cannot change',
              value: true,
              enabled: false,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isFalse);
    });

    testWidgets('applies correct padding', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            body: ToggleRow(
              icon: Icons.padding,
              title: 'Padded',
              subtitle: 'Check padding',
              value: false,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final padding = tester.widget<Padding>(find.byType(Padding));
      expect(
        padding.padding,
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
    });
  });
}
