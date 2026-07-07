import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/features/board/widgets/widget_manifest.dart';

class _FakeStorage implements FileStorageAdapter {
  final _strings = <String, String>{};

  void setString(String path, String value) => _strings[path] = value;

  @override
  Future<bool> exists(String path) async => _strings.containsKey(path);

  @override
  Future<String?> readString(String path) async => _strings[path];

  @override
  Future<Uint8List?> readBytes(String path) async => null;

  @override
  Future<void> writeString(String path, String contents) async {
    _strings[path] = contents;
  }

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {}

  @override
  Future<void> delete(String path) async {
    _strings.remove(path);
  }

  @override
  Future<List<String>> list(String directoryPath) async {
    final prefix =
        directoryPath.endsWith('/') ? directoryPath : '$directoryPath/';
    return _strings.keys.where((k) => k.startsWith(prefix)).toList();
  }
}

void main() {
  group('WidgetManifest', () {
    test('fromStorage returns null when widget.js is missing', () async {
      final storage = _FakeStorage();
      storage.setString('widgets/x/manifest.json', '{"name":"X"}');
      final manifest = await WidgetManifest.fromStorage(
        'widgets/x',
        adapter: storage,
      );
      expect(manifest, isNull);
    });

    test('fromStorage reads manifest.json and derives defaults', () async {
      final storage = _FakeStorage()
        ..setString('widgets/weather/widget.js', 'console.log(1);')
        ..setString(
          'widgets/weather/manifest.json',
          '{"name":"Weather","icon":"🌤️","allowedCommands":["*"]}',
        );
      final manifest = await WidgetManifest.fromStorage(
        'widgets/weather',
        adapter: storage,
      );
      expect(manifest, isNotNull);
      expect(manifest!.id, 'weather');
      expect(manifest.name, 'Weather');
      expect(manifest.icon, '🌤️');
      expect(manifest.allowedCommands, ['*']);
      expect(manifest.widgetPath, 'widgets/weather');
      expect(manifest.mainJsPath, 'widgets/weather/widget.js');
    });

    test('readJs returns widget.js source', () async {
      final storage = _FakeStorage()
        ..setString('widgets/calc/widget.js', 'var x = 1;');
      final manifest = await WidgetManifest.fromStorage(
        'widgets/calc',
        adapter: storage,
      );
      expect(await manifest!.readJs(adapter: storage), 'var x = 1;');
    });

    test('readJs concatenates files in order', () async {
      final storage = _FakeStorage()
        ..setString('widgets/app/widget.js', '// main')
        ..setString('widgets/app/src/a.js', '// a')
        ..setString('widgets/app/src/b.js', '// b');
      final manifest = await WidgetManifest.fromStorage(
        'widgets/app',
        adapter: storage,
      );
      final withFiles = WidgetManifest(
        id: 'app',
        name: 'App',
        description: '',
        version: '1.0.0',
        icon: '🔧',
        allowedCommands: const [],
        networkEnabled: true,
        widgetPath: 'widgets/app',
        isSingleFile: false,
        files: const ['src/a.js', 'src/b.js'],
      );
      final js = await withFiles.readJs(adapter: storage);
      expect(js, '// a\n// b');
    });

    test('readJs preprocesses yoloit.include calls', () async {
      final storage = _FakeStorage()
        ..setString('widgets/inc/widget.js', "yoloit.include('lib/util.js')")
        ..setString('widgets/inc/lib/util.js', 'var u = 2;');
      final manifest = await WidgetManifest.fromStorage(
        'widgets/inc',
        adapter: storage,
      );
      final js = await manifest!.readJs(adapter: storage);
      expect(js, 'var u = 2;');
    });

    test('appDir returns parent for single-file widgets', () {
      final manifest = WidgetManifest.fromJsFilePath('widgets/single/widget.js');
      expect(manifest.appDir, 'widgets/single');
      expect(manifest.isSingleFile, isTrue);
    });
  });
}
