import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/assistant/widgets/assistant_tool_executor.dart';
import 'package:yoloit/features/board/assistant/yolo_assistant_widget.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cloud_llm_provider.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

/// In-memory record platform so mic capture works without real hardware.
class FakeRecordPlatform extends RecordPlatform {
  StreamController<Uint8List>? byteStreamCtrl;
  Exception? startStreamException;
  bool hasPermissionResult = true;

  final _stateControllers = <String, StreamController<RecordState>>{};

  @override
  Future<void> create(String recorderId) async {
    _stateControllers[recorderId] = StreamController<RecordState>.broadcast();
  }

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    _stateControllers[recorderId]?.add(RecordState.record);
  }

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    final error = startStreamException;
    if (error != null) throw error;
    byteStreamCtrl = StreamController<Uint8List>.broadcast();
    _stateControllers[recorderId]?.add(RecordState.record);
    return byteStreamCtrl!.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    // The record package awaits the record stream's done event on stop and
    // halts amplitude monitoring on RecordState.stop.
    _stateControllers[recorderId]?.add(RecordState.stop);
    await byteStreamCtrl?.close();
    byteStreamCtrl = null;
    return '/tmp/fake.wav';
  }

  @override
  Future<void> pause(String recorderId) async {}

  @override
  Future<void> resume(String recorderId) async {}

  @override
  Future<bool> isRecording(String recorderId) async => true;

  @override
  Future<bool> isPaused(String recorderId) async => false;

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      hasPermissionResult;

  @override
  Future<void> cancel(String recorderId) async {
    await byteStreamCtrl?.close();
    byteStreamCtrl = null;
  }

  @override
  Future<void> dispose(String recorderId) async {
    await _stateControllers[recorderId]?.close();
    _stateControllers.remove(recorderId);
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -30, max: -10);

  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async =>
      true;

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async =>
      const [];

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      _stateControllers[recorderId]!.stream;

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {}
}

/// Scripted chat provider: replays canned [ChatEvent]s and can simulate
/// errors, cancellation gates and mid-flight tool completions.
class FakeChatProvider extends CloudLlmProvider {
  FakeChatProvider() : super.deferred(configId: 'fake');

  List<ChatEvent> events = const [];
  Object? errorToThrow;
  Completer<void>? gate;
  Future<void> Function()? beforeEvents;
  int sendCount = 0;
  String? lastMessage;
  List<Map<String, Object?>>? lastAudioContent;
  bool stopCalled = false;

  @override
  Stream<ChatEvent> sendMessage({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
    List<Map<String, Object?>>? audioContentOverride,
  }) async* {
    sendCount++;
    lastMessage = message;
    lastAudioContent = audioContentOverride;
    await beforeEvents?.call();
    final error = errorToThrow;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    for (final event in events) {
      yield event;
    }
    await gate?.future;
  }

  @override
  Future<void> stop(String sessionName) async {
    stopCalled = true;
    gate?.complete();
  }

  @override
  bool isRunning(String sessionName) => false;

  @override
  void dispose() {}
}

/// Shared environment for [YoloAssistantWidget] tests: board cubit, panel
/// state, fake mic/LLM seams and the pump/send helpers.
class YoloAssistantTestEnv {
  static const micChannel = MethodChannel('yoloit/microphone_permission');

  late BoardCubit cubit;
  late Map<String, dynamic> panelState;
  late FakeRecordPlatform recordPlatform;
  late RecordPlatform originalRecordPlatform;
  late FakeChatProvider fakeProvider;
  late Directory tempHome;
  late List<String> capturedProviderTypes;
  late List<AssistantToolExecutor> capturedExecutors;
  int factoryCreations = 0;
  String? clipboardText;
  Duration? originalSecureReadTimeout;

  void setUp() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    originalSecureReadTimeout = CloudLlmSettingsService.secureReadTimeout;
    CloudLlmSettingsService.secureReadTimeout = Duration.zero;
    cubit = BoardCubit();
    panelState = <String, dynamic>{
      'messages': <Map<String, dynamic>>[],
      'activeSkills': ['Terminal', 'Board Control', 'Web Search'],
      'mode': 'text',
    };
    clipboardText = null;
    capturedProviderTypes = [];
    capturedExecutors = [];
    factoryCreations = 0;
    fakeProvider = FakeChatProvider();
    YoloAssistantWidget.debugChatProviderFactory = (providerType, executor) {
      capturedProviderTypes.add(providerType);
      capturedExecutors.add(executor);
      factoryCreations++;
      return fakeProvider;
    };
    originalRecordPlatform = RecordPlatform.instance;
    recordPlatform = FakeRecordPlatform();
    RecordPlatform.instance = recordPlatform;
    tempHome = Directory.systemTemp.createTempSync('yolo_assistant_test');
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: tempHome.path));
    // Seed the desktop credentials file mirror so credential reads resolve
    // from disk and never reach the macOS keychain (which would spawn the
    // real `security` CLI and leave its timeout timer pending).
    seedCloudConfigFile(const []);
    CloudLlmSettingsService.instance.resetForTests();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText =
            (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(micChannel, (call) async {
      switch (call.method) {
        case 'request':
          return true;
        case 'displayName':
          return 'YoLoIT Test';
        case 'bundleIdentifier':
          return 'com.yoloit.test';
        case 'status':
          return 'granted';
        case 'openSettings':
          return true;
        default:
          return null;
      }
    });
  }

  /// Writes the desktop credentials file mirror that backs
  /// `CloudLlmSettingsService.loadConfigs` on macOS/Linux.
  void seedCloudConfigFile(List<Map<String, dynamic>> configs) {
    final file = File(
      '${PlatformDirs.instance.configDir}/credentials/cloud_llm_configs_v1',
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(configs), flush: true);
  }

  /// Seeds cloud configs for both read paths of
  /// `CloudLlmSettingsService.loadConfigs`: the credentials file mirror
  /// (wins in real-async `runAsync` blocks) and the SharedPreferences
  /// fallback (wins in fake-async zones where the zero secure-read timeout
  /// fires before the file read completes).
  Future<void> seedCloudConfigs(List<Map<String, dynamic>> configs) async {
    seedCloudConfigFile(configs);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloud_llm_configs_fallback_v1', jsonEncode(configs));
  }

  void tearDown() {
    YoloAssistantWidget.debugChatProviderFactory = null;
    RecordPlatform.instance = originalRecordPlatform;
    PlatformDirs.setInstance(const MacosPlatformDirs());
    if (originalSecureReadTimeout != null) {
      CloudLlmSettingsService.secureReadTimeout = originalSecureReadTimeout!;
    }
    CloudLlmSettingsService.instance.resetForTests();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(micChannel, null);
  }

  BoardPanelInstance buildPanel() {
    return BoardPanelInstance(
      id: 'assistant-1',
      type: 'board.yolo_assistant',
      title: 'YoLo Assistant',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 420, height: 560),
      state: panelState,
    );
  }

  BoardPanelInstance notePanel(String id, String title) {
    return BoardPanelInstance(
      id: id,
      type: 'board.note.markdown',
      title: title,
      bounds: const BoardPanelBounds(x: 10, y: 10, width: 200, height: 160),
      state: {'content': '# $title\nsome note text'},
    );
  }

  Future<void> pumpAssistant(
    WidgetTester tester, {
    YoloAssistantController? controller,
    List<BoardPanelInstance> extraPanels = const [],
  }) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final board = BoardDocument(
      id: 'board-1',
      name: 'Test board',
      viewport: const BoardViewport(scale: 1),
      panels: [buildPanel(), ...extraPanels],
    );
    cubit.emit(
      BoardState(boards: [board], activeBoardId: 'board-1', isLoaded: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            // Rebuilds the assistant with the latest panel state after every
            // onUpdateState, mirroring how the board applies panel state back.
            child: StatefulBuilder(
              builder: (context, setState) {
                _hostRebuild = setState;
                return YoloAssistantWidget(
                  panel: buildPanel(),
                  controller: controller,
                  onUpdateState: (next) {
                    panelState = next;
                    _hostRebuild?.call(() {});
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void Function(void Function())? _hostRebuild;

  /// Lets the (microtask-driven) fake-provider send pipeline finish and
  /// scroll animations complete.
  Future<void> settleSend(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Like [settleSend] but also advances past the 850 ms post-transcription
  /// send delay used by the voice pipeline.
  Future<void> settleVoice(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  List<Map<String, dynamic>> messages() =>
      (panelState['messages'] as List<dynamic>).cast<Map<String, dynamic>>();

  Map<String, dynamic> cloudConfigJson(String id) => {
    'id': id,
    'name': 'openrouter',
    'baseUrl': 'https://example.test/v1',
    'apiKey': 'secret',
    'model': 'gpt-x',
    'extraHeaders': <String, String>{},
  };

  Future<void> typeAndSend(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await settleSend(tester);
  }
}
