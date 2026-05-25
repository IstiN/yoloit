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
            scale: 1.0,
            orbScale: 1.0,
            ovalWidth: 1.0,
            ovalHeight: 0.45,
            titleFontSize: 22,
          ),
        ),
      ),
    ),
  );
}

/// A stateful wrapper that lets tests drive status/response changes.
class _OverlayDriver extends StatefulWidget {
  const _OverlayDriver({required this.notifier});
  final ValueNotifier<({String status, String response})> notifier;

  @override
  State<_OverlayDriver> createState() => _OverlayDriverState();
}

class _OverlayDriverState extends State<_OverlayDriver> {
  late String _status;
  late String _response;

  @override
  void initState() {
    super.initState();
    _status = widget.notifier.value.status;
    _response = widget.notifier.value.response;
    widget.notifier.addListener(_onNotifier);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onNotifier);
    super.dispose();
  }

  void _onNotifier() {
    setState(() {
      _status = widget.notifier.value.status;
      _response = widget.notifier.value.response;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        backgroundColor: const Color(0xFF020617),
        body: Center(
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'JetBrainsMono'),
            child: YoloVoiceOverlay(
              status: _status,
              title: '',
              hint: '',
              transcript: '',
              response: _response,
              animate: false,
              scale: 1.0,
              orbScale: 1.0,
              ovalWidth: 1.0,
              ovalHeight: 0.45,
              titleFontSize: 22,
            ),
          ),
        ),
      ),
    );
  }
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

    // ── Tool-call flow simulation ────────────────────────────────────────────
    // Simulates the real app sequence: user says "Покажи список покупок.",
    // LLM calls panel:focus + panel tools, then returns text.

    testGoldens('tool-call flow: responding with tool running', (tester) async {
      await tester.pumpWidgetBuilder(
        _shell(
          status: 'responding',
          response: '### Tools\n- ⏳ running: panel:focus music \'Список покупок\'',
        ),
        surfaceSize: _kSurface,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'yolo_voice_overlay_tool_running');
    });

    testGoldens('tool-call flow: responding two tools running', (tester) async {
      await tester.pumpWidgetBuilder(
        _shell(
          status: 'responding',
          response:
              '### Tools\n'
              '- ✅ panel:focus music \'Список покупок\'\n'
              '- ⏳ running: panel music \'Список покупок\'',
        ),
        surfaceSize: _kSurface,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'yolo_voice_overlay_tool_two_running');
    });

    testGoldens('tool-call flow: responding with text and tools', (tester) async {
      await tester.pumpWidgetBuilder(
        _shell(
          status: 'responding',
          response:
              'Вот ваш список покупок:\n\n'
              '### Tools\n'
              '- ✅ panel:focus music \'Список покупок\'\n'
              '- ✅ panel music \'Список покупок\'',
        ),
        surfaceSize: _kSurface,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'yolo_voice_overlay_tool_with_text');
    });

    // Verifies fix: processing → responding transition must bypass _pendingTransition.
    // Uses _OverlayDriver to drive status changes on the SAME widget instance.
    testGoldens(
      'tool-call flow: processing → responding bypasses pendingTransition',
      (tester) async {
        final notifier = ValueNotifier<({String status, String response})>((
          status: 'idle',
          response: '',
        ));
        addTearDown(notifier.dispose);

        await tester.pumpWidgetBuilder(
          _OverlayDriver(notifier: notifier),
          surfaceSize: _kSurface,
        );

        // Step 1: idle → processing (triggers sequential idle→listening→processing)
        notifier.value = (status: 'processing', response: '');
        await tester.pump(); // first postFrame: idle → listening
        await tester.pump(); // second postFrame: listening → processing
        await tester.pump(const Duration(milliseconds: 100));
        // At this point _shown=processing, _pendingTransition=false,
        // elapsed≈100ms (< processing.minMs=600ms).
        // Capture processing state.
        await screenMatchesGolden(
          tester,
          'yolo_voice_overlay_flow_processing',
        );

        // Step 2: tool call fires — status flips to responding BEFORE processing.minMs.
        // Old code: if the pending timer was set, this would be blocked.
        // New code: responding bypass fires first, cancels any pending.
        notifier.value = (
          status: 'responding',
          response: '### Tools\n- ⏳ running: panel:focus music \'Список покупок\'',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        // Must show responding, not processing.
        await screenMatchesGolden(
          tester,
          'yolo_voice_overlay_flow_tool_call_start',
        );

        // Step 3: first tool done, second running
        notifier.value = (
          status: 'responding',
          response:
              '### Tools\n'
              '- ✅ panel:focus music \'Список покупок\'\n'
              '- ⏳ running: panel music \'Список покупок\'',
        );
        await tester.pump(const Duration(milliseconds: 200));
        await screenMatchesGolden(
          tester,
          'yolo_voice_overlay_flow_tool_call_progress',
        );

        // Step 4: all tools done, text response appears
        notifier.value = (
          status: 'responding',
          response:
              'Вот ваш список покупок:\n\n'
              '### Tools\n'
              '- ✅ panel:focus music \'Список покупок\'\n'
              '- ✅ panel music \'Список покупок\'',
        );
        await tester.pump(const Duration(milliseconds: 200));
        await screenMatchesGolden(
          tester,
          'yolo_voice_overlay_flow_final_response',
        );
      },
    );
  });
}
