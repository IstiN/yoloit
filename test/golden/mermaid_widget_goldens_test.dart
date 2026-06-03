import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_widgets.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

const _darkBg = Color(0xFF0D1117);

/// Minimal 1×1 red PNG (69 bytes).
final _tinyPngRed = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x03, 0x01, 0x01, 0x00, 0xC9, 0xFE, 0x92, 0xEF, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Minimal 1×1 blue PNG (69 bytes).
final _tinyPngBlue = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x60, 0xF8, 0x0F,
  0x00, 0x01, 0x03, 0x01, 0x00, 0x08, 0x89, 0xC2, 0xEC, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Future<void> _pumpWidget(
  WidgetTester tester,
  Widget child, {
  double width = 460,
  double height = 380,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
  addTearDown(() => tester.view.resetDevicePixelRatio());

  final colors = AppColorScheme.fromAccent(Colors.deepPurple);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _darkBg,
        extensions: [colors],
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _golden(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(Scaffold),
    matchesGoldenFile('goldens/$name.png'),
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('MermaidPreviewFrame', () {
    testWidgets('loading state', (tester) async {
      final colors = AppColorScheme.fromAccent(Colors.deepPurple);
      await _pumpWidget(
        tester,
        MermaidPreviewFrame(
          height: 260,
          colors: colors,
          backgroundColor: colors.surface,
          child: const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Rendering diagram…', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      );
      await _golden(tester, 'mermaid_preview_frame_loading');
    });

    testWidgets('error state', (tester) async {
      final colors = AppColorScheme.fromAccent(Colors.deepPurple);
      await _pumpWidget(
        tester,
        MermaidPreviewFrame(
          height: 260,
          colors: colors,
          borderColor: colors.accentRed.withValues(alpha: 0.3),
          backgroundColor: colors.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Mermaid error: Syntax error in graph',
              style: TextStyle(fontSize: 12, color: colors.accentRed),
            ),
          ),
        ),
      );
      await _golden(tester, 'mermaid_preview_frame_error');
    });

    testWidgets('rendered state', (tester) async {
      final colors = AppColorScheme.fromAccent(Colors.deepPurple);
      await _pumpWidget(
        tester,
        MermaidPreviewFrame(
          height: 260,
          colors: colors,
          backgroundColor: colors.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: Image.memory(_tinyPngBlue, fit: BoxFit.contain),
            ),
          ),
        ),
      );
      await _golden(tester, 'mermaid_preview_frame_rendered');
    });
  });

  group('MermaidExpandedDialog', () {
    testWidgets('displays zoomable diagram', (tester) async {
      final colors = AppColorScheme.fromAccent(Colors.deepPurple);

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: _darkBg,
            extensions: [colors],
          ),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder:
                            (_) => MermaidExpandedDialog(
                              initialPng: _tinyPngRed,
                              svg: null,
                              targetWidth: 900,
                              aspectRatio: 1.0,
                              colors: colors,
                              backgroundColor: colors.background,
                              backgroundColorHex: '#0D1117',
                            ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await _golden(tester, 'mermaid_expanded_dialog');
    });
  });

  group('MermaidDiagram', () {
    testWidgets('loading state (renderer null)', (tester) async {
      final colors = AppColorScheme.fromAccent(Colors.deepPurple);
      late final MermaidThemeOptions theme;

      tester.view.physicalSize = const Size(460, 380);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: _darkBg,
            extensions: [colors],
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                theme = buildMermaidThemeOptions(context, colors);
                return Center(
                  child: MermaidDiagram(
                    code: 'flowchart TD; A --> B',
                    renderer: null,
                    colors: colors,
                    mermaidTheme: theme,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await _golden(tester, 'mermaid_diagram_loading');
    });
  });
}
