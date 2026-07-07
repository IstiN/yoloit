import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/features/board/widgets/widget_registry_service_web.dart';

class _FakeStorage implements FileStorageAdapter {
  final _strings = <String, String>{};
  final _bytes = <String, Uint8List>{};

  @override
  Future<bool> exists(String path) async =>
      _strings.containsKey(path) || _bytes.containsKey(path);

  @override
  Future<String?> readString(String path) async => _strings[path];

  @override
  Future<Uint8List?> readBytes(String path) async => _bytes[path];

  @override
  Future<void> writeString(String path, String contents) async {
    _strings[path] = contents;
  }

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    _bytes[path] = bytes;
  }

  @override
  Future<void> delete(String path) async {
    _strings.remove(path);
    _bytes.remove(path);
  }

  @override
  Future<List<String>> list(String directoryPath) async {
    final prefix =
        directoryPath.endsWith('/') ? directoryPath : '$directoryPath/';
    return _strings.keys
        .followedBy(_bytes.keys)
        .where((k) => k.startsWith(prefix))
        .toSet()
        .toList();
  }
}

void main() {
  group('WidgetRegistryServiceWeb', () {
    test('installFromFiles writes files and find returns manifest', () async {
      final storage = _FakeStorage();
      final service = WidgetRegistryService.testInstance(adapter: storage);
      final manifest = await service.installFromFiles(
        id: 'counter',
        files: {
          'manifest.json': '{"name":"Counter","icon":"🔢"}',
          'widget.js': 'yoloit.render({type:"text", data:"0"});',
        },
      );
      expect(manifest, isNotNull);
      expect(manifest!.id, 'counter');
      expect(manifest.name, 'Counter');

      final found = await service.find('counter');
      expect(found, isNotNull);
      expect(found!.name, 'Counter');
    });

    test('install returns null for filesystem paths on web', () async {
      final service = WidgetRegistryService.testInstance(
        adapter: _FakeStorage(),
      );
      expect(await service.install('/some/path'), isNull);
    });

    test('remove deletes all widget files', () async {
      final storage = _FakeStorage();
      final service = WidgetRegistryService.testInstance(adapter: storage);
      await service.installFromFiles(
        id: 'todo',
        files: {
          'manifest.json': '{"name":"Todo"}',
          'widget.js': '// todo',
        },
      );
      expect(await service.find('todo'), isNotNull);

      final removed = await service.remove('todo');
      expect(removed, isTrue);
      expect(await service.find('todo'), isNull);
    });

    test('loadAll returns installed widgets sorted by name', () async {
      final storage = _FakeStorage();
      final service = WidgetRegistryService.testInstance(adapter: storage);
      await service.installFromFiles(
        id: 'zoo',
        files: {
          'manifest.json': '{"name":"Zoo"}',
          'widget.js': '// zoo',
        },
      );
      await service.installFromFiles(
        id: 'alpha',
        files: {
          'manifest.json': '{"name":"Alpha"}',
          'widget.js': '// alpha',
        },
      );
      final all = await service.loadAll();
      expect(all.map((m) => m.name).toList(), ['Alpha', 'Zoo']);
    });
  });
}
