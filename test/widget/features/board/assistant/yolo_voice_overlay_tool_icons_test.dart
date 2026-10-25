import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/assistant/yolo_voice_overlay.dart';

void main() {
  testWidgets('tool log paints done, failed, and running state icons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(740, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: const Scaffold(
          body: Center(
            child: YoloVoiceOverlay(
              status: 'output',
              title: '',
              hint: '',
              transcript: '',
              response:
                  '✅ completed tool\n'
                  '❌ failed tool\n'
                  '⚙️ running tool\n'
                  'All tools finished.',
              animate: false,
              scale: 1,
              orbScale: 1,
              ovalWidth: 1,
              ovalHeight: 0.45,
              titleFontSize: 22,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('completed tool'), findsOneWidget);
    expect(find.textContaining('failed tool'), findsOneWidget);
    expect(find.textContaining('running tool'), findsOneWidget);
    expect(find.text('All tools finished.'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
