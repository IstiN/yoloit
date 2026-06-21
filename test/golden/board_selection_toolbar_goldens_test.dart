import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/ui/widgets/board_selection_toolbar.dart';

Widget _toolbarShell({required int selectedCount}) {
  return MaterialApp(
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(
      body: Center(
        child: BoardSelectionToolbar(
          selectedCount: selectedCount,
          onAddToGroup: () {},
          onDelete: () {},
          onClear: () {},
        ),
      ),
    ),
  );
}

Widget _dialogShell() {
  return MaterialApp(
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(
      body: Center(
        child: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const BoardSelectionGroupDialog(groups: []),
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Golden tests — BoardSelectionToolbar', () {
    testGoldens('single panel selected', (tester) async {
      await tester.pumpWidgetBuilder(
        _toolbarShell(selectedCount: 1),
        surfaceSize: const Size(620, 100),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'board_selection_toolbar_single');
    });

    testGoldens('multiple panels selected', (tester) async {
      await tester.pumpWidgetBuilder(
        _toolbarShell(selectedCount: 3),
        surfaceSize: const Size(620, 100),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'board_selection_toolbar_multiple');
    });
  });

  group('Golden tests — BoardSelectionGroupDialog', () {
    testGoldens('empty groups', (tester) async {
      await tester.pumpWidgetBuilder(
        _dialogShell(),
        surfaceSize: const Size(500, 400),
      );
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pump();
      await screenMatchesGolden(tester, 'board_selection_group_dialog_empty');
    });
  });
}
