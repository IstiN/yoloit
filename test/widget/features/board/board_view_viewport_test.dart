import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/sticky_note_plugin.dart';
import 'package:yoloit/features/board/ui/board_view.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';

import 'board_view_test_harness.dart';

/// In-memory clipboard so meta+C/V/D shortcuts can be verified end to end
/// without touching the platform clipboard channel.
class _FakeClipboard implements ClipboardInterface {
  String? text;

  @override
  Future<void> setText(String value) async {
    text = value;
  }

  @override
  Future<String?> getText() async => text;
}

/// Mock for `SystemChannels.platform` so text-editing shortcuts (Ctrl/Cmd+V
/// paste inside a focused TextField) reach an in-memory clipboard in the
/// fake-async test zone — the real platform channel never replies there.
String? _platformClipboardText;

void _installPlatformClipboardMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            _platformClipboardText =
                (call.arguments as Map<String, dynamic>)['text'] as String?;
            return null;
          case 'Clipboard.getData':
            return {'text': _platformClipboardText};
          default:
            return null;
        }
      });
}

void _removePlatformClipboardMock() {
  _platformClipboardText = null;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null);
}

/// A sticky note panel with an inline text field (the paste-bug repro).
BoardPanelInstance _stickyNote(String id, String text) => BoardPanelInstance(
  id: id,
  type: StickyNotePlugin.kTypeId,
  title: text,
  bounds: const BoardPanelBounds(x: 56, y: 74, width: 260, height: 220),
  state: {
    'text': text,
    'color': '#FEF08A',
    'textColor': '#1F2937',
    'fontSize': 18.0,
  },
);

dynamic _viewState(WidgetTester tester) =>
    // ignore: avoid_dynamic_calls
    tester.state(find.byType(BoardView)) as dynamic;

KeyDownEvent _keyDown(LogicalKeyboardKey logical, PhysicalKeyboardKey physical) {
  return KeyDownEvent(
    logicalKey: logical,
    physicalKey: physical,
    timeStamp: Duration.zero,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(installBoardViewChannelMocks);
  tearDownAll(removeBoardViewChannelMocks);

  setUp(_installPlatformClipboardMock);
  tearDown(_removePlatformClipboardMock);

  setUp(CanvasInteractionLock.instance.resetForTesting);
  tearDown(CanvasInteractionLock.instance.resetForTesting);

  testWidgets('escape key cancels a pending connection', (tester) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(
        boards: [
          boardTestBoard(
            panels: [boardTestNote('p1', 'Source'), boardTestNote('p2', 'Target', x: 640)],
          ),
        ],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    final state = _viewState(tester);

    // Without an active connection, escape falls through and is ignored.
    // ignore: avoid_dynamic_calls
    var result = state.debugHandleBoardKeyEvent(
      _keyDown(LogicalKeyboardKey.escape, PhysicalKeyboardKey.escape),
    );
    expect(result, KeyEventResult.ignored);

    // Start a connection from p1.
    await tester.tap(find.byTooltip('Connect (C)'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('p1')));
    await tester.pump();
    expect(find.textContaining('Cancel connection'), findsOneWidget);

    // ignore: avoid_dynamic_calls
    result = state.debugHandleBoardKeyEvent(
      _keyDown(LogicalKeyboardKey.escape, PhysicalKeyboardKey.escape),
    );
    await tester.pump();
    expect(result, KeyEventResult.handled);
    expect(find.textContaining('Cancel connection'), findsNothing);
  });

  testWidgets('delete key removes the selected panels', (tester) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(
        boards: [boardTestBoard(panels: [boardTestNote('p1', 'Keep'), boardTestNote('p2', 'Drop')])],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    final state = _viewState(tester);

    // Empty selection: the key is ignored.
    // ignore: avoid_dynamic_calls
    var result = state.debugHandleBoardKeyEvent(
      _keyDown(LogicalKeyboardKey.delete, PhysicalKeyboardKey.delete),
    );
    expect(result, KeyEventResult.ignored);
    expect(cubit.state.activeBoard!.panels, hasLength(2));

    cubit.selectPanels({'p2'});
    await tester.pump();

    // ignore: avoid_dynamic_calls
    result = state.debugHandleBoardKeyEvent(
      _keyDown(LogicalKeyboardKey.delete, PhysicalKeyboardKey.delete),
    );
    await tester.pump();
    expect(result, KeyEventResult.handled);
    expect(cubit.state.activeBoard!.panels.single.id, 'p1');
    expect(cubit.state.selectedPanelIds, isEmpty);
  });

  testWidgets('meta shortcuts copy, duplicate and paste the selection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final clipboard = _FakeClipboard();
    final cubit = TestBoardViewCubit(
      BoardState(
        boards: [boardTestBoard(panels: [boardTestNote('p1', 'Clonable')])],
        activeBoardId: 'board',
        isLoaded: true,
      ),
      clipboard: clipboard,
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    final state = _viewState(tester);
    cubit.selectPanels({'p1'});
    await tester.pump();

    // Without a meta/control modifier the letter keys are ignored.
    // ignore: avoid_dynamic_calls
    var result = state.debugHandleBoardKeyEvent(
      _keyDown(LogicalKeyboardKey.keyC, PhysicalKeyboardKey.keyC),
    );
    expect(result, KeyEventResult.ignored);
    expect(clipboard.text, isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    addTearDown(() async {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    });

    // Meta+C copies the selection to the clipboard.
    // ignore: avoid_dynamic_calls
    result = state.debugHandleBoardKeyEvent(
      _keyDown(LogicalKeyboardKey.keyC, PhysicalKeyboardKey.keyC),
    );
    expect(result, KeyEventResult.handled);
    await tester.pump();
    expect(clipboard.text, contains('yoloit/panels'));

    // Meta+D duplicates the selected panel in place.
    // ignore: avoid_dynamic_calls
    result = state.debugHandleBoardKeyEvent(
      _keyDown(LogicalKeyboardKey.keyD, PhysicalKeyboardKey.keyD),
    );
    expect(result, KeyEventResult.handled);
    await tester.pump();
    await tester.pump();
    expect(cubit.state.activeBoard!.panels, hasLength(2));

    // Meta+V pastes another copy from the clipboard.
    // ignore: avoid_dynamic_calls
    result = state.debugHandleBoardKeyEvent(
      _keyDown(LogicalKeyboardKey.keyV, PhysicalKeyboardKey.keyV),
    );
    expect(result, KeyEventResult.handled);
    await tester.pump();
    await tester.pump();
    expect(cubit.state.activeBoard!.panels, hasLength(3));

    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  });

  testWidgets('ctrl+V pastes clipboard text into a focused sticky note', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(
        boards: [boardTestBoard(panels: [_stickyNote('p1', 'Source')])],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    // Model the user clicking into the sticky note text field.
    // Focus the sticky text field directly (a real click also triggers the
    // panel selection pipeline, which needs real-IO pumping).
    tester
        .state<EditableTextState>(find.byType(EditableText).first)
        .requestKeyboard();
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>(),
      isNotNull,
      reason: 'the sticky text field must hold keyboard focus',
    );

    await Clipboard.setData(const ClipboardData(text: 'pasted text'));

    // The board shortcut handler treats Ctrl like Meta; without the
    // editable-focus guard it swallows the key for panel pasting.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    addTearDown(() async {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    // The text reached the field; no panel was pasted.
    expect(find.textContaining('pasted text'), findsOneWidget);
    expect(cubit.state.activeBoard!.panels, hasLength(1));
  });

  testWidgets(
    'backspace with selected panels does not delete them while a text field '
    'has focus',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      setBoardViewSurface(tester);

      final cubit = TestBoardViewCubit(
        BoardState(
          boards: [
            boardTestBoard(
              panels: [
                _stickyNote('p1', 'Source'),
                boardTestNote('p2', 'Keep'),
              ],
            ),
          ],
          activeBoardId: 'board',
          isLoaded: true,
        ),
      );
      addTearDown(cubit.close);
      await pumpBoardView(tester, cubit);

      // Focus the sticky text field (models clicking into it), then select
      // both panels programmatically — the real-world hazard combo.
      tester
          .state<EditableTextState>(find.byType(EditableText).first)
          .requestKeyboard();
      await tester.pump();
      cubit.selectPanels({'p1', 'p2'});
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      // The key edited the note text instead of deleting the panels.
      expect(cubit.state.activeBoard!.panels, hasLength(2));
      final text =
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller
              ?.text;
      expect(text?.length, 'Source'.length - 1);
    },
  );


  testWidgets('viewer interaction start/update detects viewport zoom', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    final state = _viewState(tester);
    // ignore: avoid_dynamic_calls
    expect(state.debugCanvasSize.width, greaterThan(0));
    // ignore: avoid_dynamic_calls
    expect(state.debugIsViewportZooming, isFalse);

    // ignore: avoid_dynamic_calls
    state.debugViewerInteractionStart(
      ScaleStartDetails(
        focalPoint: const Offset(400, 300),
        localFocalPoint: const Offset(400, 300),
        pointerCount: 2,
      ),
    );
    await tester.pump();
    // ignore: avoid_dynamic_calls
    expect(state.debugIsViewportZooming, isFalse);

    // Pinch out: scale doubles between start and update.
    // ignore: avoid_dynamic_calls
    state.debugCanvasTransform = Matrix4.diagonal3Values(2.0, 2.0, 1.0);
    // ignore: avoid_dynamic_calls
    state.debugViewerInteractionUpdate(
      ScaleUpdateDetails(
        focalPoint: const Offset(420, 310),
        localFocalPoint: const Offset(420, 310),
        scale: 2.0,
        pointerCount: 2,
      ),
    );
    await tester.pump();

    // ignore: avoid_dynamic_calls
    expect(state.debugIsViewportZooming, isTrue);
    // No canvas lock: the zoomed transform is kept, not reverted.
    // ignore: avoid_dynamic_calls
    expect((state.debugCanvasTransform as Matrix4).storage[0], 2.0);
  });

  testWidgets('viewer interaction reverts transform while canvas lock held', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    final state = _viewState(tester);
    // The interaction starts while a scrollable card holds the canvas lock.
    CanvasInteractionLock.instance.enter();

    // ignore: avoid_dynamic_calls
    final startMatrix = state.debugCanvasTransform as Matrix4;
    // ignore: avoid_dynamic_calls
    state.debugViewerInteractionStart(
      ScaleStartDetails(
        focalPoint: const Offset(400, 300),
        localFocalPoint: const Offset(400, 300),
        pointerCount: 2,
      ),
    );
    await tester.pump();

    // Pan-only change (scale unchanged) while the lock persists: the board
    // must roll the transform back to the interaction-start matrix.
    // ignore: avoid_dynamic_calls
    state.debugCanvasTransform = Matrix4.translationValues(120.0, 80.0, 0.0)
      ..multiply(startMatrix);
    // ignore: avoid_dynamic_calls
    expect((state.debugCanvasTransform as Matrix4).storage[12], isNot(startMatrix.storage[12]));

    // ignore: avoid_dynamic_calls
    state.debugViewerInteractionUpdate(
      ScaleUpdateDetails(
        focalPoint: const Offset(520, 380),
        localFocalPoint: const Offset(520, 380),
        pointerCount: 2,
      ),
    );
    await tester.pump();

    // ignore: avoid_dynamic_calls
    final restored = state.debugCanvasTransform as Matrix4;
    expect(restored.storage[12], startMatrix.storage[12]);
    expect(restored.storage[13], startMatrix.storage[13]);
    CanvasInteractionLock.instance.exit();
  });

  testWidgets('canvas drag drives the interaction lifecycle and persists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    expect(cubit.state.activeBoard!.viewport.translation, Offset.zero);

    await tester.dragFrom(const Offset(600, 600), const Offset(-150, -90));
    await tester.pump();
    await tester.pump();

    final translation = cubit.state.activeBoard!.viewport.translation;
    expect(translation.distance, greaterThan(0));
  });

  /// Delivers [event] straight to the board's interaction-region [Listener],
  /// exactly the way [GestureBinding] would if it won the hit-test race (the
  /// InteractiveViewer's own Listener shadows it for global dispatches).
  void dispatchToCanvasListener(WidgetTester tester, PointerEvent event) {
    final renderListener = tester.renderObject<RenderPointerListener>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Listener &&
            widget.behavior == HitTestBehavior.translucent &&
            widget.onPointerSignal != null &&
            widget.onPointerPanZoomStart != null,
      ),
    );
    final result = HitTestResult();
    tester.binding.hitTestInView(result, event.position, tester.view.viewId);
    final entry = result.path.firstWhere(
      (candidate) => candidate.target == renderListener,
      orElse: () =>
          throw StateError('canvas listener not hit at ${event.position}'),
    );
    entry.target.handleEvent(event.transformed(entry.transform), entry);
    if (event is PointerSignalEvent) {
      GestureBinding.instance.pointerSignalResolver.resolve(event);
    }
  }

  testWidgets('trackpad scroll over the canvas marks a canvas gesture', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(
        boards: [boardTestBoard(panels: [boardTestNote('p1', 'Note')])],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    expect(CanvasInteractionLock.instance.isCanvasGestureActive, isFalse);

    dispatchToCanvasListener(
      tester,
      PointerScrollEvent(
        viewId: tester.view.viewId,
        position: const Offset(900, 600),
        scrollDelta: const Offset(0, -24),
      ),
    );
    await tester.pump();

    expect(CanvasInteractionLock.instance.isCanvasGestureActive, isTrue);

    // Cancel the 180ms hold timer so nothing leaks past the test.
    CanvasInteractionLock.instance.resetForTesting();
    await tester.pump();
    expect(CanvasInteractionLock.instance.isCanvasGestureActive, isFalse);
  });

  testWidgets('trackpad pan-zoom gesture begins and ends a canvas gesture', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(
        boards: [boardTestBoard(panels: [boardTestNote('p1', 'Note')])],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    dispatchToCanvasListener(
      tester,
      PointerPanZoomStartEvent(
        viewId: tester.view.viewId,
        position: const Offset(900, 600),
      ),
    );
    await tester.pump();
    expect(CanvasInteractionLock.instance.isCanvasGestureActive, isTrue);

    dispatchToCanvasListener(
      tester,
      PointerPanZoomUpdateEvent(
        viewId: tester.view.viewId,
        position: const Offset(900, 600),
        pan: const Offset(12, 8),
        panDelta: const Offset(12, 8),
      ),
    );
    await tester.pump();

    dispatchToCanvasListener(
      tester,
      PointerPanZoomEndEvent(
        viewId: tester.view.viewId,
        position: const Offset(900, 600),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(CanvasInteractionLock.instance.isCanvasGestureActive, isFalse);
  });

  testWidgets(
    'panel lock conflict with an actor shows who holds the lock',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      setBoardViewSurface(tester);

      final cubit = TestBoardViewCubit(
        BoardState(
          boards: [boardTestBoard(panels: [boardTestNote('p1', 'Locked note')])],
          activeBoardId: 'board',
          isLoaded: true,
        ),
      );
      addTearDown(cubit.close);
      await pumpBoardView(tester, cubit);

      cubit.emit(
        cubit.state.copyWith(
          panelLockConflictPanelId: 'p1',
          panelLockConflictActorId: 'agent-7',
        ),
      );
      await tester.pump();
      expect(find.text('Panel is being edited by agent-7'), findsOneWidget);
      expect(cubit.state.panelLockConflictPanelId, isNull);

      // Drain the snackbar so nothing leaks past the test.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('panel lock conflict without an actor shows a generic message', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(
        boards: [boardTestBoard(panels: [boardTestNote('p1', 'Locked note')])],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    cubit.emit(cubit.state.copyWith(panelLockConflictPanelId: 'p1'));
    await tester.pump();
    expect(find.text('Panel is locked by another user'), findsOneWidget);
    expect(cubit.state.panelLockConflictPanelId, isNull);

    await tester.pump(const Duration(seconds: 5));
  });
}
