import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/ui/board_view.dart';

/// Shared harness for `BoardView` widget tests: a seeded cubit that keeps
/// remote operations offline, small board/panel builders, and a standard
/// pump helper. Used by the board_view_* test files.
class TestBoardViewCubit extends BoardCubit {
  TestBoardViewCubit(BoardState state, {super.clipboard}) {
    emit(state);
  }

  Object? connectError;
  String? connectedUrl;
  String? connectedToken;
  List<BoardDocument> connectResult = const [];

  @override
  Future<void> refreshRemoteBoards({String? url}) async {}

  @override
  Future<List<BoardDocument>> connectRemoteBoards({
    required String url,
    String? token,
  }) async {
    final error = connectError;
    if (error != null) throw error;
    connectedUrl = url;
    connectedToken = token;
    return connectResult;
  }
}

BoardPanelInstance boardTestNote(
  String id,
  String title, {
  double x = 56,
  double y = 74,
  double width = 520,
  double height = 300,
  bool hidden = false,
}) {
  return BoardPanelInstance(
    id: id,
    type: MarkdownNotePlugin.kTypeId,
    title: title,
    bounds: BoardPanelBounds(x: x, y: y, width: width, height: height),
    hidden: hidden,
    state: {'markdown': title},
  );
}

BoardDocument boardTestBoard({
  String id = 'board',
  String name = 'Board',
  bool archived = false,
  List<BoardPanelInstance> panels = const [],
  List<BoardPanelGroup> groups = const [],
  Map<String, dynamic> metadata = const {},
}) {
  return BoardDocument(
    id: id,
    name: name,
    archived: archived,
    viewport: const BoardViewport(scale: 1),
    panels: panels,
    groups: groups,
    metadata: metadata,
  );
}

void setBoardViewSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> pumpBoardView(
  WidgetTester tester,
  BoardCubit cubit, {
  bool skipOverviewPreviewCapture = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        body: BlocProvider.value(
          value: cubit,
          child: BoardView(
            skipOverviewPreviewCapture: skipOverviewPreviewCapture,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 450));
}

/// Stubs the `record` plugin channel so panels that probe the microphone do
/// not hit the platform in widget tests.
void installBoardViewChannelMocks() {
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(recordChannel, (call) async {
        switch (call.method) {
          case 'create':
            return 1;
          case 'dispose':
          case 'hasPermission':
          case 'isRecording':
          case 'isPaused':
            return false;
          default:
            return null;
        }
      });
}

void removeBoardViewChannelMocks() {
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(recordChannel, null);
}
