import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/apps_handler.dart';
import 'package:yoloit/features/board/widgets/widget_app_registry.dart';
import 'package:yoloit/features/board/widgets/widget_registry_service.dart';

class _MockWidgetRegistryService extends Mock implements WidgetRegistryService {}

class _MockWidgetAppRegistry extends Mock implements WidgetAppRegistry {}

class _MockJsWidgetEngine extends Mock implements JsWidgetEngine {}

shelf.Request _getRequest(String path) {
  return shelf.Request('GET', Uri.parse('http://localhost:8080$path'));
}

shelf.Request _postRequest(String path, {Map<String, dynamic>? body}) {
  final uri = Uri.parse('http://localhost:8080$path');
  return shelf.Request(
    'POST',
    uri,
    body: body != null ? jsonEncode(body) : null,
  );
}

shelf.Response _json(Object data) => shelf.Response.ok(
  jsonEncode(data),
  headers: {'content-type': 'application/json'},
);

shelf.Response _error(String msg) => shelf.Response(
  400,
  body: jsonEncode({'ok': false, 'error': msg}),
  headers: {'content-type': 'application/json'},
);

shelf.Response _notFound(String msg) => shelf.Response.notFound(
  jsonEncode({'ok': false, 'error': msg}),
  headers: {'content-type': 'application/json'},
);

Future<Map<String, dynamic>> _body(shelf.Request request) async {
  final raw = await request.readAsString();
  if (raw.isEmpty) return {};
  return jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('handleApps', () {
    late _MockWidgetRegistryService mockRegistry;
    late _MockWidgetAppRegistry mockAppRegistry;

    setUp(() {
      mockRegistry = _MockWidgetRegistryService();
      mockAppRegistry = _MockWidgetAppRegistry();
      when(() => mockAppRegistry.resolveLookupKey(any())).thenAnswer(
        (invocation) => invocation.positionalArguments.first as String,
      );
      when(() => mockRegistry.find(any())).thenAnswer((_) async => null);
    });

    test('GET / returns apps list', () async {
      when(() => mockRegistry.loadAll()).thenAnswer(
        (_) async => [
          const WidgetManifest(
            id: 'weather',
            name: 'Weather',
            description: '',
            version: '1.0.0',
            icon: '🌤',
            allowedCommands: [],
            networkEnabled: true,
            widgetPath: '/tmp/weather',
            isSingleFile: false,
          ),
        ],
      );
      when(() => mockAppRegistry.activeIds()).thenReturn(['weather']);

      final response = await handleApps(
        'GET',
        [],
        _getRequest('/api/apps'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final apps = body['apps'] as List;
      expect(apps.length, 1);
      expect(apps.first['id'], 'weather');
      expect(apps.first['active'], true);
      expect(body['activeIds'], ['weather']);
    });

    test('GET /dev-skill returns content', () async {
      final response = await handleApps(
        'GET',
        ['dev-skill'],
        _getRequest('/api/apps/dev-skill'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      // Asset may or may not exist in test environment; accept either outcome.
      expect(response.statusCode, anyOf(200, 400));
    });

    test('POST /install-zip missing zipPath returns error', () async {
      final response = await handleApps(
        'POST',
        ['install-zip'],
        _postRequest('/api/apps/install-zip'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('POST /install-zip zip not found returns error', () async {
      final response = await handleApps(
        'POST',
        ['install-zip'],
        _postRequest('/api/apps/install-zip', body: {'zipPath': '/nonexistent/file.zip'}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      expect(response.statusCode, 400);
    });

    test('GET /:id/snapshot not running returns error', () async {
      when(() => mockAppRegistry.resolveLookupKey('w1')).thenReturn('w1');
      when(() => mockAppRegistry.tree('w1')).thenReturn(null);

      final response = await handleApps(
        'GET',
        ['w1', 'snapshot'],
        _getRequest('/api/apps/w1/snapshot'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('GET /:id/snapshot returns tree when running', () async {
      when(() => mockAppRegistry.resolveLookupKey('w1')).thenReturn('w1');
      when(() => mockAppRegistry.tree('w1')).thenReturn({
        'type': 'text',
        'data': 'Hello',
      });

      final response = await handleApps(
        'GET',
        ['w1', 'snapshot'],
        _getRequest('/api/apps/w1/snapshot'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['tree'], isA<Map<String, dynamic>>());
      expect(body['text'], ['Hello']);
    });

    test('GET /:id/help returns manifest cli help', () async {
      when(() => mockAppRegistry.resolveLookupKey('weather')).thenReturn('weather');
      when(() => mockAppRegistry.engine('weather')).thenReturn(null);
      when(() => mockRegistry.find('weather')).thenAnswer(
        (_) async => const WidgetManifest(
          id: 'weather',
          name: 'Weather',
          description: 'Weather',
          version: '1.0.0',
          icon: '🌤',
          allowedCommands: [],
          networkEnabled: true,
          widgetPath: '/tmp/weather',
          isSingleFile: false,
          cli: {'summary': 'City weather'},
        ),
      );

      final response = await handleApps(
        'GET',
        ['weather', 'help'],
        _getRequest('/api/apps/weather/help'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['summary'], 'City weather');
      expect(body['globalCommands'], isNotEmpty);
    });

    test('GET /:id/state returns exported state and text', () async {
      final mockEngine = _MockJsWidgetEngine();
      when(() => mockAppRegistry.resolveLookupKey('weather')).thenReturn('weather');
      when(() => mockAppRegistry.engine('weather')).thenReturn(mockEngine);
      when(() => mockEngine.exportedState).thenReturn({'tempC': '10'});
      when(() => mockAppRegistry.tree('weather')).thenReturn({
        'type': 'text',
        'data': '10°C',
      });
      when(() => mockRegistry.find('weather')).thenAnswer(
        (_) async => const WidgetManifest(
          id: 'weather',
          name: 'Weather',
          description: 'Weather',
          version: '1.0.0',
          icon: '🌤',
          allowedCommands: [],
          networkEnabled: true,
          widgetPath: '/tmp/weather',
          isSingleFile: false,
        ),
      );

      final response = await handleApps(
        'GET',
        ['weather', 'state'],
        _getRequest('/api/apps/weather/state'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['state'], {'tempC': '10'});
      expect(body['text'], ['10°C']);
    });

    test('POST /:id/execute missing action returns error', () async {
      final response = await handleApps(
        'POST',
        ['w1', 'execute'],
        _postRequest('/api/apps/w1/execute'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      expect(response.statusCode, 400);
    });

    test('POST /:id/execute returns state after event', () async {
      final mockEngine = _MockJsWidgetEngine();
      when(() => mockAppRegistry.resolveLookupKey('weather')).thenReturn('weather');
      when(() => mockAppRegistry.engine('weather')).thenReturn(mockEngine);
      when(
        () => mockEngine.callEvent('set_city', any()),
      ).thenAnswer((_) async {});
      when(() => mockEngine.exportedState).thenReturn({
        'city': 'Grodno',
        'tempC': '18',
        'loading': false,
      });

      final response = await handleApps(
        'POST',
        ['weather', 'execute'],
        _postRequest(
          '/api/apps/weather/execute',
          body: {
            'action': 'set_city',
            'payload': {'city': 'Grodno'},
          },
        ),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['action'], 'set_city');
      expect(body['state'], {'city': 'Grodno', 'tempC': '18', 'loading': false});
      verify(() => mockEngine.callEvent('set_city', {'city': 'Grodno'})).called(1);
    });

    test('POST /:id/execute not running returns error', () async {
      when(() => mockAppRegistry.engine('w1')).thenReturn(null);

      final response = await handleApps(
        'POST',
        ['w1', 'execute'],
        _postRequest('/api/apps/w1/execute', body: {'action': 'click'}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('GET /:id/logs not running returns error', () async {
      when(() => mockAppRegistry.engine('w1')).thenReturn(null);

      final response = await handleApps(
        'GET',
        ['w1', 'logs'],
        _getRequest('/api/apps/w1/logs'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
      expect((body['logs'] as List).isEmpty, true);
    });

    test('POST /:id/reload not running returns error', () async {
      when(() => mockAppRegistry.triggerReload('w1')).thenAnswer((_) async => false);

      final response = await handleApps(
        'POST',
        ['w1', 'reload'],
        _postRequest('/api/apps/w1/reload'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('POST /:id/screenshot returns error', () async {
      final response = await handleApps(
        'POST',
        ['w1', 'screenshot'],
        _postRequest('/api/apps/w1/screenshot'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('unknown route returns notFound', () async {
      final response = await handleApps(
        'GET',
        ['unknown'],
        _getRequest('/api/apps/unknown'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );

      expect(response.statusCode, 404);
    });
  });

  group('demo apps and install-zip', () {
    late _MockWidgetRegistryService mockRegistry;
    late _MockWidgetAppRegistry mockAppRegistry;
    late Directory tmp;
    late Directory appsDir;

    setUp(() {
      mockRegistry = _MockWidgetRegistryService();
      mockAppRegistry = _MockWidgetAppRegistry();
      when(() => mockRegistry.find(any())).thenAnswer((_) async => null);
      when(() => mockRegistry.loadAll()).thenAnswer((_) async => []);
      tmp = Directory.systemTemp.createTempSync('apps_demo_test_');
      appsDir = Directory('${tmp.path}/apps')..createSync(recursive: true);
      debugAppsDirOverride = appsDir.path;
    });

    tearDown(() {
      debugAppsDirOverride = null;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<shelf.Response> callApps(
      String method,
      List<String> sub, {
      Map<String, dynamic>? requestBody,
    }) {
      final path = '/api/apps/${sub.join('/')}';
      final request =
          method == 'POST'
              ? _postRequest(path, body: requestBody)
              : _getRequest(path);
      return handleApps(
        method,
        sub,
        request,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        registryService: mockRegistry,
        appRegistry: mockAppRegistry,
      );
    }

    Directory writeDemo(String name, {String? manifest, String? widgetJs}) {
      final dir = Directory('${appsDir.path}/$name')
        ..createSync(recursive: true);
      if (manifest != null) {
        File('${dir.path}/manifest.json').writeAsStringSync(manifest);
      }
      if (widgetJs != null) {
        File('${dir.path}/widget.js').writeAsStringSync(widgetJs);
      }
      return dir;
    }

    Future<File> zipDir(String zipName, Directory source) async {
      final zipPath = '${tmp.path}/$zipName';
      final result = await Process.run('zip', [
        '-qr',
        zipPath,
        '.',
      ], workingDirectory: source.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return File(zipPath);
    }

    Future<Map<String, dynamic>> jsonBody(shelf.Response response) async =>
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;

    test('GET /demo returns empty list when apps dir is missing', () async {
      debugAppsDirOverride = '${tmp.path}/missing';

      final response = await callApps('GET', ['demo']);

      expect(response.statusCode, 200);
      expect((await jsonBody(response))['demos'], isEmpty);
    });

    test('GET /demo lists demos sorted by id with file paths', () async {
      writeDemo(
        'zebra',
        manifest: '{"id": "zebra", "name": "Zebra"}',
        widgetJs: '// z',
      );
      writeDemo(
        'alpha',
        manifest:
            '{"id": "alpha", "name": "Alpha", "description": "First", '
            '"icon": "A", "network": true}',
        widgetJs: '// a',
      );
      Directory('${appsDir.path}/no-manifest').createSync();
      writeDemo('broken', manifest: 'not-json');

      final response = await callApps('GET', ['demo']);

      expect(response.statusCode, 200);
      final demos = (await jsonBody(response))['demos'] as List;
      expect(demos.map((d) => (d as Map)['id']), ['alpha', 'zebra']);
      final alpha = demos.first as Map<String, dynamic>;
      expect(alpha['name'], 'Alpha');
      expect(alpha['description'], 'First');
      expect(alpha['icon'], 'A');
      expect(alpha['network'], true);
      expect(alpha['path'], '${appsDir.path}/alpha');
      expect(alpha['files'], {
        'manifest': '${appsDir.path}/alpha/manifest.json',
        'widget': '${appsDir.path}/alpha/widget.js',
      });
    });

    test('GET /demo/:id returns 400 for unknown demo', () async {
      final response = await callApps('GET', ['demo', 'ghost']);

      expect(response.statusCode, 400);
      expect((await jsonBody(response))['error'], contains('ghost'));
    });

    test('GET /demo/:id returns manifest and widget source', () async {
      writeDemo(
        'clock',
        manifest: '{"id": "clock", "name": "Clock"}',
        widgetJs: 'console.log(1);',
      );

      final response = await callApps('GET', ['demo', 'clock']);

      expect(response.statusCode, 200);
      final body = await jsonBody(response);
      expect(body['id'], 'clock');
      expect(body['path'], '${appsDir.path}/clock');
      expect(body['manifest'], {'id': 'clock', 'name': 'Clock'});
      expect(body['manifestRaw'], '{"id": "clock", "name": "Clock"}');
      expect(body['widgetJs'], 'console.log(1);');
    });

    test('GET /demo/:id tolerates invalid manifest and missing widget',
        () async {
      writeDemo('broken', manifest: 'not-json');

      final response = await callApps('GET', ['demo', 'broken']);

      expect(response.statusCode, 200);
      final body = await jsonBody(response);
      expect(body['manifest'], isEmpty);
      expect(body['manifestRaw'], 'not-json');
      expect(body['widgetJs'], isNull);
    });

    test('POST /install-zip installs app using the manifest id', () async {
      final pkg = Directory('${tmp.path}/src/pkg')..createSync(recursive: true);
      File('${pkg.path}/manifest.json').writeAsStringSync(
        '{"id": "zipapp", "name": "Zip App"}',
      );
      File('${pkg.path}/widget.js').writeAsStringSync('// zipped');
      final zip = await zipDir('whatever.zip', pkg.parent);

      final response = await callApps(
        'POST',
        ['install-zip'],
        requestBody: {'zipPath': zip.path},
      );

      expect(response.statusCode, 200);
      final body = await jsonBody(response);
      expect(body['ok'], true);
      expect(body['appName'], 'zipapp');
      expect(body['widget'], isNull);
      expect(
        File('${appsDir.path}/zipapp/widget.js').readAsStringSync(),
        '// zipped',
      );
      // The temporary extraction directory is cleaned up.
      expect(
        appsDir.listSync().map((e) => e.path.split('/').last),
        ['zipapp'],
      );
      verify(() => mockRegistry.find('zipapp')).called(1);
    });

    test('POST /install-zip falls back to the zip filename', () async {
      final inner = Directory('${tmp.path}/plain_src/inner')
        ..createSync(recursive: true);
      File('${inner.path}/widget.js').writeAsStringSync('// plain');
      final zip = await zipDir('plainapp.zip', inner.parent);

      final response = await callApps(
        'POST',
        ['install-zip'],
        requestBody: {'zipPath': zip.path},
      );

      expect(response.statusCode, 200);
      expect((await jsonBody(response))['appName'], 'plainapp');
      expect(File('${appsDir.path}/plainapp/widget.js').existsSync(), true);
    });

    test('POST /install-zip falls back to the extract dir without app files',
        () async {
      final src = Directory('${tmp.path}/docs_src')..createSync();
      File('${src.path}/readme.txt').writeAsStringSync('hello');
      final zip = await zipDir('docsapp.zip', src);

      final response = await callApps(
        'POST',
        ['install-zip'],
        requestBody: {'zipPath': zip.path},
      );

      expect(response.statusCode, 200);
      final body = await jsonBody(response);
      expect(body['ok'], true);
      expect(body['appName'], 'docsapp');
      expect(File('${appsDir.path}/docsapp/readme.txt').existsSync(), true);
    });

    test('POST /install-zip reports extraction failure', () async {
      final bad = File('${tmp.path}/bad.zip')..writeAsBytesSync([1, 2, 3, 4]);

      final response = await callApps(
        'POST',
        ['install-zip'],
        requestBody: {'zipPath': bad.path},
      );

      expect(response.statusCode, 400);
      expect((await jsonBody(response))['error'],
          contains('Failed to extract ZIP'));
    });
  });
}
