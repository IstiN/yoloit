import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/core/utils/http_client_base.dart';
import 'package:yoloit/features/board/widgets/widget_file_reader_web.dart';
import 'package:yoloit/features/board/widgets/widget_registry_service_web.dart';
import 'package:yoloit/features/board/widgets/widget_remote_source.dart';

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
  Future<void> appendString(String path, String contents) async {
    _strings[path] = (_strings[path] ?? '') + contents;
  }

  @override
  Future<int?> length(String path) async =>
      _strings[path]?.length ?? _bytes[path]?.length;

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

class _FakeHttpClient implements YoloitHttpClient {
  final Map<String, String> _responses;

  _FakeHttpClient(this._responses);

  @override
  Future<String?> getString(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  }) async =>
      _responses[url];

  @override
  Future<Map<String, dynamic>?> getJson(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final text = _responses[url];
    if (text == null) return null;
    return null; // not used by widget remote source
  }

  @override
  Future<Stream<List<int>>> postJsonStream(
    String url, {
    required Object? body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  }) async =>
      throw UnimplementedError();

  @override
  void close() {}
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
          'widget.js': 'jsr.render({type:"text", data:"0"});',
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

    test('loadAll fetches examples from remote source when storage is empty',
        () async {
      final storage = _FakeStorage();
      final client = _FakeHttpClient({
        'https://raw.githubusercontent.com/IstiN/yoloit/main/tools/widgets/weather/manifest.json':
            '{"name":"Remote Weather","icon":"🌦️"}',
        'https://raw.githubusercontent.com/IstiN/yoloit/main/tools/widgets/weather/widget.js':
            '// remote weather',
      });
      final remote = WidgetRemoteSource(client: client);
      final service = WidgetRegistryService.testInstance(
        adapter: storage,
        remoteSource: remote,
      );

      final all = await service.loadAll();
      expect(all.length, 1);
      expect(all.first.name, 'Remote Weather');
      expect(all.first.id, 'weather');

      final manifest = await WidgetManifest.fromStorage(
        'widgets/weather',
        reader: WebWidgetFileReader(adapter: storage),
      );
      expect(manifest, isNotNull);
      expect(
        await manifest!.readJs(reader: WebWidgetFileReader(adapter: storage)),
        '// remote weather',
      );
    });

    test('loadAll falls back to assets when remote source returns nothing',
        () async {
      final storage = _FakeStorage();
      final client = _FakeHttpClient({});
      final remote = WidgetRemoteSource(client: client);
      final service = WidgetRegistryService.testInstance(
        adapter: storage,
        remoteSource: remote,
      );

      // Remote returns nothing, so the service falls back to bundled Flutter
      // assets. In the unit-test environment those assets are available.
      final all = await service.loadAll();
      expect(all, isNotEmpty);
      final ids = all.map((m) => m.id).toSet();
      for (final name in WidgetRemoteSource.exampleNames) {
        expect(ids, contains(name));
      }
    });
  });

  group('WidgetRemoteSource', () {
    test('fetchWidget returns null when manifest is missing', () async {
      final client = _FakeHttpClient({});
      final source = WidgetRemoteSource(client: client);
      expect(await source.fetchWidget('weather'), isNull);
    });

    test('fetchWidget returns null when widget.js is missing', () async {
      final client = _FakeHttpClient({
        'https://raw.githubusercontent.com/IstiN/yoloit/main/tools/widgets/x/manifest.json':
            '{"name":"X"}',
      });
      final source = WidgetRemoteSource(client: client);
      expect(await source.fetchWidget('x'), isNull);
    });

    test('fetchWidget returns files from manifest and widget.js', () async {
      final client = _FakeHttpClient({
        'https://raw.githubusercontent.com/IstiN/yoloit/main/tools/widgets/calc/manifest.json':
            '{"name":"Calc","files":["lib/a.js","widget.js"]}',
        'https://raw.githubusercontent.com/IstiN/yoloit/main/tools/widgets/calc/lib/a.js':
            '// a',
        'https://raw.githubusercontent.com/IstiN/yoloit/main/tools/widgets/calc/widget.js':
            '// calc',
      });
      final source = WidgetRemoteSource(client: client);
      final files = await source.fetchWidget('calc');
      expect(files, isNotNull);
      expect(files!['manifest.json'], isNotNull);
      expect(files['lib/a.js'], '// a');
      expect(files['widget.js'], '// calc');
    });

    test('fetchAllExamples skips individual failures', () async {
      final client = _FakeHttpClient({
        'https://raw.githubusercontent.com/IstiN/yoloit/main/tools/widgets/weather/manifest.json':
            '{"name":"Weather"}',
        'https://raw.githubusercontent.com/IstiN/yoloit/main/tools/widgets/weather/widget.js':
            '// weather',
      });
      final source = WidgetRemoteSource(client: client);
      final all = await source.fetchAllExamples();
      expect(all.length, 1);
      expect(all['weather'], isNotNull);
    });
  });
}
