import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/ui/sections/notifications_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: const Scaffold(body: NotificationsSection()),
      ),
    );
    // Let the async SessionPrefs load land.
    await tester.pump();
    await tester.pump();
  }

  List<Switch> switches(WidgetTester tester) =>
      tester.widgetList<Switch>(find.byType(Switch)).toList();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows a loading spinner before prefs load', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: const Scaffold(body: NotificationsSection()),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(SettingsToggle), findsNothing);
  });

  testWidgets('renders all three toggles with persisted values', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'notifications.agentSounds': true,
      'notifications.approvalSound': false,
      'notifications.completionSound': true,
    });
    await pumpSection(tester);

    expect(find.text('Enable agent sounds'), findsOneWidget);
    expect(find.text('Approval request sound (Sosumi)'), findsOneWidget);
    expect(find.text('Completion sound (Glass)'), findsOneWidget);

    final sw = switches(tester);
    expect(sw, hasLength(3));
    expect(sw[0].value, isTrue);
    expect(sw[1].value, isFalse);
    expect(sw[2].value, isTrue);
  });

  testWidgets('master switch disables sub-switches and persists', (
    tester,
  ) async {
    await pumpSection(tester);

    // Initially everything enabled.
    expect(switches(tester)[1].onChanged, isNotNull);
    expect(switches(tester)[2].onChanged, isNotNull);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    final sw = switches(tester);
    expect(sw[0].value, isFalse);
    // Sub-switches visually off and disabled while the master is off.
    expect(sw[1].value, isFalse);
    expect(sw[1].onChanged, isNull);
    expect(sw[2].value, isFalse);
    expect(sw[2].onChanged, isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('notifications.agentSounds'), isFalse);
  });

  testWidgets('toggling approval sound persists the preference', (
    tester,
  ) async {
    await pumpSection(tester);

    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();

    expect(switches(tester)[1].value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('notifications.approvalSound'), isFalse);
  });
}
