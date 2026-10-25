import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/core/platform/file_storage_adapter_vm.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/models/terminal_backend_mode.dart';

void main() {
  test('default Copilot board chat command uses supported flags', () {
    final command = AgentConfigService.defaultBoardChatCommand('copilot');

    expect(command, 'copilot --output-format json');
    expect(command, isNot(contains('--yolo')));
  });

  group('AgentConfigService.load', () {
    final originalDirs = PlatformDirs.instance;
    final originalStorage = FileStorageAdapter.instance;
    late Directory tempDir;
    late AgentConfigService service;
    late String configPath;
    late String prefsPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('agent-config-test-');
      PlatformDirs.setInstance(
        MacosPlatformDirs(homeOverride: tempDir.path),
      );
      FileStorageAdapter.setInstanceForTest(const VmFileStorageAdapter());
      service = AgentConfigService.forTesting();
      configPath = p.join(
        PlatformDirs.instance.configDir,
        'agent_configs.json',
      );
      prefsPath = p.join(
        PlatformDirs.instance.configDir,
        'agent_prefs.json',
      );
    });

    tearDown(() async {
      service.terminalBackendModeNotifier.dispose();
      service.terminalRenderEngineNotifier.dispose();
      PlatformDirs.setInstance(originalDirs);
      FileStorageAdapter.setInstanceForTest(originalStorage);
      await tempDir.delete(recursive: true);
    });

    Future<void> writeJson(String path, Object? value) async {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(value));
    }

    Future<void> writeRaw(String path, String value) async {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(value);
    }

    Future<Map<String, dynamic>> readPrefs() async {
      final raw = await File(prefsPath).readAsString();
      return jsonDecode(raw) as Map<String, dynamic>;
    }

    Map<String, dynamic> savedConfig(
      String id, {
      String? launchCommand,
      String? streamAdapter,
      bool visible = true,
      bool disableModel = false,
    }) {
      return AgentConfig(
        id: id,
        displayName: 'Saved $id',
        iconLabel: 'S',
        launchCommand: launchCommand ?? '$id-custom',
        visible: visible,
        isBuiltIn: true,
        streamAdapter: streamAdapter,
        disableModel: disableModel,
      ).toJson();
    }

    test('loads defaults for missing files and caches the config path', () async {
      final configs = await service.load();

      expect(configs, hasLength(9));
      expect(
        configs.map((config) => config.id),
        containsAll([
          'copilot',
          'claude',
          'gemini',
          'cursor',
          'pi',
          'terminal',
          'opencode',
          'kimi',
          'codex',
        ]),
      );
      expect(service.defaultAgentId, isNull);
      expect(service.defaultAsrMode, 'cloud');
      expect(service.terminalBackendMode, TerminalBackendMode.runtime);
      expect(
        service.terminalBackendModeNotifier.value,
        TerminalBackendMode.runtime,
      );

      await writeJson(configPath, [savedConfig('custom')]);
      final cached = await service.load();
      expect(cached.map((config) => config.id), isNot(contains('custom')));
    });

    test('saved values win while built-ins are merged and migrated', () async {
      await writeJson(configPath, [
        savedConfig(
          'cursor',
          launchCommand: 'cursor-from-disk',
          visible: false,
        ),
        savedConfig('codex', disableModel: true),
        savedConfig('custom', launchCommand: 'first-custom'),
        savedConfig('custom', launchCommand: 'last-custom'),
        savedConfig('copilot', streamAdapter: 'custom-copilot'),
      ]);

      final configs = await service.load();

      expect(configs, hasLength(10));
      expect(configs.map((config) => config.id), [
        'cursor',
        'codex',
        'custom',
        'copilot',
        'claude',
        'gemini',
        'pi',
        'terminal',
        'opencode',
        'kimi',
      ]);
      final cursor = service.configForAgent('cursor')!;
      expect(cursor.launchCommand, 'cursor-from-disk');
      expect(cursor.displayName, 'Saved cursor');
      expect(cursor.visible, isFalse);
      expect(cursor.streamAdapter, 'cursor');
      expect(service.configForAgent('codex')!.streamAdapter, 'codex');
      expect(service.configForAgent('codex')!.disableModel, isFalse);
      expect(service.configForAgent('custom')!.launchCommand, 'last-custom');
      expect(service.configForAgent('custom')!.streamAdapter, isNull);
      expect(
        service.configForAgent('copilot')!.streamAdapter,
        'custom-copilot',
      );
    });

    test('malformed config falls back to defaults without losing prefs', () async {
      await writeRaw(configPath, '{not-json');
      await writeJson(prefsPath, {
        'defaultAgentId': 'cursor',
        'defaultAsrMode': 'local',
        'defaultAsrCloudConfigId': 'cloud-config',
        'defaultAsrCloudModel': 'whisper-1',
        'terminalBackendMode': 'tmux',
      });

      final configs = await service.load();

      expect(configs, hasLength(9));
      expect(configs.every((config) => config.isBuiltIn), isTrue);
      expect(service.defaultAgentId, 'cursor');
      expect(service.defaultAsrMode, 'cloud');
      expect(service.defaultAsrCloudConfigId, 'cloud-config');
      expect(service.defaultAsrCloudModel, 'whisper-1');
      expect(service.terminalBackendMode, TerminalBackendMode.tmux);
      expect(
        service.terminalBackendModeNotifier.value,
        TerminalBackendMode.tmux,
      );

      final migratedPrefs = await readPrefs();
      expect(migratedPrefs['defaultAgentId'], 'cursor');
      expect(migratedPrefs['defaultAsrMode'], 'cloud');
      expect(migratedPrefs['defaultAsrCloudConfigId'], 'cloud-config');
      expect(migratedPrefs['defaultAsrCloudModel'], 'whisper-1');
      // ASR migration is saved before the backend preference is applied.
      expect(migratedPrefs['terminalBackendMode'], isNull);
    });

    test('empty saved configs and prefs retain default fallbacks', () async {
      await writeJson(configPath, <Object?>[]);
      await writeJson(prefsPath, <String, Object?>{});

      final configs = await service.load();

      expect(configs, hasLength(9));
      expect(service.defaultAgentId, isNull);
      expect(service.defaultAsrMode, 'cloud');
      expect(service.defaultAsrCloudConfigId, isNull);
      expect(service.defaultAsrCloudModel, isNull);
      expect(service.terminalBackendMode, TerminalBackendMode.runtime);
      expect((await readPrefs())['defaultAsrMode'], 'cloud');
    });

    test('malformed prefs are ignored after saved configs load', () async {
      await writeJson(configPath, [savedConfig('custom')]);
      await writeRaw(prefsPath, '[not-json');

      final configs = await service.load();

      expect(service.configForAgent('custom'), isNotNull);
      expect(configs, hasLength(10));
      expect(service.defaultAgentId, isNull);
      expect(service.defaultAsrMode, 'cloud');
      expect(service.terminalBackendMode, TerminalBackendMode.runtime);
      expect(
        service.terminalBackendModeNotifier.value,
        TerminalBackendMode.runtime,
      );
    });
  });
}
