import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/board_share_server.dart';
import 'package:yoloit/features/board/ui/dialogs/share_board_dialog.dart';

void main() {
  group('ShareBoardDialog', () {
    const info = BoardShareServerInfo(
      url: 'http://192.168.1.2:43110',
      token: 'abc123',
      host: '0.0.0.0',
      port: 43110,
    );

    Widget buildDialog() {
      return MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const ShareBoardDialog(info: info),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      );
    }

    testWidgets('renders title and description', (tester) async {
      await tester.pumpWidget(buildDialog());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Share board'), findsOneWidget);
      expect(
        find.textContaining('Use Connect remote YoLoIT'),
        findsOneWidget,
      );
    });

    testWidgets('renders URL and Token rows', (tester) async {
      await tester.pumpWidget(buildDialog());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('URL'), findsOneWidget);
      expect(find.text('Token'), findsOneWidget);
      expect(find.text('http://192.168.1.2:43110'), findsOneWidget);
      expect(find.text('abc123'), findsOneWidget);
    });

    testWidgets('renders copy buttons', (tester) async {
      await tester.pumpWidget(buildDialog());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.copy), findsNWidgets(2));
    });

    testWidgets('copy buttons are tappable', (tester) async {
      await tester.pumpWidget(buildDialog());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.copy), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.copy).first);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Done button closes dialog', (tester) async {
      await tester.pumpWidget(buildDialog());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Share board'), findsNothing);
    });

    testWidgets('Stop sharing button renders', (tester) async {
      await tester.pumpWidget(buildDialog());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Stop sharing'), findsOneWidget);
    });
  });
}
