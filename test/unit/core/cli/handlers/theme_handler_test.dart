import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/theme_handler.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';

class _MockThemeManager extends Mock implements ThemeManager {}

shelf.Request _getRequest(String path, {Map<String, String>? query}) {
  final uri = Uri.parse('http://localhost:8080$path').replace(queryParameters: query);
  return shelf.Request('GET', uri);
}

shelf.Request _postRequest(String path, {Map<String, dynamic>? body}) {
  final uri = Uri.parse('http://localhost:8080$path');
  return shelf.Request(
    'POST',
    uri,
    body: body != null ? jsonEncode(body) : null,
  );
}

shelf.Request _deleteRequest(String path, {Map<String, String>? query}) {
  final uri = Uri.parse('http://localhost:8080$path').replace(queryParameters: query);
  return shelf.Request('DELETE', uri);
}

shelf.Response _json(Object data) => shelf.Response.ok(
  jsonEncode(data),
  headers: {'content-type': 'application/json'},
);

shelf.Response _notFound(String msg) => shelf.Response.notFound(
  jsonEncode({'ok': false, 'error': msg}),
  headers: {'content-type': 'application/json'},
);

void main() {
  setUpAll(() {
    registerFallbackValue(const Color(0xFFFFFFFF));
  });
  group('handleTheme', () {
    late _MockThemeManager mockThemeManager;

    setUp(() {
      mockThemeManager = _MockThemeManager();
      when(() => mockThemeManager.current).thenReturn(AppThemePreset.neonPurple);
      when(() => mockThemeManager.isDark).thenReturn(true);
      when(() => mockThemeManager.hasOverrides).thenReturn(false);
      when(() => mockThemeManager.colorOverrides).thenReturn({});
      when(() => mockThemeManager.customThemes).thenReturn([]);
      when(() => mockThemeManager.activeCustomThemeId).thenReturn(null);
      when(() => mockThemeManager.effectiveScheme).thenReturn(
        AppColorScheme.fromAccent(Colors.blue, brightness: Brightness.dark),
      );
    });

    test('GET / returns current theme info', () async {
      final response = await handleTheme(
        'GET',
        [],
        _getRequest('/api/theme'),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['preset'], AppThemePreset.neonPurple.name);
      expect(body['brightness'], 'dark');
    });

    test('GET /presets returns built-in and custom presets', () async {
      final response = await handleTheme(
        'GET',
        ['presets'],
        _getRequest('/api/theme/presets'),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final presets = body['presets'] as List;
      expect(presets.isNotEmpty, true);
      expect(presets.any((p) => p['type'] == 'builtin'), true);
    });

    test('POST /set with valid preset', () async {
      when(() => mockThemeManager.setTheme(AppThemePreset.neonPurple)).thenAnswer((_) async {});
      when(() => mockThemeManager.clearColorOverrides()).thenAnswer((_) async {});

      final response = await handleTheme(
        'POST',
        ['set'],
        _postRequest('/api/theme/set', body: {'preset': AppThemePreset.neonPurple.name}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
    });

    test('POST /set with invalid preset returns error', () async {
      final response = await handleTheme(
        'POST',
        ['set'],
        _postRequest('/api/theme/set', body: {'preset': 'unknown'}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('POST /set with customId', () async {
      when(() => mockThemeManager.setCustomTheme('custom_1')).thenAnswer((_) async {});
      when(() => mockThemeManager.clearColorOverrides()).thenAnswer((_) async {});

      final response = await handleTheme(
        'POST',
        ['set'],
        _postRequest('/api/theme/set', body: {'customId': 'custom_1'}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
    });

    test('POST /set without preset or customId returns error', () async {
      final response = await handleTheme(
        'POST',
        ['set'],
        _postRequest('/api/theme/set', body: {}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('POST /brightness dark', () async {
      when(() => mockThemeManager.setBrightness(Brightness.dark)).thenAnswer((_) async {});

      final response = await handleTheme(
        'POST',
        ['brightness'],
        _postRequest('/api/theme/brightness', body: {'brightness': 'dark'}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['brightness'], 'dark');
    });

    test('POST /brightness light', () async {
      when(() => mockThemeManager.setBrightness(Brightness.light)).thenAnswer((_) async {});

      final response = await handleTheme(
        'POST',
        ['brightness'],
        _postRequest('/api/theme/brightness', body: {'brightness': 'light'}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
    });

    test('POST /brightness invalid returns error', () async {
      final response = await handleTheme(
        'POST',
        ['brightness'],
        _postRequest('/api/theme/brightness', body: {'brightness': 'red'}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('POST /color with 6-digit hex', () async {
      when(() => mockThemeManager.setColorOverride('primary', any())).thenAnswer((_) async {});

      final response = await handleTheme(
        'POST',
        ['color'],
        _postRequest('/api/theme/color', body: {'slot': 'primary', 'color': '#548AF7'}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
    });

    test('POST /color with 8-digit hex', () async {
      when(() => mockThemeManager.setColorOverride('primary', any())).thenAnswer((_) async {});

      final response = await handleTheme(
        'POST',
        ['color'],
        _postRequest('/api/theme/color', body: {'slot': 'primary', 'color': '#FF548AF7'}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
    });

    test('POST /color invalid hex returns error', () async {
      final response = await handleTheme(
        'POST',
        ['color'],
        _postRequest('/api/theme/color', body: {'slot': 'primary', 'color': '#ZZZ'}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('POST /color missing params returns error', () async {
      final response = await handleTheme(
        'POST',
        ['color'],
        _postRequest('/api/theme/color', body: {}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('DELETE /color removes override', () async {
      when(() => mockThemeManager.removeColorOverride('primary')).thenAnswer((_) async {});

      final response = await handleTheme(
        'DELETE',
        ['color'],
        _deleteRequest('/api/theme/color', query: {'slot': 'primary'}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
    });

    test('DELETE /color missing slot returns error', () async {
      final response = await handleTheme(
        'DELETE',
        ['color'],
        _deleteRequest('/api/theme/color'),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('POST /reset-colors clears overrides', () async {
      when(() => mockThemeManager.clearColorOverrides()).thenAnswer((_) async {});

      final response = await handleTheme(
        'POST',
        ['reset-colors'],
        _postRequest('/api/theme/reset-colors', body: {}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
    });

    test('POST /save with name', () async {
      when(() => mockThemeManager.saveCurrentAsPreset('My Theme')).thenAnswer((_) async => 'custom_1');

      final response = await handleTheme(
        'POST',
        ['save'],
        _postRequest('/api/theme/save', body: {'name': 'My Theme'}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['id'], 'custom_1');
    });

    test('POST /save without name returns error', () async {
      final response = await handleTheme(
        'POST',
        ['save'],
        _postRequest('/api/theme/save', body: {}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('GET /export returns JSON', () async {
      when(() => mockThemeManager.exportCurrentAsJson()).thenReturn('{"name":"test"}');

      final response = await handleTheme(
        'GET',
        ['export'],
        _getRequest('/api/theme/export'),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, '{"name":"test"}');
    });

    test('POST /import with path succeeds', () async {
      when(() => mockThemeManager.importThemeFile('/path/to/theme.json')).thenAnswer((_) async => 'custom_2');
      when(() => mockThemeManager.setCustomTheme('custom_2')).thenAnswer((_) async {});

      final response = await handleTheme(
        'POST',
        ['import'],
        _postRequest('/api/theme/import', body: {'path': '/path/to/theme.json'}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['id'], 'custom_2');
    });

    test('POST /import without path returns error', () async {
      final response = await handleTheme(
        'POST',
        ['import'],
        _postRequest('/api/theme/import', body: {}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('POST /import failure returns error', () async {
      when(() => mockThemeManager.importThemeFile('/bad/path')).thenThrow(Exception('fail'));

      final response = await handleTheme(
        'POST',
        ['import'],
        _postRequest('/api/theme/import', body: {'path': '/bad/path'}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('DELETE /custom removes theme', () async {
      when(() => mockThemeManager.deleteCustomTheme('custom_1')).thenAnswer((_) async {});

      final response = await handleTheme(
        'DELETE',
        ['custom'],
        _deleteRequest('/api/theme/custom', query: {'id': 'custom_1'}),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
    });

    test('DELETE /custom missing id returns error', () async {
      final response = await handleTheme(
        'DELETE',
        ['custom'],
        _deleteRequest('/api/theme/custom'),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('GET /colors returns colors', () async {
      final response = await handleTheme(
        'GET',
        ['colors'],
        _getRequest('/api/theme/colors'),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['colors'], isA<Map<String, dynamic>>());
    });

    test('GET /slots returns slots', () async {
      final response = await handleTheme(
        'GET',
        ['slots'],
        _getRequest('/api/theme/slots'),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['categories'], isA<Map<String, dynamic>>());
    });

    test('unknown route returns notFound', () async {
      final response = await handleTheme(
        'GET',
        ['unknown'],
        _getRequest('/api/theme/unknown'),
        json: _json,
        notFound: _notFound,
        themeManager: mockThemeManager,
      );

      expect(response.statusCode, 404);
    });
  });
}
