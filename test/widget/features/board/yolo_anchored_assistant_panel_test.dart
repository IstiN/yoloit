import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget_vm.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/yolo_anchored_assistant_panel.dart';

import '../../../unit/helpers/mock_board_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBoardCubit cubit;
  late ChatPanelController chatController;
  late BoardPanelInstance? builtAssistantPanel;
  late int closeCalls;
  late int micConsumedCalls;

  BoardPanelInstance anchor(String id, {Map<String, dynamic>? state}) =>
      BoardPanelInstance(
        id: id,
        type: 'board.markdown',
        title: 'Anchor $id',
        bounds: const BoardPanelBounds(x: 40, y: 40, width: 420, height: 300),
        state: state ?? const {},
      );

  Widget buildPanel(BoardPanelInstance anchorPanel, {bool startMic = false}) {
    return MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: BlocProvider<BoardCubit>.value(
        value: cubit,
        child: Scaffold(
          body: Stack(
            children: [
              YoloAnchoredAssistantPanel(
                anchorPanel: anchorPanel,
                canvasOrigin: Offset.zero,
                chatController: chatController,
                startMic: startMic,
                onStartMicConsumed: () => micConsumedCalls++,
                onClose: () => closeCalls++,
                chatBuilder: (assistantPanel, onUpdateState) {
                  builtAssistantPanel = assistantPanel;
                  return const SizedBox.expand();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  setUp(() {
    // 'local' short-circuits provider resolution before any storage reads.
    SharedPreferences.setMockInitialValues({
      'assistant_provider_type_v1': 'local',
    });
    cubit = MockBoardCubit();
    when(
      () => cubit.stream,
    ).thenAnswer((_) => const Stream<BoardState>.empty());
    when(() => cubit.updatePanel(any(), any())).thenAnswer((_) async {});
    when(
      () => cubit.updatePanel(any(), any(), boardId: any(named: 'boardId')),
    ).thenAnswer((_) async {});
    chatController = ChatPanelController();
    builtAssistantPanel = null;
    closeCalls = 0;
    micConsumedCalls = 0;
  });

  Future<void> pumpAssistant(
    WidgetTester tester,
    BoardPanelInstance anchorPanel, {
    bool startMic = false,
  }) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildPanel(anchorPanel, startMic: startMic));
    // Finish the 420ms entry animation.
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('close reverses the entry animation, then fires onClose', (
    tester,
  ) async {
    await pumpAssistant(
      tester,
      anchor('a1', state: {
        'yoloAssistant': {'assistantProviderResolved': true},
      }),
    );
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 100));
    // Still reversing — onClose has not fired yet.
    expect(closeCalls, 0);

    await tester.pump(const Duration(milliseconds: 500));
    expect(closeCalls, 1);
  });

  testWidgets('tapping close again while reversing closes immediately', (
    tester,
  ) async {
    await pumpAssistant(
      tester,
      anchor('a1', state: {
        'yoloAssistant': {'assistantProviderResolved': true},
      }),
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 100));
    expect(closeCalls, 0);

    // Second tap hits the already-reversing branch: no extra wait.
    await tester.tap(find.byIcon(Icons.close));
    expect(closeCalls, 1);

    // When the reverse finishes, the first invocation completes too.
    await tester.pump(const Duration(milliseconds: 500));
    expect(closeCalls, 2);
  });

  testWidgets('anchor change rebuilds the assistant panel and re-bootstraps', (
    tester,
  ) async {
    final updatedPanelIds = <String>[];
    when(() => cubit.updatePanel(any(), any())).thenAnswer((invocation) async {
      updatedPanelIds.add(invocation.positionalArguments[0] as String);
    });

    await pumpAssistant(
      tester,
      anchor('a1', state: {
        'yoloAssistant': {'assistantProviderResolved': true},
      }),
    );
    expect(builtAssistantPanel!.id, 'yolo-badge-a1');
    expect(builtAssistantPanel!.title, 'YoLo: Anchor a1');

    // The bootstrap future runs SharedPreferences / secure-storage I/O, which
    // needs the real event loop.
    await tester.runAsync(() async {
      await tester.pumpWidget(buildPanel(anchor('a2')));
      final sw = Stopwatch()..start();
      while (updatedPanelIds.isEmpty && sw.elapsed < const Duration(seconds: 10)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });

    // didUpdateWidget rebuilt the derived assistant panel for the new anchor.
    expect(builtAssistantPanel!.id, 'yolo-badge-a2');
    expect(builtAssistantPanel!.title, 'YoLo: Anchor a2');

    // The new anchor had no persisted resolution, so the bootstrap ran and
    // wrote the resolved provider back through the cubit.
    expect(updatedPanelIds, contains('a2'));
  });

  testWidgets('same anchor keeps the existing assistant panel', (tester) async {
    await pumpAssistant(
      tester,
      anchor('a1', state: {
        'yoloAssistant': {'assistantProviderResolved': true},
      }),
    );
    final first = builtAssistantPanel;

    await tester.pumpWidget(
      buildPanel(
        anchor('a1', state: {
          'yoloAssistant': {'assistantProviderResolved': true},
        }),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(identical(builtAssistantPanel, first), isTrue);
    verifyNever(() => cubit.updatePanel(any(), any()));
  });

  testWidgets('startMic flipping to true consumes the mic request', (
    tester,
  ) async {
    await pumpAssistant(
      tester,
      anchor('a1', state: {
        'yoloAssistant': {'assistantProviderResolved': true},
      }),
    );
    expect(micConsumedCalls, 0);

    await tester.pumpWidget(
      buildPanel(
        anchor('a1', state: {
          'yoloAssistant': {'assistantProviderResolved': true},
        }),
        startMic: true,
      ),
    );
    await tester.pump();

    expect(micConsumedCalls, 1);
  });

  testWidgets('startMic at mount consumes the mic request after first frame', (
    tester,
  ) async {
    await pumpAssistant(
      tester,
      anchor('a1', state: {
        'yoloAssistant': {'assistantProviderResolved': true},
      }),
      startMic: true,
    );
    await tester.pump();

    expect(micConsumedCalls, 1);
  });
}
