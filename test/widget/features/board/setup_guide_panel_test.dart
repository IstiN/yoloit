import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/setup/setup_catalog.dart';
import 'package:yoloit/features/board/plugins/builtin/setup_guide_plugin.dart';

import 'setup_guide_test_harness.dart';

// covers-write: board.setup_guide
void main() {
  testWidgets('setup guide panel renders selectable quick commands', (
    tester,
  ) async {
    await tester.pumpWidget(
      setupGuideHarness(
        panel: setupPanelFor(<String>['codex'], id: 'setup-1'),
        snapshot: setupSnapshotFor(<SetupPackageStatus>[
          setupPkg(
            id: 'codex',
            name: 'Codex CLI',
            category: SetupPackageCategory.agents,
            installCommand: 'install codex',
          ),
          setupPkg(
            id: 'kimi',
            name: 'Kimi Code CLI',
            category: SetupPackageCategory.agents,
            installCommand: 'install kimi',
          ),
        ]),
      ),
    );

    await tester.pump();

    expect(find.text('Codex CLI'), findsOneWidget);
    expect(find.text('Kimi Code CLI'), findsOneWidget);
    expect(find.textContaining('Install selected'), findsOneWidget);
    expect(find.text('Copy command'), findsOneWidget);
    expect(find.textContaining('read-only'), findsOneWidget);
  });

  testWidgets('toggling a package writes updated selection to panel state', (
    tester,
  ) async {
    Map<String, dynamic>? lastUpdate;

    await tester.pumpWidget(
      setupGuideHarness(
        panel: setupPanelFor(<String>['codex'], id: 'setup-2'),
        snapshot: setupSnapshotFor(<SetupPackageStatus>[
          setupPkg(
            id: 'codex',
            name: 'Codex CLI',
            category: SetupPackageCategory.agents,
            installCommand: 'install codex',
          ),
          setupPkg(
            id: 'kimi',
            name: 'Kimi Code CLI',
            category: SetupPackageCategory.agents,
            installCommand: 'install kimi',
          ),
        ]),
        onUpdateState: (update) => lastUpdate = update,
      ),
    );

    await tester.pump();

    final kimiTile = find.widgetWithText(CheckboxListTile, 'Kimi Code CLI');
    expect(kimiTile, findsOneWidget);
    await tester.tap(kimiTile);
    await tester.pump();

    expect(lastUpdate, isNotNull);
    final selectedIds = lastUpdate!['selectedPackageIds'] as List<dynamic>;
    expect(selectedIds, contains('codex'));
    expect(selectedIds, contains('kimi'));
  });

  testWidgets('renders sections for system, agents, and optional packages', (
    tester,
  ) async {
    final snapshot = setupSnapshotFor(<SetupPackageStatus>[
      setupPkg(
        id: 'git',
        name: 'Git',
        category: SetupPackageCategory.system,
        required: true,
        available: true,
        version: 'git version 2.43.0',
      ),
      setupPkg(
        id: 'codex',
        name: 'Codex CLI',
        category: SetupPackageCategory.agents,
        installCommand: 'install codex',
      ),
      setupPkg(
        id: 'hand-tool',
        name: 'Hand Tool',
        category: SetupPackageCategory.optional,
      ),
    ]);

    await tester.pumpWidget(
      setupGuideHarness(
        panel: setupPanelFor(<String>['codex']),
        snapshot: snapshot,
      ),
    );
    await tester.pump();

    expect(find.text('System'), findsOneWidget);
    expect(find.text('AI agents'), findsOneWidget);
    expect(find.text('Optional'), findsOneWidget);
    expect(find.text('Git'), findsOneWidget);
    expect(find.text('Codex CLI'), findsOneWidget);
    expect(find.text('Hand Tool'), findsOneWidget);
    // An available package shows its version and a 'ready' badge; a package
    // without an install command is flagged 'manual'.
    expect(find.text('git version 2.43.0'), findsOneWidget);
    expect(find.text('ready'), findsOneWidget);
    expect(find.text('required'), findsOneWidget);
    expect(find.text('manual'), findsOneWidget);
  });

  testWidgets('re-reads the selection when the panel instance changes', (
    tester,
  ) async {
    final snapshot = setupSnapshotFor(<SetupPackageStatus>[
      setupPkg(
        id: 'codex',
        name: 'Codex CLI',
        category: SetupPackageCategory.agents,
        installCommand: 'install codex',
      ),
      setupPkg(
        id: 'kimi',
        name: 'Kimi Code CLI',
        category: SetupPackageCategory.agents,
        installCommand: 'install kimi',
      ),
    ]);

    Map<String, dynamic>? lastUpdate;
    void onUpdate(Map<String, dynamic> update) => lastUpdate = update;

    await tester.pumpWidget(
      setupGuideHarness(
        panel: setupPanelFor(<String>['codex'], id: 'setup-a'),
        snapshot: snapshot,
        onUpdateState: onUpdate,
      ),
    );
    await tester.pump();

    final kimiTile = find.widgetWithText(CheckboxListTile, 'Kimi Code CLI');
    expect(tester.widget<CheckboxListTile>(kimiTile).value, isFalse);

    // Replacing the panel with a different instance/state must refresh the
    // selection through didUpdateWidget + _readSelectedIds.
    await tester.pumpWidget(
      setupGuideHarness(
        panel: setupPanelFor(<String>['kimi'], id: 'setup-b'),
        snapshot: snapshot,
        onUpdateState: onUpdate,
      ),
    );
    await tester.pump();

    expect(tester.widget<CheckboxListTile>(kimiTile).value, isTrue);

    await tester.tap(kimiTile);
    await tester.pump();

    expect(lastUpdate, isNotNull);
    final selectedIds = lastUpdate!['selectedPackageIds'] as List<dynamic>;
    expect(selectedIds, isNot(contains('kimi')));
    expect(selectedIds, isNot(contains('codex')));
  });

  testWidgets('falls back to the default selection without state ids', (
    tester,
  ) async {
    final snapshot = setupSnapshotFor(<SetupPackageStatus>[
      setupPkg(
        id: 'codex',
        name: 'Codex CLI',
        category: SetupPackageCategory.agents,
        installCommand: 'install codex',
      ),
    ]);

    Map<String, dynamic>? lastUpdate;
    await tester.pumpWidget(
      setupGuideHarness(
        panel: setupPanelFor(<String>['codex'], id: 'setup-defaults')
            .copyWith(state: <String, dynamic>{}),
        snapshot: snapshot,
        onUpdateState: (update) => lastUpdate = update,
      ),
    );
    await tester.pump();

    // 'codex' is part of the default selection, so tapping it deselects it.
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Codex CLI'));
    await tester.pump();

    expect(lastUpdate, isNotNull);
    final selectedIds = lastUpdate!['selectedPackageIds'] as List<dynamic>;
    expect(selectedIds, contains('git'));
    expect(selectedIds, contains('tmux'));
    expect(selectedIds, contains(SetupCatalog.yoloitSkillsPackageId));
    expect(selectedIds, isNot(contains('codex')));
  });

  testWidgets('shows a spinner while the setup check is running', (
    tester,
  ) async {
    final backend = FakeSetupGuideBackend();
    SetupGuidePanel.debugBackend = backend;
    addTearDown(() => SetupGuidePanel.debugBackend = null);

    final completer = Completer<SetupCheckSnapshot>();
    backend.checkHandler = () => completer.future;

    // No initial snapshot: the panel must fetch one via the backend.
    await tester.pumpWidget(
      setupGuideHarness(panel: setupPanelFor(<String>['codex'])),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(backend.checkCalls, 1);

    completer.complete(
      setupSnapshotFor(<SetupPackageStatus>[
        setupPkg(
          id: 'codex',
          name: 'Codex CLI',
          category: SetupPackageCategory.agents,
          installCommand: 'install codex',
        ),
      ]),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Codex CLI'), findsOneWidget);
  });

  testWidgets('shows an error view when the check fails and retries', (
    tester,
  ) async {
    final backend = FakeSetupGuideBackend();
    SetupGuidePanel.debugBackend = backend;
    addTearDown(() => SetupGuidePanel.debugBackend = null);

    var attempt = 0;
    backend.checkHandler = () {
      attempt++;
      if (attempt == 1) {
        return Future<SetupCheckSnapshot>.error(StateError('boom'));
      }
      return Future<SetupCheckSnapshot>.value(
        setupSnapshotFor(<SetupPackageStatus>[
          setupPkg(
            id: 'codex',
            name: 'Codex CLI',
            category: SetupPackageCategory.agents,
            installCommand: 'install codex',
          ),
        ]),
      );
    };

    await tester.pumpWidget(
      setupGuideHarness(panel: setupPanelFor(<String>['codex'])),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Codex CLI'), findsOneWidget);
    expect(backend.checkCalls, 2);
  });

  // The local install flow is exercised through the [SetupGuideBackend] seam:
  // the fake replays scripted output instead of spawning real install
  // processes, which would be neither safe nor deterministic in a widget test.

  testWidgets('local install without an install command surfaces an error', (
    tester,
  ) async {
    final backend = FakeSetupGuideBackend();
    SetupGuidePanel.debugBackend = backend;
    addTearDown(() => SetupGuidePanel.debugBackend = null);

    // The catalog has no install action for SetupTargetOs.unknown, so the
    // install script is empty and _installLocal throws before running anything.
    final snapshot = setupSnapshotFor(
      <SetupPackageStatus>[
        setupPkg(
          id: 'codex',
          name: 'Codex CLI',
          category: SetupPackageCategory.agents,
          installCommand: 'install codex',
        ),
      ],
      os: SetupTargetOs.unknown,
    );

    await tester.pumpWidget(
      setupGuideHarness(
        panel: setupPanelFor(<String>['codex']),
        snapshot: snapshot,
      ),
    );
    await tester.pump();

    await tester.tap(find.textContaining('Install selected'));
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('No install command for selected packages'),
      findsOneWidget,
    );
    expect(backend.lastScript, isNull);
    // The failure clears the installing state so the button is usable again.
    expect(find.textContaining('Install selected'), findsOneWidget);
    expect(find.text('Installing...'), findsNothing);
  });

  testWidgets(
    'local install runs special tasks, streams the script, then refreshes',
    (tester) async {
      final backend = FakeSetupGuideBackend();
      SetupGuidePanel.debugBackend = backend;
      addTearDown(() => SetupGuidePanel.debugBackend = null);

      backend
        ..specialLines = <String>['skills installed']
        ..scriptLines = <String>['downloading codex', '[exit 0]']
        ..checkHandler =
            () => Future<SetupCheckSnapshot>.value(
              setupSnapshotFor(
                <SetupPackageStatus>[
                  setupPkg(
                    id: 'codex',
                    name: 'Codex CLI',
                    category: SetupPackageCategory.agents,
                    available: true,
                    version: 'codex 1.0',
                  ),
                ],
                versionLabel: '42.0',
                os: SetupTargetOs.macos,
              ),
            );

      final snapshot = setupSnapshotFor(
        <SetupPackageStatus>[
          setupPkg(
            id: 'codex',
            name: 'Codex CLI',
            category: SetupPackageCategory.agents,
            installCommand: 'install codex',
          ),
          setupPkg(
            id: SetupCatalog.yoloitSkillsPackageId,
            name: 'YoLoIT Global Skills',
            category: SetupPackageCategory.agents,
            installCommand: 'skills task',
          ),
        ],
        os: SetupTargetOs.macos,
      );

      await tester.pumpWidget(
        setupGuideHarness(
          panel: setupPanelFor(<String>[
            'codex',
            SetupCatalog.yoloitSkillsPackageId,
          ]),
          snapshot: snapshot,
        ),
      );
      await tester.pump();

      await tester.tap(find.textContaining('Install selected'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The special task ran first, then the batch install script.
      expect(backend.specialRan, <String>[SetupCatalog.yoloitSkillsPackageId]);
      expect(backend.lastScript, isNotNull);
      expect(backend.lastScript, contains('codex/install.sh'));
      // Streamed output landed in the log (early lines are culled once the
      // log auto-scrolls to the bottom, so assert on the tail).
      expect(find.text('downloading codex'), findsOneWidget);
      expect(find.text('downloading codex'), findsOneWidget);
      expect(find.text('[exit 0]'), findsOneWidget);
      // The panel refreshed once the install completed and cleared the
      // installing state, so the install button is enabled again.
      expect(backend.checkCalls, 1);
      expect(find.text('42.0'), findsOneWidget);
      expect(find.textContaining('Install selected'), findsOneWidget);
      expect(find.text('Installing...'), findsNothing);
    },
  );

  testWidgets('copy command flips to Copied and resets after two seconds', (
    tester,
  ) async {
    // Clipboard needs a platform handler in widget tests, otherwise
    // Clipboard.setData never completes and the label never flips.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final snapshot = setupSnapshotFor(<SetupPackageStatus>[
      setupPkg(
        id: 'codex',
        name: 'Codex CLI',
        category: SetupPackageCategory.agents,
        installCommand: 'install codex',
      ),
    ]);

    await tester.pumpWidget(
      setupGuideHarness(
        panel: setupPanelFor(<String>['codex']),
        snapshot: snapshot,
      ),
    );
    await tester.pump();

    final copyButton = find.widgetWithText(TextButton, 'Copy command');
    expect(copyButton, findsOneWidget);
    expect(tester.widget<TextButton>(copyButton).onPressed, isNotNull);

    await tester.tap(copyButton);
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Copy command'), findsOneWidget);
  });

  testWidgets('header badges reflect required availability and version', (
    tester,
  ) async {
    final ready = setupSnapshotFor(<SetupPackageStatus>[
      setupPkg(
        id: 'git',
        name: 'Git',
        category: SetupPackageCategory.system,
        required: true,
        available: true,
      ),
    ]);
    await tester.pumpWidget(
      setupGuideHarness(panel: setupPanelFor(<String>['git']), snapshot: ready),
    );
    await tester.pump();
    expect(find.text('required ready'), findsOneWidget);
    expect(find.text('24.04'), findsOneWidget);

    // A fresh widget (new state) picks up the other snapshot.
    await tester.pumpWidget(const SizedBox());

    final missing = setupSnapshotFor(
      <SetupPackageStatus>[
        setupPkg(
          id: 'git',
          name: 'Git',
          category: SetupPackageCategory.system,
          required: true,
          installCommand: 'install git',
        ),
      ],
      versionLabel: '',
    );
    await tester.pumpWidget(
      setupGuideHarness(
        panel: setupPanelFor(<String>['git']),
        snapshot: missing,
      ),
    );
    await tester.pump();
    expect(find.text('required missing'), findsOneWidget);
    // An empty version label hides that badge entirely.
    expect(find.text('24.04'), findsNothing);
  });
}
