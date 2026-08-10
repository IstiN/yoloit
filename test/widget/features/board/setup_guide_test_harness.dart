import 'package:flutter/material.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/setup/setup_catalog.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/setup_guide_plugin.dart';

SetupCheckSnapshot setupSnapshotFor(
  List<SetupPackageStatus> packages, {
  String versionLabel = '24.04',
  SetupTargetOs os = SetupTargetOs.linux,
}) => SetupCheckSnapshot(
  runtime: SetupRuntimeInfo(
    os: os,
    osLabel: 'Ubuntu',
    versionLabel: versionLabel,
    packageManager: 'apt',
    homeDirectory: '/home/yolo',
  ),
  packages: packages,
);

SetupPackageStatus setupPkg({
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

BoardPanelInstance setupPanelFor(
  List<String> selectedIds, {
  String id = 'setup-x',
}) => BoardPanelInstance(
  id: id,
  type: SetupGuidePlugin.kTypeId,
  title: 'Setup Guide',
  bounds: const BoardPanelBounds(x: 0, y: 0, width: 560, height: 520),
  state: {'selectedPackageIds': selectedIds},
);

Widget setupGuideHarness({
  required BoardPanelInstance panel,
  SetupCheckSnapshot? snapshot,
  void Function(Map<String, dynamic> update)? onUpdateState,
  RemoteBoardInfo? remoteInfo,
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
          remoteInfo: remoteInfo,
        ),
      ),
    ),
  ),
);

/// Fake [SetupGuideBackend] that records invocations and replays scripted
/// output instead of spawning real processes or touching the local machine.
class FakeSetupGuideBackend extends SetupGuideBackend {
  int checkCalls = 0;
  Future<SetupCheckSnapshot> Function()? checkHandler;
  List<String> specialLines = <String>[];
  List<String> scriptLines = <String>[];
  String? lastScript;
  final List<String> specialRan = <String>[];

  @override
  Future<SetupCheckSnapshot> checkLocal() {
    checkCalls++;
    final handler = checkHandler;
    if (handler != null) return handler();
    return Future<SetupCheckSnapshot>.value(setupSnapshotFor(<SetupPackageStatus>[]));
  }

  @override
  Stream<String> runInstallScript(String script) {
    lastScript = script;
    return Stream<String>.fromIterable(scriptLines);
  }

  @override
  Stream<String> runSpecialInstallTask(String packageId) {
    specialRan.add(packageId);
    return Stream<String>.fromIterable(specialLines);
  }
}
