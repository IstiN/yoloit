import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/setup/setup_catalog.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/setup_guide_plugin.dart';

SetupCheckSnapshot _snapshotFor(
  List<SetupPackageStatus> packages, {
  String versionLabel = '24.04',
}) => SetupCheckSnapshot(
  runtime: SetupRuntimeInfo(
    os: SetupTargetOs.linux,
    osLabel: 'Ubuntu',
    versionLabel: versionLabel,
    packageManager: 'apt',
    homeDirectory: '/home/yolo',
  ),
  packages: packages,
);

SetupPackageStatus _pkg({
  required String id,
  required String name,
  required SetupPackageCategory category,
  bool required = false,
  bool available = false,
  String? version,
  String? installCommand,
}) => SetupPackageStatus(
  id: id,
  name: name,
  category: category,
  description: '$name description',
  command: id,
  required: required,
  available: available,
  version: version,
  installAction:
      installCommand == null
          ? null
          : SetupInstallAction(command: installCommand),
);

BoardPanelInstance _panelFor(
  List<String> selectedIds, {
  String id = 'setup-x',
}) => BoardPanelInstance(
  id: id,
  type: SetupGuidePlugin.kTypeId,
  title: 'Setup Guide',
  bounds: const BoardPanelBounds(x: 0, y: 0, width: 560, height: 520),
  state: {'selectedPackageIds': selectedIds},
);

Widget _harness({
  required BoardPanelInstance panel,
  required SetupCheckSnapshot snapshot,
  void Function(Map<String, dynamic> update)? onUpdateState,
}) => MaterialApp(
  theme: AppThemePreset.neonPurple.theme,
  home: Scaffold(
    body: SizedBox(
      width: 560,
      height: 520,
      child: SetupGuidePanel(
        panel: panel,
        initialSnapshot: snapshot,
        renderContext: BoardPanelRenderContext(
          isSelected: true,
          onFocus: () {},
          onDelete: () {},
          onUpdateState: onUpdateState ?? (_) {},
          onShowEditor: () {},
        ),
      ),
    ),
  ),
);

// covers-write: board.setup_guide
void main() {
  testWidgets('setup guide panel renders selectable quick commands', (
    tester,
  ) async {
    const panel = BoardPanelInstance(
      id: 'setup-1',
      type: SetupGuidePlugin.kTypeId,
      title: 'Setup Guide',
      bounds: BoardPanelBounds(x: 0, y: 0, width: 560, height: 520),
      state: {
        'selectedPackageIds': <String>['codex'],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: SizedBox(
            width: 560,
            height: 520,
            child: SetupGuidePanel(
              panel: panel,
              initialSnapshot: const SetupCheckSnapshot(
                runtime: SetupRuntimeInfo(
                  os: SetupTargetOs.linux,
                  osLabel: 'Ubuntu',
                  versionLabel: '24.04',
                  packageManager: 'apt',
                  homeDirectory: '/home/yolo',
                ),
                packages: <SetupPackageStatus>[
                  SetupPackageStatus(
                    id: 'codex',
                    name: 'Codex CLI',
                    category: SetupPackageCategory.agents,
                    description: 'OpenAI coding agent',
                    command: 'codex',
                    required: false,
                    available: false,
                    installAction: SetupInstallAction(command: 'install codex'),
                  ),
                  SetupPackageStatus(
                    id: 'kimi',
                    name: 'Kimi Code CLI',
                    category: SetupPackageCategory.agents,
                    description: 'Moonshot AI terminal coding agent',
                    command: 'kimi',
                    required: false,
                    available: false,
                    installAction: SetupInstallAction(command: 'install kimi'),
                  ),
                ],
              ),
              renderContext: BoardPanelRenderContext(
                isSelected: true,
                onFocus: () {},
                onDelete: () {},
                onUpdateState: (_) {},
                onShowEditor: () {},
              ),
            ),
          ),
        ),
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
    const panel = BoardPanelInstance(
      id: 'setup-2',
      type: SetupGuidePlugin.kTypeId,
      title: 'Setup Guide',
      bounds: BoardPanelBounds(x: 0, y: 0, width: 560, height: 520),
      state: {
        'selectedPackageIds': <String>['codex'],
      },
    );

    Map<String, dynamic>? lastUpdate;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: SizedBox(
            width: 560,
            height: 520,
            child: SetupGuidePanel(
              panel: panel,
              initialSnapshot: const SetupCheckSnapshot(
                runtime: SetupRuntimeInfo(
                  os: SetupTargetOs.linux,
                  osLabel: 'Ubuntu',
                  versionLabel: '24.04',
                  packageManager: 'apt',
                  homeDirectory: '/home/yolo',
                ),
                packages: <SetupPackageStatus>[
                  SetupPackageStatus(
                    id: 'codex',
                    name: 'Codex CLI',
                    category: SetupPackageCategory.agents,
                    description: 'OpenAI coding agent',
                    command: 'codex',
                    required: false,
                    available: false,
                    installAction: SetupInstallAction(command: 'install codex'),
                  ),
                  SetupPackageStatus(
                    id: 'kimi',
                    name: 'Kimi Code CLI',
                    category: SetupPackageCategory.agents,
                    description: 'Moonshot AI terminal coding agent',
                    command: 'kimi',
                    required: false,
                    available: false,
                    installAction: SetupInstallAction(command: 'install kimi'),
                  ),
                ],
              ),
              renderContext: BoardPanelRenderContext(
                isSelected: true,
                onFocus: () {},
                onDelete: () {},
                onUpdateState: (update) => lastUpdate = update,
                onShowEditor: () {},
              ),
            ),
          ),
        ),
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
    final snapshot = _snapshotFor(<SetupPackageStatus>[
      _pkg(
        id: 'git',
        name: 'Git',
        category: SetupPackageCategory.system,
        required: true,
        available: true,
        version: 'git version 2.43.0',
      ),
      _pkg(
        id: 'codex',
        name: 'Codex CLI',
        category: SetupPackageCategory.agents,
        installCommand: 'install codex',
      ),
      _pkg(
        id: 'hand-tool',
        name: 'Hand Tool',
        category: SetupPackageCategory.optional,
      ),
    ]);

    await tester.pumpWidget(
      _harness(panel: _panelFor(<String>['codex']), snapshot: snapshot),
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
    final snapshot = _snapshotFor(<SetupPackageStatus>[
      _pkg(
        id: 'codex',
        name: 'Codex CLI',
        category: SetupPackageCategory.agents,
        installCommand: 'install codex',
      ),
      _pkg(
        id: 'kimi',
        name: 'Kimi Code CLI',
        category: SetupPackageCategory.agents,
        installCommand: 'install kimi',
      ),
    ]);

    Map<String, dynamic>? lastUpdate;
    void onUpdate(Map<String, dynamic> update) => lastUpdate = update;

    await tester.pumpWidget(
      _harness(
        panel: _panelFor(<String>['codex'], id: 'setup-a'),
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
      _harness(
        panel: _panelFor(<String>['kimi'], id: 'setup-b'),
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
    const panel = BoardPanelInstance(
      id: 'setup-defaults',
      type: SetupGuidePlugin.kTypeId,
      title: 'Setup Guide',
      bounds: BoardPanelBounds(x: 0, y: 0, width: 560, height: 520),
      state: <String, dynamic>{},
    );
    final snapshot = _snapshotFor(<SetupPackageStatus>[
      _pkg(
        id: 'codex',
        name: 'Codex CLI',
        category: SetupPackageCategory.agents,
        installCommand: 'install codex',
      ),
    ]);

    Map<String, dynamic>? lastUpdate;
    await tester.pumpWidget(
      _harness(
        panel: panel,
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

  // NOTE: there is intentionally no test for the local install flow.
  // `_installLocal` builds its script via `SetupCatalog.installScript`, which
  // always returns at least the `set +e` preamble (see
  // `SetupCatalog.installBatchScript`), so the 'No install command' StateError
  // is unreachable and every other selection spawns a real install process —
  // not safe or deterministic in a widget test.

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

    final snapshot = _snapshotFor(<SetupPackageStatus>[
      _pkg(
        id: 'codex',
        name: 'Codex CLI',
        category: SetupPackageCategory.agents,
        installCommand: 'install codex',
      ),
    ]);

    await tester.pumpWidget(
      _harness(panel: _panelFor(<String>['codex']), snapshot: snapshot),
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
    final ready = _snapshotFor(<SetupPackageStatus>[
      _pkg(
        id: 'git',
        name: 'Git',
        category: SetupPackageCategory.system,
        required: true,
        available: true,
      ),
    ]);
    await tester.pumpWidget(
      _harness(panel: _panelFor(<String>['git']), snapshot: ready),
    );
    await tester.pump();
    expect(find.text('required ready'), findsOneWidget);
    expect(find.text('24.04'), findsOneWidget);

    // A fresh widget (new state) picks up the other snapshot.
    await tester.pumpWidget(const SizedBox());

    final missing = _snapshotFor(
      <SetupPackageStatus>[
        _pkg(
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
      _harness(panel: _panelFor(<String>['git']), snapshot: missing),
    );
    await tester.pump();
    expect(find.text('required missing'), findsOneWidget);
    // An empty version label hides that badge entirely.
    expect(find.text('24.04'), findsNothing);
  });
}
