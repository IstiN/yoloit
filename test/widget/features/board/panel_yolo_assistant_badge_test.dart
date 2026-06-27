import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/ui/panel_yolo_assistant_badge.dart';
import 'package:yoloit/features/board/ui/yolo_anchored_assistant_panel.dart';

Widget _badgeShell({
  required BoardCubit cubit,
  required BoardPanelInstance targetPanel,
  bool assistantOpen = false,
}) {
  return MaterialApp(
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(
      body: BlocProvider.value(
        value: cubit,
        child: Stack(
          children: [
            const SizedBox.expand(),
            Positioned(
              left: 20,
              top: 20,
              width: PanelYoloAssistantBadge.hitWidth,
              height: PanelYoloAssistantBadge.minTriggerHeight,
              child: PanelYoloAssistantBadge(
                targetPanel: targetPanel,
                assistantOpen: assistantOpen,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _anchoredShell({
  required BoardCubit cubit,
  required BoardPanelInstance targetPanel,
  Widget Function(
    BoardPanelInstance assistantPanel,
    ValueChanged<Map<String, dynamic>> onUpdateState,
  )? chatBuilder,
}) {
  final controller = ChatPanelController();
  cubit.openYoloAssistant(targetPanel.id);
  return MaterialApp(
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(
      body: BlocProvider.value(
        value: cubit,
        child: SizedBox(
          width: 900,
          height: 700,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            YoloAnchoredAssistantPanel(
              anchorPanel: targetPanel,
              canvasOrigin: Offset.zero,
              chatController: controller,
              startMic: false,
              onStartMicConsumed: () {},
              onClose: cubit.closeYoloAssistant,
              chatBuilder: chatBuilder,
            ),
          ],
        ),
        ),
      ),
    ),
  );
}

class _Fixture {
  _Fixture(this.cubit, this.targetPanel);

  final BoardCubit cubit;
  final BoardPanelInstance targetPanel;
}

_Fixture _createFixture({Map<String, dynamic> targetState = const {}}) {
  final cubit = BoardCubit();
  final targetPanel = BoardPanelInstance(
    id: 'target',
    type: MarkdownNotePlugin.kTypeId,
    title: 'Focus panel',
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 400, height: 400),
    state: targetState,
  );
  final board = BoardDocument(
    id: 'board',
    name: 'Board',
    viewport: const BoardViewport(scale: 1),
    panels: [targetPanel],
  );
  cubit.emit(
    BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
  );
  return _Fixture(cubit, targetPanel);
}

void _seedCloudOpenRouter() {
  FlutterSecureStorage.setMockInitialValues({
    'cloud_llm_configs_v1': jsonEncode([
      {
        'id': 'openrouter',
        'name': 'OpenRouter',
        'baseUrl': 'https://openrouter.ai/api/v1',
        'apiKey': 'sk-test',
        'model': 'openrouter/google/gemma-4-31b-it',
        'extraHeaders': <String, String>{},
      },
    ]),
  });
  SharedPreferences.setMockInitialValues({
    'cloud_llm_active_config_v1': 'openrouter',
  });
}

Future<BoardPanelInstance> _captureAssistantPanel(
  WidgetTester tester,
  BoardCubit cubit,
  BoardPanelInstance targetPanel,
) async {
  BoardPanelInstance? captured;
  await tester.pumpWidget(
    _anchoredShell(
      cubit: cubit,
      targetPanel: targetPanel,
      chatBuilder: (panel, onUpdate) {
        captured = panel;
        return const SizedBox.shrink();
      },
    ),
  );
  await tester.pump();
  for (var i = 0; i < 30 && captured == null; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return captured!;
}

ChatSessionConfig _configOf(BoardPanelInstance panel) => ChatSessionConfig.fromJson(
  Map<String, dynamic>.from(panel.state['config'] as Map),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('PanelYoloAssistantBadge', () {
    testWidgets('collapsed badge opens anchored assistant on tap', (tester) async {
      final fixture = _createFixture();
      await tester.pumpWidget(
        _badgeShell(
          cubit: fixture.cubit,
          targetPanel: fixture.targetPanel,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.bySemanticsLabel('Ask YoLo about this panel'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsLabel('Ask YoLo about this panel'));
      await tester.pump();

      expect(fixture.cubit.state.yoloAssistantAnchorPanelId, 'target');
    });

    testWidgets('focuses message input when anchored assistant opens', (
      tester,
    ) async {
      final fixture = _createFixture();
      await tester.pumpWidget(
        _anchoredShell(
          cubit: fixture.cubit,
          targetPanel: fixture.targetPanel,
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      final messageField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Message…',
      );
      expect(messageField, findsOneWidget);
      expect(tester.widget<TextField>(messageField).focusNode?.hasFocus, isTrue);
    });

    testWidgets('persists assistant state into target panel', (tester) async {
      final fixture = _createFixture();

      ValueChanged<Map<String, dynamic>>? capturedOnUpdate;
      await tester.pumpWidget(
        _anchoredShell(
          cubit: fixture.cubit,
          targetPanel: fixture.targetPanel,
          chatBuilder: (panel, onUpdate) {
            capturedOnUpdate = onUpdate;
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump();
      for (var i = 0; i < 30 && capturedOnUpdate == null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(capturedOnUpdate, isNotNull);
      capturedOnUpdate!({
        'messages': <Map<String, dynamic>>[],
        'configured': true,
      });
      await tester.pump();

      final updated = fixture.cubit.state.activeBoard!.panels.singleWhere(
        (p) => p.id == 'target',
      );
      final assistantState =
          updated.state['yoloAssistant'] as Map<String, dynamic>?;
      expect(assistantState, isNotNull);
      expect(assistantState!['messages'], isEmpty);
    });

    testWidgets('creates chat-configured assistant panel', (tester) async {
      final fixture = _createFixture();
      final captured = await _captureAssistantPanel(
        tester,
        fixture.cubit,
        fixture.targetPanel,
      );

      expect(captured.type, ChatPanelPlugin.kTypeId);
      expect(captured.state['configured'], isTrue);
      expect(captured.state['targetPanelId'], 'target');
      expect(_configOf(captured).provider, 'cloud:openrouter');
    });

    testWidgets(
      'keeps cloud provider when active config lacks api key',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'cloud_llm_active_config_v1': 'openrouter',
          'assistant_provider_type_v1': 'cloud',
        });
        FlutterSecureStorage.setMockInitialValues({
          'cloud_llm_configs_v1': jsonEncode([
            {
              'id': 'openrouter',
              'name': 'OpenRouter',
              'baseUrl': 'https://openrouter.ai/api/v1',
              'apiKey': '',
              'model': 'openrouter/google/gemma-4-31b-it',
              'extraHeaders': <String, String>{},
            },
          ]),
        });
        final fixture = _createFixture(
          targetState: {
            'yoloAssistant': {
              'configured': true,
              'assistantProviderResolved': true,
              'config': {
                'sessionName': 'saved',
                'workingDir': '/tmp',
                'provider': 'cloud:openrouter',
                'model': 'openrouter/google/gemma-4-31b-it',
              },
            },
          },
        );
        final captured = await _captureAssistantPanel(
          tester,
          fixture.cubit,
          fixture.targetPanel,
        );

        expect(_configOf(captured).provider, 'cloud:openrouter');
      },
    );

    testWidgets('restores persisted provider config', (tester) async {
      final fixture = _createFixture(
        targetState: {
          'yoloAssistant': {
            'configured': true,
            'config': {
              'sessionName': 'saved',
              'workingDir': '/tmp',
              'provider': 'copilot',
              'model': 'gpt-5-mini',
            },
          },
        },
      );
      final captured = await _captureAssistantPanel(
        tester,
        fixture.cubit,
        fixture.targetPanel,
      );

      final config = _configOf(captured);
      expect(config.provider, 'cloud:openrouter');
      expect(config.sessionName, 'saved');
    });

    testWidgets(
      'migrates unresolved local provider to cloud default',
      (tester) async {
        _seedCloudOpenRouter();
        final fixture = _createFixture(
          targetState: {
            'yoloAssistant': {
              'configured': true,
              'config': {
                'sessionName': 'saved',
                'workingDir': '/tmp',
                'provider': 'local',
                'model': 'gemma4-e2b-it-4bit',
              },
            },
          },
        );
        final captured = await _captureAssistantPanel(
          tester,
          fixture.cubit,
          fixture.targetPanel,
        );

        final config = _configOf(captured);
        expect(config.provider, 'cloud:openrouter');
        expect(config.model, 'openrouter/google/gemma-4-31b-it');
        expect(config.sessionName, 'saved');
        expect(captured.state['assistantProviderResolved'], isTrue);

        final updatedTarget =
            fixture.cubit.state.activeBoard!.panels.singleWhere(
          (p) => p.id == 'target',
        );
        final persistedAssistant =
            updatedTarget.state['yoloAssistant'] as Map<String, dynamic>?;
        expect(persistedAssistant, isNotNull);
        expect(
          _configOf(
            BoardPanelInstance(
              id: 'x',
              type: MarkdownNotePlugin.kTypeId,
              title: '',
              bounds: const BoardPanelBounds(
                x: 0,
                y: 0,
                width: 0,
                height: 0,
              ),
              state: {'config': persistedAssistant!['config']},
            ),
          ).provider,
          'cloud:openrouter',
        );
      },
    );

    testWidgets(
      'keeps cloud provider once assistantProviderResolved is true',
      (tester) async {
        _seedCloudOpenRouter();
        final fixture = _createFixture(
          targetState: {
            'yoloAssistant': {
              'configured': true,
              'assistantProviderResolved': true,
              'config': {
                'sessionName': 'saved',
                'workingDir': '/tmp',
                'provider': 'cloud:openrouter',
                'model': 'openrouter/google/gemma-4-31b-it',
              },
            },
          },
        );
        final captured = await _captureAssistantPanel(
          tester,
          fixture.cubit,
          fixture.targetPanel,
        );

        expect(_configOf(captured).provider, 'cloud:openrouter');
      },
    );

    testWidgets('copy history button copies messages to clipboard', (tester) async {
      SystemChannels.platform.setMockMethodCallHandler((call) async {
        if (call.method == 'Clipboard.setData') return null;
        return null;
      });
      addTearDown(
        () => SystemChannels.platform.setMockMethodCallHandler(null),
      );

      final fixture = _createFixture(
        targetState: {
          'yoloAssistant': {
            'configured': true,
            'assistantProviderResolved': true,
            'messages': [
              {
                'id': 'm1',
                'role': 'user',
                'content': 'Hello',
                'timestamp': '2026-06-22T10:00:00.000Z',
                'toolCalls': [],
                'attachments': [],
              },
              {
                'id': 'm2',
                'role': 'assistant',
                'content': 'Hi there',
                'timestamp': '2026-06-22T10:00:01.000Z',
                'toolCalls': [],
                'attachments': [],
              },
            ],
            'config': {
              'sessionName': 'saved',
              'workingDir': '/tmp',
              'provider': 'cloud:openrouter',
              'model': 'openrouter/google/gemma-4-31b-it',
            },
          },
        },
      );
      await _captureAssistantPanel(
        tester,
        fixture.cubit,
        fixture.targetPanel,
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byTooltip('Copy YoLo history'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('YoLo history copied to clipboard'), findsOneWidget);
    });
  });
}
