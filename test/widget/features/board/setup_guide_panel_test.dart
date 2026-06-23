import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/setup/setup_catalog.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/setup_guide_plugin.dart';

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
}
