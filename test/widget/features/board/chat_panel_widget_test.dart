import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('unconfigured chat panel shows setup even with saved messages', (
    tester,
  ) async {
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    final panel = BoardPanelInstance(
      id: 'chat-panel',
      type: ChatPanelPlugin.kTypeId,
      title: 'AI Chat',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 420, height: 500),
      state: {
        'configured': false,
        'config':
            const ChatSessionConfig(sessionName: '', workingDir: '').toJson(),
        'messages': [
          ChatMessage(
            id: 'msg-old',
            role: ChatRole.user,
            content: 'привет',
            timestamp: DateTime.utc(2026, 6, 2),
          ).toJson(),
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: SizedBox(
              width: 520,
              height: 620,
              child: ChatPanelWidget(panel: panel, onUpdateState: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('Start Chat'), findsOneWidget);
    expect(find.text('Message...'), findsNothing);
  });
}
