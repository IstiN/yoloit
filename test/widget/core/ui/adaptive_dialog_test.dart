import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';

void main() {
  testWidgets('AdaptiveDialogScaffold uses fullscreen layout on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: AdaptiveDialogScaffold(
          title: 'Mobile dialog',
          body: Text('Body'),
          actions: [Text('Action')],
        ),
      ),
    );

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Material), findsWidgets);
    expect(find.text('Mobile dialog'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
  });

  testWidgets('AdaptiveDialogScaffold keeps alert layout on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: AdaptiveDialogScaffold(
          title: 'Desktop dialog',
          body: Text('Body'),
        ),
      ),
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Desktop dialog'), findsOneWidget);
  });
}
