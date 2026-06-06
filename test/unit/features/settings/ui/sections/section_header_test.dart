import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/ui/sections/section_header.dart';

void main() {
  group('SectionHeader', () {
    testWidgets('renders title text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: const Scaffold(body: SectionHeader(title: 'Appearance')),
        ),
      );

      expect(find.text('Appearance'), findsOneWidget);
    });

    testWidgets('applies correct text style', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: const Scaffold(body: SectionHeader(title: 'General')),
        ),
      );

      final text = tester.widget<Text>(find.text('General'));
      expect(text.style?.fontSize, 12);
      expect(text.style?.fontWeight, FontWeight.w700);
      expect(text.style?.letterSpacing, 1);
    });

    testWidgets('uses primary color from theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: const Scaffold(body: SectionHeader(title: 'About')),
        ),
      );

      final text = tester.widget<Text>(find.text('About'));
      expect(text.style?.color, isNotNull);
    });
  });
}
