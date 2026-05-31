import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class YoloitRemoteClient {
  YoloitRemoteClient({
    required String baseUrl,
    this.token,
    HttpClient? httpClient,
  }) : baseUri = _normalizeBaseUri(baseUrl),
       _http = httpClient ?? HttpClient();

  final Uri baseUri;
  final String? token;
  final HttpClient _http;

  Future<Map<String, dynamic>> health() => _json('GET', '/api/health');

  Future<List<Map<String, dynamic>>> listBoards() async {
    final response = await _json('GET', '/api/boards');
    return (response['boards'] as List? ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<BoardDocument> fetchBoard(String remoteBoardId) async {
    final response = await _json(
      'GET',
      '/api/boards/${Uri.encodeComponent(remoteBoardId)}',
    );
    return remoteBoardFromJson(
      response,
      baseUrl: baseUri.toString(),
      token: token,
    );
  }

  Future<BoardDocument> putBoard(BoardDocument board) async {
    final remote = remoteInfoForBoard(board);
    if (remote == null) return board;
    final response = await _json(
      'PUT',
      '/api/boards/${Uri.encodeComponent(remote.boardId)}',
      body: boardToRemoteJson(board),
    );
    final updated = response['board'];
    if (updated is! Map) return board;
    return remoteBoardFromJson(
      Map<String, dynamic>.from(updated),
      baseUrl: remote.url,
      token: remote.token,
    );
  }

  Future<BoardDocument> createBoard(String name) async {
    final response = await _json('POST', '/api/boards', body: {'name': name});
    final summary = Map<String, dynamic>.from(response['board'] as Map);
    return fetchBoard(summary['id'] as String);
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final request = await _http
        .openUrl(method, baseUri.resolve(path))
        .timeout(const Duration(seconds: 10));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (token != null && token!.trim().isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      final encoded = utf8.encode(jsonEncode(body));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.contentLength = encoded.length;
      request.add(encoded);
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw YoloitRemoteException(
        'Remote YoLoIT returned HTTP ${response.statusCode}: $text',
        statusCode: response.statusCode,
        body: text,
      );
    }
    if (text.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const YoloitRemoteException(
        'Remote YoLoIT returned non-object JSON',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Uri _normalizeBaseUri(String raw) {
    final trimmed = raw.trim();
    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.parse(withScheme);
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw YoloitRemoteException('Invalid remote YoLoIT URL: $raw');
    }
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }
}

class YoloitRemoteException implements Exception {
  const YoloitRemoteException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => message;
}

({String url, String? token, String boardId, int? revision})?
remoteInfoForBoard(BoardDocument board) {
  final raw = board.metadata['remote'];
  if (raw is! Map) return null;
  final remote = Map<String, dynamic>.from(raw);
  final url = (remote['url'] as String? ?? '').trim();
  final boardId = (remote['boardId'] as String? ?? '').trim();
  if (url.isEmpty || boardId.isEmpty) return null;
  final token = (remote['token'] as String?)?.trim();
  final revision = remote['revision'];
  return (
    url: url,
    token: token == null || token.isEmpty ? null : token,
    boardId: boardId,
    revision: revision is num ? revision.toInt() : null,
  );
}

bool isRemoteBoard(BoardDocument board) => remoteInfoForBoard(board) != null;

BoardDocument remoteBoardFromJson(
  Map<String, dynamic> json, {
  required String baseUrl,
  String? token,
}) {
  final remoteId = json['id'] as String;
  final metadata = Map<String, dynamic>.from(json['metadata'] as Map? ?? {});
  final historyRevision = (metadata['historyRevision'] as num?)?.toInt();
  metadata['remote'] = <String, dynamic>{
    'url': baseUrl,
    if (token != null && token.trim().isNotEmpty) 'token': token.trim(),
    'boardId': remoteId,
    if (historyRevision != null) 'revision': historyRevision,
  };
  metadata['remoteSource'] = 'yoloitd';
  return BoardDocument(
    id: remoteLocalBoardId(baseUrl, remoteId),
    name: json['name'] as String? ?? 'Remote board',
    viewport: _remoteViewport(json['viewport']),
    panels: _remotePanels(json['panels']),
    links: _remoteLinks(json['links']),
    drawings: _remoteDrawings(json['drawings']),
    metadata: metadata,
  );
}

Map<String, dynamic> boardToRemoteJson(BoardDocument board) {
  final remote = remoteInfoForBoard(board);
  final metadata =
      Map<String, dynamic>.from(board.metadata)
        ..remove('remote')
        ..remove('remoteSource')
        ..remove('historyRevision');
  return <String, dynamic>{
    if (remote != null) 'id': remote.boardId,
    if (remote?.revision != null) 'expectedRevision': remote!.revision,
    'name': board.name,
    'viewport': board.viewport.toJson(),
    'panels': board.panels.map((panel) => panel.toJson()).toList(),
    'links': board.links.map((link) => link.toJson()).toList(),
    'drawings': board.drawings.map((drawing) => drawing.toJson()).toList(),
    'metadata': metadata,
  };
}

String remoteLocalBoardId(String baseUrl, String remoteBoardId) {
  final normalized = Uri.parse(
    baseUrl.contains('://') ? baseUrl : 'http://$baseUrl',
  );
  final key = '${normalized.scheme}://${normalized.host}:${normalized.port}';
  final hash = _stableHash(key).toRadixString(36);
  final safeRemote = remoteBoardId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  return 'remote_${hash}_$safeRemote';
}

int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

BoardViewport _remoteViewport(Object? raw) {
  if (raw is! Map) return const BoardViewport();
  final map = Map<String, dynamic>.from(raw);
  final translation = map['translation'];
  if (translation is Map) {
    return BoardViewport(
      scale: (map['scale'] as num?)?.toDouble() ?? 1.0,
      translation: Offset(
        (translation['dx'] as num?)?.toDouble() ?? 0.0,
        (translation['dy'] as num?)?.toDouble() ?? 0.0,
      ),
      focusedPanelId: map['focusedPanelId'] as String?,
    );
  }
  return BoardViewport.fromJson(map);
}

List<BoardPanelInstance> _remotePanels(Object? raw) {
  return (raw as List? ?? const <Object?>[])
      .whereType<Map<Object?, Object?>>()
      .map(
        (entry) =>
            BoardPanelInstance.fromJson(Map<String, dynamic>.from(entry)),
      )
      .toList();
}

List<BoardPanelLink> _remoteLinks(Object? raw) {
  return (raw as List? ?? const <Object?>[])
      .whereType<Map<Object?, Object?>>()
      .map((entry) => _remoteLink(Map<String, dynamic>.from(entry)))
      .whereType<BoardPanelLink>()
      .toList();
}

BoardPanelLink? _remoteLink(Map<String, dynamic> json) {
  try {
    return BoardPanelLink.fromJson(json);
  } catch (_) {
    final from = json['fromPanelId'] as String? ?? json['from'] as String?;
    final to = json['toPanelId'] as String? ?? json['to'] as String?;
    if (from == null || to == null) return null;
    return BoardPanelLink(
      id: json['id'] as String? ?? 'link_${_stableHash('$from:$to')}',
      fromPanelId: from,
      toPanelId: to,
      style:
          json['style'] == 'line' ? BoardLinkStyle.line : BoardLinkStyle.arrow,
      color: Color((json['color'] as num?)?.toInt() ?? 0xFF60A5FA),
      geometry: _linkGeometry(json['geometry'] as String?),
    );
  }
}

BoardLinkGeometry _linkGeometry(String? value) {
  return BoardLinkGeometry.values.firstWhere(
    (entry) => entry.name == value,
    orElse: () => BoardLinkGeometry.bezier,
  );
}

List<BoardDrawingElement> _remoteDrawings(Object? raw) {
  return (raw as List? ?? const <Object?>[])
      .whereType<Map<Object?, Object?>>()
      .map(
        (entry) =>
            BoardDrawingElement.fromJson(Map<String, dynamic>.from(entry)),
      )
      .toList();
}
