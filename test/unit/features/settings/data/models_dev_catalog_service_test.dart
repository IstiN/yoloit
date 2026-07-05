import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/settings/data/models_dev_catalog_service.dart';

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

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('models_dev_test_');
    PlatformDirs.setInstance(_TempPlatformDirs(tmpDir.path));
    ModelsDevCatalogService.instance.resetForTesting();
  });

  tearDown(() {
    PlatformDirs.setInstance(const MacosPlatformDirs());
    tmpDir.deleteSync(recursive: true);
  });

  group('ModelsDevModel', () {
    test('isFree when both costs are zero', () {
      const model = ModelsDevModel(
        id: 'free-model',
        name: 'Free Model',
        providerId: 'opencode',
        providerName: 'OpenCode',
        inputCost: 0,
        outputCost: 0,
      );
      expect(model.isFree, isTrue);
    });

    test('isFree when both costs are null', () {
      const model = ModelsDevModel(
        id: 'unknown-model',
        name: 'Unknown Model',
        providerId: 'opencode',
        providerName: 'OpenCode',
      );
      expect(model.isFree, isFalse);
    });

    test('isFree when one cost is non-zero', () {
      const model = ModelsDevModel(
        id: 'paid-model',
        name: 'Paid Model',
        providerId: 'opencode',
        providerName: 'OpenCode',
        inputCost: 1.5,
        outputCost: 0,
      );
      expect(model.isFree, isFalse);
    });

    test('opencodeModelId formats correctly', () {
      const model = ModelsDevModel(
        id: 'gpt-4',
        name: 'GPT-4',
        providerId: 'openai',
        providerName: 'OpenAI',
      );
      expect(model.opencodeModelId, 'openai/gpt-4');
    });

    test('toChatModelInfo sets isDefault and costMultiplier for free model', () {
      const model = ModelsDevModel(
        id: 'free-model',
        name: 'Free Model',
        providerId: 'opencode',
        providerName: 'OpenCode',
        inputCost: 0,
        outputCost: 0,
        contextWindow: 128000,
      );
      final info = model.toChatModelInfo(isDefault: true);
      expect(info.id, 'opencode/free-model');
      expect(info.displayName, 'Free Model');
      expect(info.costMultiplier, 0);
      expect(info.isDefault, isTrue);
      expect(info.inputCostPerMillion, 0);
      expect(info.outputCostPerMillion, 0);
      expect(info.contextWindow, 128000);
      expect(info.providerGroup, 'OpenCode');
    });

    test('toChatModelInfo leaves costMultiplier null for paid model', () {
      const model = ModelsDevModel(
        id: 'paid-model',
        name: 'Paid Model',
        providerId: 'opencode',
        providerName: 'OpenCode',
        inputCost: 2.0,
        outputCost: 5.0,
      );
      final info = model.toChatModelInfo(isDefault: false);
      expect(info.costMultiplier, isNull);
      expect(info.isDefault, isFalse);
    });
  });

  group('ModelsDevCatalogService loading', () {
    test('loadAll returns empty list when no cache and network fails', () async {
      final models = await ModelsDevCatalogService.instance.loadAll();
      expect(models, isEmpty);
    });

    test('loadAll reads from fresh disk cache', () async {
      final cacheFile = File('${tmpDir.path}/models_dev.json');
      cacheFile.writeAsStringSync(jsonEncode({
        'opencode': {
          'name': 'OpenCode',
          'models': {
            'qwen-free': {
              'name': 'Qwen Free',
              'cost': {'input': 0, 'output': 0},
              'limit': {'context': 128000},
            },
          },
        },
      }));

      final models = await ModelsDevCatalogService.instance.loadAll();
      expect(models.length, 1);
      expect(models.first.id, 'qwen-free');
      expect(models.first.name, 'Qwen Free');
      expect(models.first.isFree, isTrue);
      expect(models.first.contextWindow, 128000);
    });

    test('isLoaded is true after successful load', () async {
      expect(ModelsDevCatalogService.instance.isLoaded, isFalse);
      final cacheFile = File('${tmpDir.path}/models_dev.json');
      cacheFile.writeAsStringSync(jsonEncode({
        'opencode': {
          'name': 'OpenCode',
          'models': {},
        },
      }));
      await ModelsDevCatalogService.instance.loadAll();
      expect(ModelsDevCatalogService.instance.isLoaded, isTrue);
    });

    test('loadAll returns memory cache on second call', () async {
      final cacheFile = File('${tmpDir.path}/models_dev.json');
      cacheFile.writeAsStringSync(jsonEncode({
        'opencode': {
          'name': 'OpenCode',
          'models': {
            'model-a': {'name': 'Model A'},
          },
        },
      }));
      final first = await ModelsDevCatalogService.instance.loadAll();
      final second = await ModelsDevCatalogService.instance.loadAll();
      expect(identical(first, second), isTrue);
    });
  });

  group('ModelsDevCatalogService parsing', () {
    test('parses multiple providers and models', () async {
      final cacheFile = File('${tmpDir.path}/models_dev.json');
      cacheFile.writeAsStringSync(jsonEncode({
        'opencode': {
          'name': 'OpenCode',
          'models': {
            'free-1': {'name': 'Free 1', 'cost': {'input': 0, 'output': 0}},
            'paid-1': {'name': 'Paid 1', 'cost': {'input': 1.0, 'output': 2.0}},
          },
        },
        'anthropic': {
          'name': 'Anthropic',
          'models': {
            'claude': {'name': 'Claude', 'cost': {'input': 3.0, 'output': 9.0}},
          },
        },
      }));

      final all = await ModelsDevCatalogService.instance.loadAll();
      expect(all.length, 3);
      expect(all.where((m) => m.providerId == 'opencode').length, 2);
      expect(all.where((m) => m.providerId == 'anthropic').length, 1);
    });

    test('handles missing optional fields with defaults', () async {
      final cacheFile = File('${tmpDir.path}/models_dev.json');
      cacheFile.writeAsStringSync(jsonEncode({
        'opencode': {
          'name': 'OpenCode',
          'models': {
            'minimal': {},
          },
        },
      }));

      final models = await ModelsDevCatalogService.instance.loadAll();
      expect(models.length, 1);
      expect(models.first.id, 'minimal');
      expect(models.first.name, 'minimal');
      expect(models.first.inputCost, isNull);
      expect(models.first.outputCost, isNull);
      expect(models.first.contextWindow, isNull);
      expect(models.first.family, isNull);
      expect(models.first.reasoning, isFalse);
      expect(models.first.attachment, isFalse);
    });

    test('skips null provider data', () async {
      final cacheFile = File('${tmpDir.path}/models_dev.json');
      cacheFile.writeAsStringSync(jsonEncode({
        'opencode': null,
        'other': {
          'name': 'Other',
          'models': {'m1': {'name': 'M1'}},
        },
      }));

      final models = await ModelsDevCatalogService.instance.loadAll();
      expect(models.length, 1);
      expect(models.first.id, 'm1');
    });

    test('skips null model data', () async {
      final cacheFile = File('${tmpDir.path}/models_dev.json');
      cacheFile.writeAsStringSync(jsonEncode({
        'opencode': {
          'name': 'OpenCode',
          'models': {
            'good': {'name': 'Good'},
            'bad': null,
          },
        },
      }));

      final models = await ModelsDevCatalogService.instance.loadAll();
      expect(models.length, 1);
      expect(models.first.id, 'good');
    });
  });

  group('ModelsDevCatalogService filtering and sorting', () {
    setUp(() async {
      final cacheFile = File('${tmpDir.path}/models_dev.json');
      cacheFile.writeAsStringSync(jsonEncode({
        'opencode': {
          'name': 'OpenCode',
          'models': {
            'z-free': {'name': 'Z Free', 'cost': {'input': 0, 'output': 0}},
            'a-free': {'name': 'A Free', 'cost': {'input': 0, 'output': 0}},
            'cheap': {'name': 'Cheap', 'cost': {'input': 1.0, 'output': 2.0}},
            'expensive': {
              'name': 'Expensive',
              'cost': {'input': 5.0, 'output': 10.0},
            },
          },
        },
        'other': {
          'name': 'Other',
          'models': {
            'other-free': {'name': 'Other Free', 'cost': {'input': 0, 'output': 0}},
            'other-paid': {'name': 'Other Paid', 'cost': {'input': 2.0, 'output': 4.0}},
          },
        },
      }));
      await ModelsDevCatalogService.instance.loadAll();
    });

    test('modelsForProvider returns only matching provider', () async {
      final opencode = await ModelsDevCatalogService.instance.modelsForProvider('opencode');
      expect(opencode.length, 4);
      final other = await ModelsDevCatalogService.instance.modelsForProvider('other');
      expect(other.length, 2);
      final missing = await ModelsDevCatalogService.instance.modelsForProvider('none');
      expect(missing, isEmpty);
    });

    test('opencodeModelsAsChatModelInfo sorts free first then paid by cost', () async {
      final infos = await ModelsDevCatalogService.instance.opencodeModelsAsChatModelInfo();
      expect(infos.length, 4);
      expect(infos[0].displayName, 'A Free');
      expect(infos[1].displayName, 'Z Free');
      expect(infos[2].displayName, 'Cheap');
      expect(infos[3].displayName, 'Expensive');
      expect(infos[0].isDefault, isTrue);
      expect(infos[1].isDefault, isFalse);
      expect(infos[0].costMultiplier, 0);
      expect(infos[2].costMultiplier, isNull);
    });

    test('opencodeModelsWithAuth includes free opencode and configured providers', () async {
      final infos = await ModelsDevCatalogService.instance.opencodeModelsWithAuth(
        configuredProviderIds: ['other'],
      );
      expect(infos.length, 4);
      expect(infos[0].displayName, 'A Free');
      expect(infos[1].displayName, 'Z Free');
      expect(infos[2].displayName, 'Other Free');
      expect(infos[3].displayName, 'Other Paid');
      expect(infos[0].isDefault, isTrue);
    });

    test('opencodeModelsWithAuth skips opencode in configuredProviderIds', () async {
      final infos = await ModelsDevCatalogService.instance.opencodeModelsWithAuth(
        configuredProviderIds: ['opencode'],
      );
      expect(infos.length, 2);
      expect(infos.every((i) => i.id.startsWith('opencode/')), isTrue);
    });
  });
}
