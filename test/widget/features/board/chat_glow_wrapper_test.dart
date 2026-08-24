import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget.dart';
import 'package:yoloit/features/board/ui/chat_glow_wrapper.dart';

void main() {
  const panelId = 'panel-glow-test';
  final notifier = ValueNotifier<bool>(false);

  Future<void> pumpGlow(WidgetTester tester, {bool tickersEnabled = true}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(AppColors.presetCyberGreen),
        home: TickerMode(
          enabled: tickersEnabled,
          child: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 120,
                child: ChatGlowWrapper(
                  panelId: panelId,
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                  child: ColoredBox(color: Colors.black),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ChatGlowWrapperState glowState(WidgetTester tester) =>
      tester.state<ChatGlowWrapperState>(find.byType(ChatGlowWrapper));

  Finder glowOpacity() => find.descendant(
    of: find.byType(ChatGlowWrapper),
    matching: find.byType(Opacity),
  );

  BoxDecoration glowDecoration(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(ChatGlowWrapper),
        matching: find.byType(DecoratedBox),
      ),
    );
    return box.decoration as BoxDecoration;
  }

  setUp(() {
    notifier.value = false;
    ChatPanelWidget.processingNotifiers[panelId] = notifier;
  });

  tearDown(() {
    ChatPanelWidget.processingNotifiers.remove(panelId);
  });

  testWidgets('no glow and no ticker while not processing', (tester) async {
    await pumpGlow(tester);
    // Let the post-frame notifier retry run.
    await tester.pump();

    expect(glowOpacity(), findsNothing);
    expect(glowState(tester).isGlowAnimating, isFalse);
  });

  testWidgets(
    'processing pulse animates opacity only over a static glow layer',
    (tester) async {
      await pumpGlow(tester);

      notifier.value = true;
      await tester.pump();

      // Glow layer exists and is raster-cached behind a RepaintBoundary.
      expect(glowOpacity(), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ChatGlowWrapper),
          matching: find.byType(RepaintBoundary),
        ),
        findsOneWidget,
      );
      expect(glowState(tester).isGlowAnimating, isTrue);

      // Controller just started: alpha maps to the old 20/80 lower bound.
      expect(tester.widget<Opacity>(glowOpacity()).opacity, 0.25);

      final decorationBefore = glowDecoration(tester);
      final shadow = decorationBefore.boxShadow!.single;
      expect(shadow.blurRadius, 20);
      expect(shadow.spreadRadius, 2);
      final scheme = AppColorScheme.fromAccent(
        AppColors.presetCyberGreen,
        brightness: Brightness.dark,
      );
      expect(shadow.color, scheme.accentGreenGlow.withAlpha(80));

      // Half a 1200ms cycle -> value 0.5 -> opacity 0.625. The static glow
      // layer (decoration instance) is untouched: only the layer opacity
      // changes, so the compositor re-uses the rasterized shadow.
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.widget<Opacity>(glowOpacity()).opacity, 0.625);
      expect(identical(glowDecoration(tester), decorationBefore), isTrue);
    },
  );

  testWidgets('glow ticker stops when processing ends', (tester) async {
    await pumpGlow(tester);

    notifier.value = true;
    await tester.pump();
    expect(glowState(tester).isGlowAnimating, isTrue);

    notifier.value = false;
    await tester.pump();

    expect(glowOpacity(), findsNothing);
    expect(glowState(tester).isGlowAnimating, isFalse);
    // Nothing left scheduling frames for the glow.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('TickerMode disables and resumes the glow ticker', (
    tester,
  ) async {
    notifier.value = true;
    await pumpGlow(tester);
    expect(glowState(tester).isGlowAnimating, isTrue);

    // Board hidden under the overview: tickers muted, no frames scheduled.
    await pumpGlow(tester, tickersEnabled: false);
    expect(glowState(tester).isGlowAnimating, isFalse);
    // The glow layer stays (state preserved), it just stops pulsing.
    expect(glowOpacity(), findsOneWidget);

    await pumpGlow(tester);
    expect(glowState(tester).isGlowAnimating, isTrue);
  });

  testWidgets('no glow when the panel never registers a notifier', (
    tester,
  ) async {
    ChatPanelWidget.processingNotifiers.remove(panelId);
    await pumpGlow(tester);
    // Post-frame retry still finds nothing.
    await tester.pump();

    expect(glowOpacity(), findsNothing);
    expect(glowState(tester).isGlowAnimating, isFalse);
  });

  testWidgets('pulse value updates are throttled to ~30fps while processing', (
    tester,
  ) async {
    notifier.value = true;
    await pumpGlow(tester);
    // Drain the initial frame so the ticker is running.
    await tester.pump();

    final state = glowState(tester);
    var updateCount = 0;
    void onUpdate() {
      updateCount += 1;
    }

    state.debugPulseValue.addListener(onUpdate);

    // Pump 60 frames at 16ms (≈960ms wall-clock) — at 60Hz the ticker
    // would fire 60 times. Throttling caps the value-notifier updates
    // at roughly one per 33ms, so we expect ~29 updates for ~960ms.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    state.debugPulseValue.removeListener(onUpdate);

    // Allow a wide window so the assertion is robust against scheduler
    // rounding; the key claim is "noticeably fewer than 60", not an
    // exact 30.
    expect(
      updateCount,
      lessThan(40),
      reason: 'expected throttled updates (<40) but got $updateCount',
    );
    expect(
      updateCount,
      greaterThan(15),
      reason: 'expected some throttled updates (>15) but got $updateCount',
    );
  });
}
