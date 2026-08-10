import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_installer.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/ui/sections/about_section_vm.dart';

import '../../../../../helpers/fake_http_overrides.dart';
import '../../../../../helpers/fake_platform_installer.dart';

void main() {
  late FakePlatformInstaller installer;
  late FakeHttpOverrides httpOverrides;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    installer = FakePlatformInstaller(appVersion: '1.0.0');
    PlatformInstaller.setInstance(installer);
    httpOverrides = FakeHttpOverrides(
      responder: (uri, headers) =>
          githubReleaseResponse(200, tagName: 'v9.9.9'),
    );
    HttpOverrides.global = httpOverrides;
  });

  tearDown(() {
    HttpOverrides.global = null;
    PlatformInstaller.setInstance(MacosPlatformInstaller());
  });

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: const Scaffold(
          body: SingleChildScrollView(child: AboutSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapCheckNow(WidgetTester tester) async {
    await tester.tap(find.text('Check for Updates'));
    await tester.pumpAndSettle();
  }

  group('AboutSection._checkNow', () {
    testWidgets('shows the available update card for a newer release',
        (tester) async {
      await pumpSection(tester);
      await tapCheckNow(tester);

      expect(find.text('v9.9.9 is available!'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('shows up-to-date message for an older release',
        (tester) async {
      httpOverrides.responder =
          (uri, headers) => githubReleaseResponse(200, tagName: 'v0.5.0');
      await pumpSection(tester);
      await tapCheckNow(tester);

      expect(
        find.text('You are on the latest version (1.0.0).'),
        findsOneWidget,
      );
    });

    testWidgets('shows the skipped notice for a skipped version',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'updates.skippedVersion': '9.9.9',
      });
      await pumpSection(tester);
      await tapCheckNow(tester);

      expect(find.textContaining('was skipped'), findsOneWidget);
    });

    testWidgets('shows the error message when the check fails',
        (tester) async {
      httpOverrides.responder =
          (uri, headers) => const FakeHttpResponse(500, <int>[]);
      await pumpSection(tester);
      await tapCheckNow(tester);

      expect(
        find.textContaining('Could not reach GitHub releases API'),
        findsOneWidget,
      );
    });
  });

  group('AboutSection._installUpdate', () {
    Future<void> pumpWithUpdate(WidgetTester tester) async {
      await pumpSection(tester);
      await tapCheckNow(tester);
      expect(find.text('v9.9.9 is available!'), findsOneWidget);
    }

    testWidgets('downloads and installs via the platform installer',
        (tester) async {
      await pumpWithUpdate(tester);

      await tester.tap(find.text('Download'));
      // The progress bar is indeterminate once install finishes, so
      // pumpAndSettle would never settle — flush microtasks with pumps.
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }
      expect(installer.preparedTags, <String>['v9.9.9']);
      expect(installer.launchedTokens, <String>['tok-1']);
      expect(find.text('Ready to install'), findsOneWidget);
      expect(
        find.text('App will restart automatically after install.'),
        findsOneWidget,
      );
    });

    testWidgets('shows a snackbar when the install fails', (tester) async {
      installer.errorOnPrepare = StateError('network boom');
      await pumpWithUpdate(tester);

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(installer.launchedTokens, isEmpty);
      expect(find.textContaining('Update failed:'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);

      // Let the snackbar auto-dismiss so no timer is left pending.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });
}
