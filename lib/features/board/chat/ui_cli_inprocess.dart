import 'dart:convert';
import 'dart:io';

import 'package:yoloit/core/cli/handlers/ui_handler.dart';

/// Executes `ui:*` chat tools in-process via the local CliServer HTTP API.
///
/// Avoids relying on a potentially stale bundled `tools/yoloit` bash script
/// inside the running Flutter app.
class UiCliInProcessClient {
  UiCliInProcessClient._();

  static Future<String?> tryExecute({
    required String command,
    required Map<String, Object?> arguments,
    required int port,
  }) async {
    switch (command) {
      case 'ui:create':
        return _create(arguments, port);
      case 'ui:render':
        return _render(arguments, port);
      case 'ui:get':
        return _get(arguments, port);
      case 'ui:edit':
        return _edit(arguments, port);
      default:
        return null;
    }
  }

  static Future<String?> _create(
    Map<String, Object?> arguments,
    int port,
  ) async {
    final board = _string(arguments['board'] ?? arguments['b']);
    final title = _string(arguments['title'] ?? arguments['t']);
    if (board == null || title == null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'executed': true,
        'error': 'Missing board or title for ui:create',
      });
    }
    final response = await _post(
      port,
      '/boards/${Uri.encodeComponent(board)}/panels',
      <String, Object?>{
        'type': 'board.ui',
        'title': title,
      },
    );
    if (response == null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'executed': true,
        'error': 'ui:create HTTP request failed',
      });
    }
    final panel = response['panel'];
    if (response['ok'] != true && panel == null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'executed': true,
        'error': response['error'] ?? response,
      });
    }
    final panelMap =
        panel is Map
            ? Map<String, Object?>.from(panel.cast<String, Object?>())
            : <String, Object?>{'id': response['id'], 'type': 'board.ui', 'title': title};
    return jsonEncode(<String, Object?>{
      'ok': true,
      'executed': true,
      'command': 'ui:create $board $title',
      'panel': panelMap,
    });
  }

  static Future<String?> _render(
    Map<String, Object?> arguments,
    int port,
  ) async {
    final board = _string(arguments['board'] ?? arguments['b']);
    if (board == null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'executed': true,
        'error': 'Missing board for ui:render',
      });
    }
    final tree = _parseTree(arguments['tree'] ?? arguments['j'] ?? arguments['json']);
    if (tree == null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'executed': true,
        'error': 'Missing or invalid tree for ui:render',
      });
    }
    final panelId = await _resolveUiPanelId(
      port: port,
      boardRef: board,
      panelHint: _string(arguments['panel'] ?? arguments['p']),
    );
    if (panelId == null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'executed': true,
        'error': 'No board.ui panel found on board "$board"',
      });
    }
    final response = await _post(
      port,
      '/boards/${Uri.encodeComponent(board)}/panels/${Uri.encodeComponent(panelId)}/action',
      <String, Object?>{'action': 'render', 'tree': tree},
    );
    return _wrapActionResponse(
      command: 'ui:render $board $panelId',
      response: response,
    );
  }

  static Future<String?> _get(
    Map<String, Object?> arguments,
    int port,
  ) async {
    final board = _string(arguments['board'] ?? arguments['b']);
    if (board == null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'executed': true,
        'error': 'Missing board for ui:get',
      });
    }
    final panelId = await _resolveUiPanelId(
      port: port,
      boardRef: board,
      panelHint: _string(arguments['panel'] ?? arguments['p']),
    );
    if (panelId == null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'executed': true,
        'error': 'No board.ui panel found on board "$board"',
      });
    }
    final response = await _post(
      port,
      '/boards/${Uri.encodeComponent(board)}/panels/${Uri.encodeComponent(panelId)}/action',
      <String, Object?>{'action': 'get'},
    );
    return _wrapActionResponse(
      command: 'ui:get $board $panelId',
      response: response,
    );
  }

  static Future<String?> _edit(
    Map<String, Object?> arguments,
    int port,
  ) async {
    final board = _string(arguments['board'] ?? arguments['b']);
    if (board == null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'executed': true,
        'error': 'Missing board for ui:edit',
      });
    }
    final panelId = await _resolveUiPanelId(
      port: port,
      boardRef: board,
      panelHint: _string(arguments['panel'] ?? arguments['p']),
    );
    if (panelId == null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'executed': true,
        'error': 'No board.ui panel found on board "$board"',
      });
    }
    await _put(
      port,
      '/boards/${Uri.encodeComponent(board)}/panels/${Uri.encodeComponent(panelId)}',
      <String, Object?>{'focus': true},
    );
    return jsonEncode(<String, Object?>{
      'ok': true,
      'executed': true,
      'command': 'ui:edit $board $panelId',
      'message':
          'Panel focused — open JSON editor from the panel header (edit icon).',
    });
  }

  static Future<String?> _resolveUiPanelId({
    required int port,
    required String boardRef,
    String? panelHint,
  }) async {
    final panels = await _getJson(
      port,
      '/boards/${Uri.encodeComponent(boardRef)}/panels',
    );
    final list = panels?['panels'];
    if (list is! List) return null;
    final typed =
        list
            .whereType<Map<String, dynamic>>()
            .map((p) => Map<String, dynamic>.from(p))
            .where((p) => p['hidden'] != true)
            .toList();
    if (panelHint != null && panelHint.trim().isNotEmpty) {
      final hint = panelHint.trim().toLowerCase();
      for (final panel in typed) {
        final title = '${panel['title'] ?? ''}'.toLowerCase();
        final id = '${panel['id'] ?? ''}'.toLowerCase();
        if (title == hint || id == hint || id.startsWith(hint)) {
          return panel['id'] as String?;
        }
      }
    }
    for (final panel in typed) {
      if (panel['type'] == 'board.ui') {
        return panel['id'] as String?;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _parseTree(Object? raw) {
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw.cast<String, dynamic>());
      if (map.containsKey('tree') && !map.containsKey('type')) {
        final nested = map['tree'];
        if (nested is Map) {
          return Map<String, dynamic>.from(nested.cast<String, dynamic>());
        }
      }
      return parseUiTree(map);
    }
    if (raw is String) {
      return parseUiTree(_stripMarkdownFence(raw));
    }
    return null;
  }

  static String stripMarkdownFence(String value) => _stripMarkdownFence(value);

  static String _stripMarkdownFence(String value) {
    var text = value.trim();
    if (!text.startsWith('```')) return text;
    text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
    return text.trim();
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  static Future<Map<String, dynamic>?> _getJson(int port, String path) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/api$path'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>?> _put(
    int port,
    String path,
    Map<String, Object?> body,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.putUrl(Uri.parse('http://127.0.0.1:$port/api$path'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return <String, dynamic>{'ok': false, 'error': text};
      }
      return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
    } catch (error) {
      return <String, dynamic>{'ok': false, 'error': '$error'};
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>?> _post(
    int port,
    String path,
    Map<String, Object?> body,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('http://127.0.0.1:$port/api$path'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return <String, dynamic>{'ok': false, 'error': text};
      }
      return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
    } catch (error) {
      return <String, dynamic>{'ok': false, 'error': '$error'};
    } finally {
      client.close(force: true);
    }
  }

  static String _wrapActionResponse({
    required String command,
    required Map<String, dynamic>? response,
  }) {
    if (response == null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'executed': true,
        'command': command,
        'error': 'HTTP request failed',
      });
    }
    final ok = response['ok'] == true;
    return jsonEncode(<String, Object?>{
      'ok': ok,
      'executed': true,
      'command': command,
      if (response['message'] != null) 'message': response['message'],
      if (response['data'] != null) 'data': response['data'],
      if (!ok) 'error': response['error'] ?? response['message'] ?? response,
    });
  }
}
