import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_installer.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/updates/data/update_service.dart';
import 'package:yoloit/features/updates/ui/update_banner.dart';

import '../../../helpers/fake_platform_installer.dart';

void main() {
  const info = UpdateInfo(
    version: '9.9.9',
    tagName: 'v9.9.9',
    releaseUrl: 'https://example.test/release/v9.9.9',
    releaseNotes: 'notes',
  );

  late FakePlatformInstaller installer;

  setUp(() {
    installer = FakePlatformInstaller();
    PlatformInstaller.setInstance(installer);
  });

  tearDown(() {
    PlatformInstaller.setInstance(MacosPlatformInstaller());
  });

  Widget app({
    required AutoUpdatePhase phase,
    double? progress,
    String status = '',
    String? token,
    VoidCallback? onDismiss,
  }) {
    return MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        body: AutoUpdateBanner(
          info: info,
          phase: phase,
          progress: progress,
          status: status,
          launchToken: token,
          onDismiss: onDismiss ?? () {},
        ),
      ),
    );
  }

  /// Unmounts the banner so its countdown timer is cancelled.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  group('AutoUpdateBanner._label', () {
    testWidgets('downloading shows tag and percentage', (tester) async {
      await tester.pumpWidget(
        app(phase: AutoUpdatePhase.downloading, progress: 0.42),
      );
      expect(find.text('Downloading YoLoIT v9.9.9 42%…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('downloading without progress hides bar and percentage',
        (tester) async {
      await tester.pumpWidget(app(phase: AutoUpdatePhase.downloading));
      expect(find.text('Downloading YoLoIT v9.9.9…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('installing shows the current status and indeterminate bar',
        (tester) async {
      await tester.pumpWidget(
        app(phase: AutoUpdatePhase.installing, status: 'Extracting…'),
      );
      expect(find.text('Extracting…'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, isNull);
    });

    testWidgets('installing falls back to a default label', (tester) async {
      await tester.pumpWidget(app(phase: AutoUpdatePhase.installing));
      expect(find.text('Installing…'), findsOneWidget);
    });

    testWidgets('ready shows the countdown label and action buttons',
        (tester) async {
      await tester.pumpWidget(app(phase: AutoUpdatePhase.ready, token: 'tok'));
      expect(
        find.text('YoLoIT v9.9.9 ready — restarting in 5s…'),
        findsOneWidget,
      );
      expect(find.text('Restart Now'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('error shows the failure message', (tester) async {
      await tester.pumpWidget(
        app(phase: AutoUpdatePhase.error, status: 'boom'),
      );
      expect(find.text('Update failed: boom'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });
  });

  group('AutoUpdateBanner actions', () {
    testWidgets('Later cancels the countdown and dismisses', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        app(
          phase: AutoUpdatePhase.ready,
          token: 'tok',
          onDismiss: () => dismissed = true,
        ),
      );

      await tester.tap(find.text('Later'));
      await tester.pump();

      expect(dismissed, isTrue);
      // No restart was triggered and the timer is gone.
      expect(installer.launchedTokens, isEmpty);
      await tester.pump(const Duration(seconds: 10));
      expect(installer.launchedTokens, isEmpty);
      await unmount(tester);
    });

    testWidgets('Restart Now applies the update immediately', (tester) async {
      await tester.pumpWidget(app(phase: AutoUpdatePhase.ready, token: 'tok'));

      await tester.tap(find.text('Restart Now'));
      await tester.pump();

      expect(installer.launchedTokens, <String>['tok']);
      await unmount(tester);
    });

    testWidgets('countdown reaches zero and auto-restarts', (tester) async {
      await tester.pumpWidget(app(phase: AutoUpdatePhase.ready, token: 'tok'));

      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('YoLoIT v9.9.9 ready — restarting in 4s…'),
        findsOneWidget,
      );

      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(installer.launchedTokens, <String>['tok']);
      await unmount(tester);
    });

    testWidgets('transitioning to ready starts the countdown', (tester) async {
      await tester.pumpWidget(
        app(phase: AutoUpdatePhase.downloading, progress: 1.0),
      );
      await tester.pumpWidget(app(phase: AutoUpdatePhase.ready, token: 'tok'));

      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('YoLoIT v9.9.9 ready — restarting in 4s…'),
        findsOneWidget,
      );

      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(installer.launchedTokens, <String>['tok']);
      await unmount(tester);
    });

    testWidgets('error close button dismisses the banner', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        app(
          phase: AutoUpdatePhase.error,
          status: 'boom',
          onDismiss: () => dismissed = true,
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(dismissed, isTrue);
    });
  });
}
