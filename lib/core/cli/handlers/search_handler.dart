import 'dart:async';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';

Future<shelf.Response> handleSearch(
  String method,
  List<String> sub,
  shelf.Request request,
  BoardCubit cubit, {
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
  ChatSessionManager? chatSessionManager,
  ChatSessionHistory? chatSessionHistory,
}) async {
  if (method != 'GET' || (sub.isNotEmpty && sub[0] != 'all')) {
    return notFound('Unknown search route');
  }
  final query =
      request.url.queryParameters['q']?.trim() ??
      request.url.queryParameters['query']?.trim() ??
      '';
  if (query.isEmpty) return error('Missing "q" query parameter');
  final scope =
      request.url.queryParameters['scope']?.trim().toLowerCase() ?? 'all';

  final items = <Map<String, Object?>>[];
  if (scope == 'all' || scope == 'boards' || scope == 'panels') {
    items.addAll(searchBoards(cubit, query));
  }
  if (scope == 'all' || scope == 'active-chats' || scope == 'chats') {
    items.addAll(searchActiveChats(query, chatSessionManager: chatSessionManager));
  }
  if (scope == 'all' || scope == 'sessions' || scope == 'history') {
    items.addAll(await searchSavedChatSessions(query, chatSessionHistory: chatSessionHistory));
  }

  return json({'ok': true, 'query': query, 'scope': scope, 'items': items});
}

List<Map<String, Object?>> searchBoards(BoardCubit cubit, String query) {
  final items = <Map<String, Object?>>[];
  for (final board in cubit.state.boards) {
    // Also search board name itself.
    final boardSnippet = matchSnippet(board.name, query);
    if (boardSnippet != null) {
      items.add({
        'scope': 'board',
        'boardId': board.id,
        'boardName': board.name,
        'panelId': null,
        'panelTitle': null,
        'panelType': null,
        'snippet': boardSnippet,
      });
    }
    for (final panel in board.panels) {
      // Include panel ID as a searchable field so queries like
      // "demo_copilot" or "demo copilot" match a panel named demo_copilot.
      final texts = <String>[
        if ((panel.title ?? '').trim().isNotEmpty) panel.title.trim(),
        panel.id,
        ...collectSearchStrings(panel.state),
      ];
      for (final text in texts) {
        final snippet = matchSnippet(text, query);
        if (snippet == null) continue;
        items.add({
          'scope': 'board',
          'boardId': board.id,
          'boardName': board.name,
          'panelId': panel.id,
          'panelTitle': panel.title ?? panel.id,
          'panelType': panel.type,
          'snippet': snippet,
        });
        break;
      }
    }
  }
  return items;
}

List<Map<String, Object?>> searchActiveChats(
  String query, {
  ChatSessionManager? chatSessionManager,
}) {
  final manager = chatSessionManager ?? ChatSessionManager.instance;
  final items = <Map<String, Object?>>[];
  for (final panelId in manager.activeSessionIds) {
    final session = manager.get(panelId);
    if (session == null) continue;
    for (final message in session.messages) {
      final snippet = matchSnippet(message.content, query);
      if (snippet == null) continue;
      items.add({
        'scope': 'active-chat',
        'panelId': panelId,
        'provider': session.config.provider,
        'model': session.config.model,
        'role': message.role.name,
        'snippet': snippet,
      });
    }
  }
  return items;
}

Future<List<Map<String, Object?>>> searchSavedChatSessions(
  String query, {
  ChatSessionHistory? chatSessionHistory,
}) async {
  final history = chatSessionHistory ?? ChatSessionHistory.instance;
  final entries = await history.loadAll();
  final items = <Map<String, Object?>>[];
  for (final entry in entries) {
    final messages = await history.loadMessages(entry.id);
    for (final message in messages) {
      final content = message['content'] as String? ?? '';
      final snippet = matchSnippet(content, query);
      if (snippet == null) continue;
      items.add({
        'scope': 'saved-session',
        'sessionId': entry.id,
        'sessionName': entry.sessionName,
        'provider': entry.provider,
        'model': entry.model,
        'workingDir': entry.workingDir,
        'role': message['role'] ?? 'unknown',
        'snippet': snippet,
      });
    }
  }
  return items;
}

List<String> collectSearchStrings(dynamic value, {int depth = 0}) {
  final out = <String>[];
  _collectSearchStrings(value, depth, out);
  return out;
}

void _collectSearchStrings(dynamic value, int depth, List<String> out) {
  if (value == null || depth > 4) return;
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) out.add(trimmed);
    return;
  }
  if (value is num || value is bool) {
    out.add('$value');
    return;
  }
  if (value is List) {
    for (final item in value) {
      _collectSearchStrings(item, depth + 1, out);
    }
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key == 'id' || entry.key == 'timestamp') continue;
      _collectSearchStrings(entry.value, depth + 1, out);
    }
    return;
  }
}

/// Returns a snippet of [text] if it matches [query], or null if no match.
///
/// Matching strategy (most-specific first):
/// 1. Exact substring (case-insensitive) — highest fidelity, returns a
///    centred snippet.
/// 2. Separator-normalised substring — spaces, underscores, hyphens and dots
///    are treated as equivalent (e.g. "demo copilot" matches "demo_copilot").
/// 3. All-words anywhere — every whitespace-token in the query appears
///    somewhere in the normalised text (order-independent).
String? matchSnippet(String text, String query) {
  final haystack = text.toLowerCase();
  final needle = query.toLowerCase().trim();

  // 1. Exact substring match.
  final exactIdx = haystack.indexOf(needle);
  if (exactIdx >= 0) {
    return buildSnippet(text, exactIdx, needle.length);
  }

  // Normalise both sides: replace _, -, . with space.
  final normHaystack = haystack.replaceAll(RegExp(r'[_\-.]'), ' ');
  final normNeedle = needle.replaceAll(RegExp(r'[_\-.]'), ' ');

  // 2. Separator-normalised substring match.
  final normIdx = normHaystack.indexOf(normNeedle);
  if (normIdx >= 0) {
    return buildSnippet(text, normIdx, normNeedle.length);
  }

  // 3. All query words present anywhere (order-independent).
  final queryWords =
      normNeedle.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (queryWords.length > 1) {
    final allMatch = queryWords.every((w) => normHaystack.contains(w));
    if (allMatch) {
      // Find the first word match to anchor the snippet.
      final firstIdx = normHaystack.indexOf(queryWords.first);
      return buildSnippet(
        text,
        firstIdx < 0 ? 0 : firstIdx,
        queryWords.first.length,
      );
    }
  }

  return null;
}

String buildSnippet(String text, int matchIdx, int matchLen) {
  final start = (matchIdx - 48).clamp(0, text.length);
  final end = (matchIdx + matchLen + 72).clamp(0, text.length);
  final prefix = start > 0 ? '…' : '';
  final suffix = end < text.length ? '…' : '';
  return '$prefix${text.substring(start, end).replaceAll('\n', ' ')}$suffix';
}
