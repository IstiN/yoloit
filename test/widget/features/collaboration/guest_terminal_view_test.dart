import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart' hide TerminalState;
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/collaboration/services/guest_terminal_registry.dart';
import 'package:yoloit/features/collaboration/ui/guest_terminal_view.dart';

void main() {
  group('GuestTerminalView', () {
    setUp(() {
      GuestTerminalRegistry.instance.clear();
    });

    testWidgets('disables scroll-to-arrow fallback', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(AppColors.presetCyberGreen),
          home: const Scaffold(body: GuestTerminalView(nodeId: 'node-1')),
        ),
      );
      await tester.pump();

      final terminalView = tester.widget<TerminalView>(
        find.byType(TerminalView),
      );
      expect(terminalView.simulateScroll, isFalse);
    });
  });
}
