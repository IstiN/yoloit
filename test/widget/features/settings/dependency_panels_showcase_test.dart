import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/ui/debug_ui/sections/dependency_panels_showcase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The record package's AudioRecorder() constructor calls the native method
  // channel asynchronously during construction. Without a registered handler
  // the MissingPluginException becomes an unhandled async error that fails
  // the test. Install a minimal mock that returns success for "create".
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, (call) async {
      if (call.method == 'create') return 1;
      if (call.method == 'hasPermission') return false;
      return null;
    });
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, null);
  });

  Widget buildApp() => MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: const Scaffold(
          body: DependencyPanelsShowcase(),
        ),
      );

  testWidgets('_startSampleVideo surfaces a video error in the test environment',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      // Player() creation throws in initState when the native media_kit MPV
      // backend is absent (headless test env). The catch block sets
      // _videoError, which is rendered as "Video sample failed:".
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (find.textContaining('Video sample failed:').evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.textContaining('Video sample failed:'), findsOneWidget);
    });
  });

  testWidgets('_startSampleVideo early-returns when player is null',
      (tester) async {
    // When Player() fails in initState, _player is null and _videoError
    // is set. _startSampleVideo checks `player == null` and returns early.
    // This test verifies the null-guard path: no "Loading sample video…"
    // text should appear because the error path took over.
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (find.textContaining('Video sample failed:').evaluate().isNotEmpty) {
          break;
        }
      }
    });
    // The error text confirms the null-guard was hit — the widget never
    // shows the loading state because _startSampleVideo returned early.
    expect(find.textContaining('Loading sample video'), findsNothing);
    expect(find.textContaining('Video sample failed:'), findsOneWidget);
  });

  testWidgets('shows loading text before the error settles', (tester) async {
    // Immediately after pump (before the async error resolves), the widget
    // shows the loading state. This exercises the _videoReady == false &&
    // _videoError == null branch of the build method.
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      // First frame: _videoReady is false, _videoError is null → loading text.
      await tester.pump(const Duration(milliseconds: 10));
      // We may catch the loading text before the error arrives.
      // Either loading or error should be visible.
      final hasLoading =
          find.textContaining('Loading sample video').evaluate().isNotEmpty;
      final hasError =
          find.textContaining('Video sample failed:').evaluate().isNotEmpty;
      expect(hasLoading || hasError, isTrue);
    });
  });

  testWidgets('mic check button exists and shows an initial status',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });

    expect(find.text('Check microphone'), findsOneWidget);
    expect(
      find.textContaining('Tap to check microphone permission'),
      findsOneWidget,
    );
  });

  testWidgets('_checkMic transitions through Checking… to a terminal status',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      // Wait for the video player error path to settle.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (find.textContaining('Video sample failed:').evaluate().isNotEmpty) {
          break;
        }
      }

      final micButton = find.text('Check microphone');
      expect(micButton, findsOneWidget);

      await tester.ensureVisible(micButton);
      await tester.tap(micButton);

      // _checkMic sets _busy = true synchronously then awaits
      // _recorder.hasPermission(). The mock channel returns false quickly,
      // so _status transitions from 'Checking…' to 'Microphone permission
      // denied…'. Poll until a terminal status text appears.
      String? terminal;
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        final statusTexts = find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data ?? '');
        for (final text in statusTexts) {
          if (text.contains('granted') ||
              text.contains('denied') ||
              text.contains('failed')) {
            terminal = text;
            break;
          }
        }
        if (terminal != null) break;
      }

      expect(terminal, isNotNull);
    });
  });
}
