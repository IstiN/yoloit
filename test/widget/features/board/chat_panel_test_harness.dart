import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// Platform dirs rooted in a per-test temp directory.
class ChatTestPlatformDirs extends PlatformDirs {
  const ChatTestPlatformDirs(this.root);

  final String root;

  @override
  String get configDir => '$root/config';

  @override
  String get dataDir => '$root/data';

  @override
  String get logsDir => '$root/logs';

  @override
  String get tempDir => root;

  @override
  String get skillsDir => '$root/skills';

  @override
  String get yoloitTempDir => '$root/tmp';
}

/// Chat provider test double with a controllable event stream.
class FakeChatProvider extends ChatProvider {
  FakeChatProvider({
    required this.id,
    this.autoSessionId,
    this.models = const [
      ChatModelInfo(id: 'fake-model', displayName: 'Fake Model'),
    ],
  });

  final String id;
  final String? autoSessionId;
  final List<ChatModelInfo> models;
  final List<String> sentMessages = [];
  final List<ChatRuntimeContext?> sentRuntimeContexts = [];
  final List<List<String>> sentAttachments = [];
  final Map<String, String> _sessionIds = {};
  StreamController<ChatEvent>? _controller;

  @override
  String get providerId => id;

  @override
  String get displayName => 'Fake';

  @override
  List<ChatModelInfo> get availableModels => models;

  @override
  bool get supportsImages => false;

  @override
  ChatImageMode get imageMode => ChatImageMode.filePath;

  @override
  bool isRunning(String sessionName) => _controller != null;

  @override
  Stream<ChatEvent> sendMessage({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
    List<Map<String, Object?>>? audioContentOverride,
  }) {
    sentMessages.add(message);
    sentRuntimeContexts.add(runtimeContext);
    sentAttachments.add(attachments);
    final sid = autoSessionId;
    if (sid != null) _sessionIds[config.sessionName] = sid;
    _controller = StreamController<ChatEvent>();
    return _controller!.stream;
  }

  void emit(ChatEvent event) => _controller?.add(event);

  void emitError(Object error) => _controller?.addError(error);

  Future<void> complete() async {
    final controller = _controller;
    _controller = null;
    await controller?.close();
  }

  @override
  Future<void> stop(String sessionName) => complete();

  @override
  void dispose() {}

  @override
  void setSessionId(String sessionName, String sessionId) {
    _sessionIds[sessionName] = sessionId;
  }

  @override
  String? getSessionId(String sessionName) => _sessionIds[sessionName];
}

ChatEvent chatDeltaEvent(String text) => ChatEvent(
  type: ChatEventType.assistantDelta,
  rawType: 'assistant.message_delta',
  data: {'deltaContent': text},
);

ChatEvent chatToolStartEvent(
  String toolCallId,
  String toolName, {
  Map<String, dynamic>? arguments,
}) => ChatEvent(
  type: ChatEventType.toolStart,
  rawType: 'tool.execution_start',
  data: {
    'toolCallId': toolCallId,
    'toolName': toolName,
    'arguments': ?arguments,
  },
);

ChatEvent chatToolCompleteEvent(
  String toolCallId, {
  required String content,
  bool success = true,
}) => ChatEvent(
  type: ChatEventType.toolComplete,
  rawType: 'tool.execution_complete',
  data: {
    'toolCallId': toolCallId,
    'success': success,
    'result': {'content': content},
  },
);

/// Pumps a configured [ChatPanelWidget] against a [FakeChatProvider]-backed
/// session and records every panel-state update.
class ChatPanelHarness {
  ChatPanelHarness({
    required this.provider,
    required this.panelId,
    this.autoSessionId,
    this.extraPanels = const [],
    this.extraState = const {},
    this.models = const [
      ChatModelInfo(id: 'fake-model', displayName: 'Fake Model'),
    ],
    this.seedSession,
  });

  final String provider;
  final String panelId;
  final String? autoSessionId;
  final List<BoardPanelInstance> extraPanels;
  final Map<String, dynamic> extraState;
  final List<ChatModelInfo> models;
  final void Function(ChatSession)? seedSession;

  final List<Map<String, dynamic>> updates = [];
  final List<(String, Map<String, dynamic>, String)> createdPanels = [];
  late final FakeChatProvider fake;
  late final BoardCubit cubit;
  late final ChatSessionConfig config;
  late Map<String, dynamic> panelState;

  ChatSession get session => ChatSessionManager.instance.sessions[panelId]!;

  Future<void> pump(WidgetTester tester) async {
    config = ChatSessionConfig(
      sessionName: 'test-session',
      workingDir: '/tmp',
      provider: provider,
    );
    fake = FakeChatProvider(
      id: provider,
      autoSessionId: autoSessionId,
      models: models,
    );
    final session = ChatSession(
      panelId: panelId,
      config: config,
      providerFactory: (_) => fake,
    );
    seedSession?.call(session);
    ChatSessionManager.instance.sessions[panelId] = session;

    panelState = {
      'configured': true,
      'config': config.toJson(),
      ...extraState,
    };
    final board = BoardDocument(
      id: 'b1',
      name: 'Board 1',
      panels: [_buildPanel(), ...extraPanels],
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('board.documents.v1', jsonEncode([board.toJson()]));
    await prefs.setString('board.active.id.v1', 'b1');
    cubit = BoardCubit();
    // BoardCubit.load() performs real file I/O (AgentConfigService), which
    // never completes inside the widget-test fake-async zone — run it in a
    // real async scope.
    await tester.runAsync(() => cubit.load());

    await _pumpTree(tester);
    await tester.pump();
  }

  /// Re-pumps the widget with a new panel state so `didUpdateWidget` runs.
  /// A fresh map is used so the old widget keeps its previous state snapshot.
  Future<void> rebuild(WidgetTester tester, Map<String, dynamic> newState) async {
    panelState = Map<String, dynamic>.of(newState);
    await _pumpTree(tester);
    await tester.pump();
  }

  BoardPanelInstance _buildPanel() => BoardPanelInstance(
    id: panelId,
    type: ChatPanelPlugin.kTypeId,
    title: 'AI Chat',
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 420, height: 500),
    state: panelState,
  );

  Future<void> _pumpTree(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: SizedBox(
              width: 520,
              height: 620,
              child: ChatPanelWidget(
                panel: _buildPanel(),
                onUpdateState: updates.add,
                onCreateLinkedPanel: (typeId, state, title) async {
                  createdPanels.add((typeId, state, title));
                  return 'linked-${createdPanels.length}';
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Types [text] into the input field and presses Enter, then lets the
  /// debounced draft-persist timer (300 ms) elapse so no timer leaks.
  Future<void> typeAndSend(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  /// Closes the provider stream so `onDone` fires. The close future must not
  /// be awaited directly inside the fake-async zone — it only resolves once
  /// the done event is delivered, which requires a pump first.
  Future<void> finishTurn(WidgetTester tester) async {
    unawaited(fake.complete());
    await tester.pump();
    await tester.pump();
  }

  void dispose() {
    ChatSessionManager.instance.sessions.remove(panelId);
    ChatPanelWidget.processingNotifiers.remove(panelId);
    unawaited(cubit.close());
  }
}
