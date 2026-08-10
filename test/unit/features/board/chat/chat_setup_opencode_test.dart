import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/widgets/chat_setup_view_vm.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/models_dev_catalog_service.dart';

/// A PlatformDirs that points all directories to a temp folder so that
/// OpenCodeAuthService (reads ~/.local/share/opencode/auth.json) and
/// ModelsDevCatalogService (caches to configDir/models_dev.json) stay
/// self-contained inside the test sandbox.
class _TempPlatformDirs extends PlatformDirs {
  _TempPlatformDirs(this._tmpDir);
  final String _tmpDir;

  @override
  String get configDir => _tmpDir;

  @override
  String get dataDir => _tmpDir;

  @override
  String get logsDir => _tmpDir;

  @override
  String get tempDir => _tmpDir;

  @override
  String get skillsDir => '$_tmpDir/skills';

  @override
  String get yoloitTempDir => '$_tmpDir/tmp';
}

/// Blocks all real HTTP requests in the test zone by returning a client
/// whose every method throws, so ModelsDevCatalogService._fetchRemote
/// returns null fast instead of hanging on the network.
class _BlockingHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _ThrowingHttpClient();
}

class _ThrowingHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw SocketException('HTTP blocked in test');
  }
}

const _opencodeConfig = AgentConfig(
  id: 'opencode',
  displayName: 'OpenCode',
  iconLabel: 'OC',
  launchCommand: 'opencode',
  visible: true,
  isBuiltIn: true,
  streamAdapter: 'opencode',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('chat_setup_opencode_');
    PlatformDirs.setInstance(_TempPlatformDirs(tmpDir.path));
    ModelsDevCatalogService.instance.resetForTesting();
    await AgentConfigService.instance.save([_opencodeConfig]);
    // Block all real HTTP so models.dev fetch returns null instantly.
    HttpOverrides.global = _BlockingHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = null;
    PlatformDirs.setInstance(const MacosPlatformDirs());
    tmpDir.deleteSync(recursive: true);
  });

  Widget buildApp({
    required ChatSessionConfig config,
    ValueChanged<ChatSessionConfig>? onStart,
  }) =>
      BlocProvider<BoardCubit>(
        create: (_) => BoardCubit(),
        child: MaterialApp(
          theme: AppThemePreset.neonPurple.theme.copyWith(
            extensions: [AppColorScheme.fromAccent(const Color(0xFF7C6BFF))],
          ),
          home: Scaffold(
            body: ChatSetupView(
              panelId: 'panel-1',
              config: config,
              models: const [],
              onStart: onStart ?? (_) {},
            ),
          ),
        ),
      );

  testWidgets(
      '_loadOpencodeModels runs on init and falls back to kOpencodeModels',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        buildApp(
          config: const ChatSessionConfig(
            sessionName: 's',
            workingDir: '/tmp',
            provider: 'opencode',
            model: 'opencode/qwen3.6-plus-free',
          ),
        ),
      );

      // Let _loadOpencodeModels settle — it awaits two service calls.
      // The HTTP override makes _fetchRemote return null fast.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }

      // No auth.json and no models.dev cache exist → the services return
      // empty/fallback lists. _opencodeModels stays null so the hardcoded
      // kOpencodeModels fallback default model is rendered.
      expect(find.text('Qwen 3.6 Plus (Free)'), findsOneWidget);
      expect(find.byType(ChatSetupView), findsOneWidget);
    });
  });

  testWidgets('_loadOpencodeModels does not crash when services throw',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        buildApp(
          config: const ChatSessionConfig(
            sessionName: 's',
            workingDir: '/tmp',
            provider: 'opencode',
            model: 'opencode/qwen3.6-plus-free',
          ),
        ),
      );

      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }

      // Even after errors the widget renders normally with the fallback.
      expect(find.byType(ChatSetupView), findsOneWidget);
      expect(find.text('Qwen 3.6 Plus (Free)'), findsOneWidget);
    });
  });

  testWidgets('_loadOpencodeModels handles non-default model gracefully',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        buildApp(
          config: const ChatSessionConfig(
            sessionName: 's',
            workingDir: '/tmp',
            provider: 'opencode',
            // An arbitrary model id that does not exist in kOpencodeModels.
            // _loadOpencodeModels runs in initState; since the services fail,
            // _opencodeModels stays null and the fallback kOpencodeModels is
            // used by _modelsForProvider.
            model: 'some-unknown-model',
          ),
        ),
      );

      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }

      // The widget renders without crashing — _loadOpencodeModels's catch
      // block swallows the service error.
      expect(find.byType(ChatSetupView), findsOneWidget);
    });
  });
}
