import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/widgets_handler.dart';
import 'package:yoloit/features/board/widgets/widget_registry_service.dart';

shelf.Request _request(String method, String path, {Map<String, dynamic>? body}) {
  return shelf.Request(
    method,
    Uri.parse('http://localhost:8080$path'),
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

  late Directory home;
  late Directory appsDir;
  final registry = WidgetRegistryService.instance;

  setUp(() {
    home = Directory.systemTemp.createTempSync('widgets_handler_test_');
    appsDir = Directory('${home.path}/.config/yoloit/apps')
      ..createSync(recursive: true);
    WidgetRegistryService.debugHomeDir = home.path;
    registry.invalidate();
  });

  tearDown(() {
    WidgetRegistryService.debugHomeDir = null;
    registry.invalidate();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  Future<shelf.Response> callWidgets(
    String method,
    List<String> sub, {
    Map<String, dynamic>? requestBody,
  }) {
    return handleWidgets(
      method,
      sub,
      _request(method, '/api/widgets/${sub.join('/')}', body: requestBody),
      body: _body,
      json: _json,
      error: _error,
      notFound: _notFound,
    );
  }

  Future<Map<String, dynamic>> jsonBody(shelf.Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, dynamic>;

  void writeWidgetSource(
    Directory dir, {
    String? manifest,
    String widgetJs = '// w',
  }) {
    dir.createSync(recursive: true);
    if (manifest != null) {
      File('${dir.path}/manifest.json').writeAsStringSync(manifest);
    }
    File('${dir.path}/widget.js').writeAsStringSync(widgetJs);
  }

  void seedInstalledWidget(String id) {
    writeWidgetSource(
      Directory('${appsDir.path}/$id'),
      manifest: '{"id": "$id", "name": "${id}Name"}',
    );
    registry.invalidate();
  }

  test('GET / returns installed widgets', () async {
    seedInstalledWidget('meter');

    final response = await callWidgets('GET', []);

    expect(response.statusCode, 200);
    final widgets = (await jsonBody(response))['widgets'] as List;
    final meter =
        widgets.cast<Map<String, dynamic>>().where((w) => w['id'] == 'meter');
    expect(meter.length, 1);
    expect(meter.first['name'], 'meterName');
  });

  test('returns notFound for sub paths deeper than one segment', () async {
    final response = await callWidgets('GET', ['a', 'b']);

    expect(response.statusCode, 404);
    expect((await jsonBody(response))['error'], 'Unknown widget route');
  });

  test('returns notFound for unsupported method on collection', () async {
    final response = await callWidgets('POST', []);

    expect(response.statusCode, 404);
  });

  test('GET /:id returns a single widget', () async {
    seedInstalledWidget('meter');

    final response = await callWidgets('GET', ['meter']);

    expect(response.statusCode, 200);
    final widget = (await jsonBody(response))['widget'] as Map<String, dynamic>;
    expect(widget['id'], 'meter');
  });

  test('GET /:id returns notFound for unknown widget', () async {
    final response = await callWidgets('GET', ['ghost']);

    expect(response.statusCode, 404);
    expect((await jsonBody(response))['error'], contains('ghost'));
  });

  test('DELETE /:id removes an installed widget', () async {
    seedInstalledWidget('meter');

    final response = await callWidgets('DELETE', ['meter']);

    expect(response.statusCode, 200);
    final body = await jsonBody(response);
    expect(body['ok'], true);
    expect(body['id'], 'meter');
    expect(await registry.find('meter'), isNull);
  });

  test('DELETE /:id returns ok false for unknown widget', () async {
    final response = await callWidgets('DELETE', ['ghost']);

    expect(response.statusCode, 200);
    expect((await jsonBody(response))['ok'], false);
  });

  test('POST /install requires the path field', () async {
    final response = await callWidgets('POST', ['install']);

    expect(response.statusCode, 400);
    expect((await jsonBody(response))['error'], 'Missing "path" field');
  });

  test('POST /install copies a widget directory into the apps dir', () async {
    final src = Directory('${home.path}/src/coolapp');
    writeWidgetSource(
      src,
      manifest: '{"id": "coolapp", "name": "Cool App", "network": false}',
      widgetJs: '// cool',
    );

    final response = await callWidgets(
      'POST',
      ['install'],
      requestBody: {'path': src.path},
    );

    expect(response.statusCode, 200);
    final body = await jsonBody(response);
    expect(body['ok'], true);
    final widget = body['widget'] as Map<String, dynamic>;
    expect(widget['id'], 'coolapp');
    expect(widget['name'], 'Cool App');
    expect(widget['network'], false);
    expect(
      File('${appsDir.path}/coolapp/widget.js').readAsStringSync(),
      '// cool',
    );
  });

  test('POST /install reports failure for a missing path', () async {
    final response = await callWidgets(
      'POST',
      ['install'],
      requestBody: {'path': '${home.path}/does-not-exist'},
    );

    expect(response.statusCode, 400);
    expect(
      (await jsonBody(response))['error'],
      contains('Failed to install widget'),
    );
  });
}
