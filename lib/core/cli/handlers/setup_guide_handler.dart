import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for Setup Guide panels (`board.setup_guide`).
class SetupGuideCliHandler extends PanelCliHandler {
  const SetupGuideCliHandler();

  @override
  String get typeId => 'board.setup_guide';

  @override
  List<String> get supportedActions => [
    'get',
    'select',
    'unselect',
    'set-selected',
  ];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {'selectedPackageIds': _selectedIds(panel)};
  }

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'get':
        return CliActionResult(data: getContent(panel));
      case 'select':
        final packageId = args['packageId']?.toString().trim();
        if (packageId == null || packageId.isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "packageId" field',
          );
        }
        final selected = _selectedIds(panel);
        if (!selected.contains(packageId)) {
          selected.add(packageId);
        }
        return CliActionResult(
          message: 'Selected package $packageId',
          stateUpdate: {'selectedPackageIds': selected},
        );
      case 'unselect':
        final packageId = args['packageId']?.toString().trim();
        if (packageId == null || packageId.isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "packageId" field',
          );
        }
        final selected = _selectedIds(panel);
        selected.remove(packageId);
        return CliActionResult(
          message: 'Unselected package $packageId',
          stateUpdate: {'selectedPackageIds': selected},
        );
      case 'set-selected':
        final packageIds = _packageIdsArg(args);
        if (packageIds == null) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "packageIds" field',
          );
        }
        return CliActionResult(
          message: 'Selected packages updated (${packageIds.length})',
          stateUpdate: {'selectedPackageIds': packageIds},
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'get': const CliActionHelp(
      description: 'Read selected setup package ids',
    ),
    'select': const CliActionHelp(
      description: 'Select a setup package by id',
      params: {'packageId': 'Package id (required)'},
    ),
    'unselect': const CliActionHelp(
      description: 'Unselect a setup package by id',
      params: {'packageId': 'Package id (required)'},
    ),
    'set-selected': const CliActionHelp(
      description: 'Replace the selected setup package list',
      params: {'packageIds': 'Array of package ids (required)'},
    ),
  };

  List<String> _selectedIds(BoardPanelInstance panel) {
    final raw = panel.state['selectedPackageIds'];
    if (raw is List) {
      return raw
          .map((value) => value?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  List<String>? _packageIdsArg(Map<String, dynamic> args) {
    final raw = args['packageIds'] ?? args['packages'];
    if (raw is! List) return null;
    return raw
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
  }
}
