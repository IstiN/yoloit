import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/assistant/yolo_voice_overlay.dart';

// Fixed surface that matches the widget's own fixed 700×440 layout.
const _kSurface = Size(740, 480);

Widget _shell({
  required String status,
  String response = '',
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Center(
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'JetBrainsMono'),
          child: YoloVoiceOverlay(
            status: status,
            title: '',
            hint: '',
            transcript: '',
            response: response,
            animate: false,
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Golden tests — YOLO voice overlay', () {
    testGoldens('voice overlay trigger', (tester) async {
      await tester.pumpWidgetBuilder(
        _shell(status: 'idle'),
        surfaceSize: _kSurface,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'yolo_voice_overlay_trigger');
    });

    testGoldens('voice overlay listening', (tester) async {
      await tester.pumpWidgetBuilder(
        _shell(status: 'listening'),
        surfaceSize: _kSurface,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'yolo_voice_overlay_listening');
    });

    testGoldens('voice overlay sending audio', (tester) async {
      await tester.pumpWidgetBuilder(
        _shell(status: 'processing'),
        surfaceSize: _kSurface,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'yolo_voice_overlay_sending');
    });

    testGoldens('voice overlay thinking', (tester) async {
      await tester.pumpWidgetBuilder(
        _shell(status: 'thinking'),
        surfaceSize: _kSurface,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'yolo_voice_overlay_thinking');
    });

    testGoldens('voice overlay responding', (tester) async {
      await tester.pumpWidgetBuilder(
        _shell(
          status: 'responding',
          response:
              'The board "ChatTestBoard" has 20 panels. It looks like you are working on a voice assistant experience with beautiful morphing transitions.',
        ),
        surfaceSize: _kSurface,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'yolo_voice_overlay_responding');
    });

    testGoldens('single plectrum shape', (tester) async {
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            backgroundColor: const Color(0xFF020617),
            body: Center(
              child: SinglePlectrumPreview(
                color: const Color(0xFF3CE8FF),
                rotation: 0.0,
                size: 280,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/yolo_single_plectrum.png'),
      );
    });
  });
}
