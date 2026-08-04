import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/settings/data/setup_check_service.dart';
import 'package:yoloit/features/settings/ui/setup_guide_page_vm.dart';

/// One available required dep, one missing required dep with an install
/// action, one missing optional dep without one; one available agent and one
/// missing agent with an install action.
const _fakeResult = SetupCheckResult(
  deps: [
    DependencyStatus(
      id: 'git',
      name: 'git',
      description: 'Version control',
      installHint: 'brew install git',
      isAvailable: true,
      version: '2.49.0',
      installAction: InstallAction(executable: 'brew', args: ['install', 'git']),
    ),
    DependencyStatus(
      id: 'tmux',
      name: 'tmux',
      description: 'Terminal multiplexer',
      installHint: 'brew install tmux',
      isAvailable: false,
      installAction: InstallAction(executable: 'brew', args: ['install', 'tmux']),
    ),
    DependencyStatus(
      id: 'node',
      name: 'Node.js',
      description: 'Required for npm-based AI agents',
      installHint: 'brew install node',
      isAvailable: false,
      isRequired: false,
    ),
  ],
  agents: [
    DependencyStatus(
      id: 'copilot',
      name: 'GitHub Copilot',
      description: 'AI coding agent by GitHub',
      installHint: 'npm install -g @github/copilot',
      isAvailable: true,
      version: '1.0.0',
      isRequired: false,
    ),
    DependencyStatus(
      id: 'claude',
      name: 'Claude Code',
      description: 'AI coding agent by Anthropic',
      installHint: 'npm install -g @anthropic-ai/claude-code',
      isAvailable: false,
      isRequired: false,
      installAction: InstallAction(
        executable: 'npm',
        args: ['install', '-g', '@anthropic-ai/claude-code'],
      ),
    ),
  ],
);

const _fakeAllOkResult = SetupCheckResult(
  deps: [
    DependencyStatus(
      id: 'git',
      name: 'git',
      description: 'Version control',
      installHint: 'brew install git',
      isAvailable: true,
      version: '2.49.0',
    ),
  ],
  agents: [
    DependencyStatus(
      id: 'copilot',
      name: 'GitHub Copilot',
      description: 'AI coding agent by GitHub',
      installHint: 'npm install -g @github/copilot',
      isAvailable: true,
      isRequired: false,
    ),
  ],
);

/// Resolves on the fake test clock so the loading state is observable and
/// deterministic (advance with `tester.pump`).
Future<SetupCheckResult> _delayedFake(SetupCheckResult result) =>
    Future<SetupCheckResult>.delayed(
      const Duration(milliseconds: 10),
      () => result,
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ThemeManager.instance.load();
    debugSetupCheckRunner = () => _delayedFake(_fakeResult);
  });

  tearDown(() {
    debugSetupCheckRunner = SetupCheckService.check;
  });

  /// The macOS permissions card probes the real file system, which never
  /// completes inside the widget-test fake-async zone — give the real event
  /// loop turns while advancing the fake clock until the loading view is
  /// gone (the wizard footer shows Re-check even while loading, so key off
  /// the loading text instead).
  Future<void> pumpUntilLoaded(WidgetTester tester) async {
    final loading = find.text('Checking your environment...');
    for (var i = 0; i < 100; i++) {
      if (loading.evaluate().isEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 15));
    }
    fail('setup guide did not finish dependency checks in time');
  }

  /// Gives the real event loop turns until [finder] matches — used for the
  /// permissions card, whose status resolves via real file-system I/O.
  Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    fail('widget not found in time: $finder');
  }

  Future<void> pumpEmbedded(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 700, child: SetupGuideEmbedded()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('SetupGuideEmbedded', () {
    testWidgets('shows loading view then dependency and agent sections', (
      tester,
    ) async {
      await pumpEmbedded(tester);

      // Loading state before the checks complete.
      expect(find.text('Checking your environment...'), findsOneWidget);

      await pumpUntilLoaded(tester);

      expect(find.text('Checking your environment...'), findsNothing);
      expect(find.text('System Dependencies'), findsOneWidget);
      expect(find.text('AI Agents'), findsOneWidget);
      expect(find.text('git'), findsOneWidget);
      expect(find.text('tmux'), findsOneWidget);
      expect(find.text('GitHub Copilot'), findsOneWidget);
      expect(find.text('Claude Code'), findsOneWidget);
      // Missing required dep → warning summary in the embedded footer row.
      expect(
        find.text('Some required dependencies are missing'),
        findsOneWidget,
      );
      // Available entries show their badge and version.
      expect(find.text('Available'), findsNWidgets(2));
      expect(find.text('2.49.0'), findsOneWidget);
      // Required deps show the chip.
      expect(find.text('required'), findsNWidgets(2));
    });

    testWidgets('shows macOS permissions card with privacy action', (
      tester,
    ) async {
      await pumpEmbedded(tester);
      await pumpUntilLoaded(tester);
      await pumpUntilFound(tester, find.text('Privacy Settings'));

      expect(find.text('macOS Permissions'), findsOneWidget);
      expect(find.text('Folder Access'), findsOneWidget);
      expect(find.text('Privacy Settings'), findsOneWidget);
    });

    testWidgets('re-check button runs the checks again', (tester) async {
      await pumpEmbedded(tester);
      await pumpUntilLoaded(tester);

      var calls = 0;
      debugSetupCheckRunner = () {
        calls++;
        return _delayedFake(_fakeResult);
      };

      final recheck = find.widgetWithText(TextButton, 'Re-check');
      await tester.ensureVisible(recheck);
      await tester.pump();
      await tester.tap(recheck);
      await tester.pump();
      expect(find.text('Checking your environment...'), findsOneWidget);

      await pumpUntilLoaded(tester);
      expect(find.text('System Dependencies'), findsOneWidget);
      expect(calls, 1);
    });

    testWidgets('copy button copies an install hint', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') return null;
            return null;
          });

      await pumpEmbedded(tester);
      await pumpUntilLoaded(tester);

      // Missing deps/agents render Copy buttons for their install hints.
      final copyButtons = find.text('Copy');
      expect(copyButtons, findsNWidgets(3));

      await tester.ensureVisible(copyButtons.first);
      await tester.pump();
      await tester.tap(copyButtons.first);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text('Copied'), findsOneWidget);

      // The button reverts after a two second delay.
      await tester.pump(const Duration(seconds: 2, milliseconds: 100));
      await tester.pump();
      expect(find.text('Copied'), findsNothing);
    });
  });

  group('SetupGuidePage wizard', () {
    testWidgets('shows get started button and marks setup completed', (
      tester,
    ) async {
      debugSetupCheckRunner = () => _delayedFake(_fakeAllOkResult);
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed:
                        () => SetupGuidePage.show(context, isWizard: true),
                    child: const Text('open wizard'),
                  ),
                ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('open wizard'));
      await tester.pump();
      expect(find.text('Welcome to YoLoIT 👋'), findsOneWidget);

      await pumpUntilLoaded(tester);

      expect(find.text('All required dependencies found'), findsOneWidget);
      expect(find.text('Get Started →'), findsOneWidget);
      expect(await SessionPrefs.isSetupCompleted(), isFalse);

      await tester.tap(find.text('Get Started →'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();

      expect(await SessionPrefs.isSetupCompleted(), isTrue);
      // Let the dialog close transition finish.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Get Started →'), findsNothing);
    });
  });
}
