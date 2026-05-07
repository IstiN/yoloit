import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores a registry of past chat sessions for browsing/resuming.
///
/// Metadata is kept in SharedPreferences for fast access.
/// Full message history is stored as JSON files on disk under
/// `<appSupportDir>/chat_sessions/<id>.json`.
class ChatSessionHistory {
  ChatSessionHistory._();
  static final instance = ChatSessionHistory._();

  static const _key = 'chat_session_history';

  /// Temporary store for messages to restore into a newly created panel.
  /// Key is the new panel ID, value is the message list.
  /// ChatPanelWidget checks this in initState and consumes the entry.
  static final Map<String, List<Map<String, dynamic>>> restoredMessages = {};

  /// Save or update a session entry (metadata + messages).
  Future<void> upsert(
    ChatSessionEntry entry, {
    List<Map<String, dynamic>>? messages,
  }) async {
    final entries = await loadAll();
    final idx = entries.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      entries[idx] = entry;
    } else {
      entries.insert(0, entry);
    }
    // Keep last 50 sessions
    if (entries.length > 50) {
      for (final old in entries.sublist(50)) {
        await _deleteMessageFile(old.id);
      }
      entries.removeRange(50, entries.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
    // Persist messages to disk
    if (messages != null && messages.isNotEmpty) {
      await _saveMessages(entry.id, messages);
    }
  }

  /// Load all session entries (metadata only).
  Future<List<ChatSessionEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ChatSessionEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Load messages for a specific session.
  Future<List<Map<String, dynamic>>> loadMessages(String id) async {
    final file = await _messageFile(id);
    if (!file.existsSync()) return [];
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Delete a session entry by ID (metadata + messages).
  Future<void> delete(String id) async {
    final entries = await loadAll();
    entries.removeWhere((e) => e.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
    await _deleteMessageFile(id);
  }

  // ── File helpers ──────────────────────────────────────────────────────────

  Future<Directory> _sessionsDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}/chat_sessions');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _messageFile(String id) async {
    final dir = await _sessionsDir();
    // Sanitize id for filename
    final safe = id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return File('${dir.path}/$safe.json');
  }

  Future<void> _saveMessages(
    String id,
    List<Map<String, dynamic>> messages,
  ) async {
    final file = await _messageFile(id);
    await file.writeAsString(jsonEncode(messages));
  }

  Future<void> _deleteMessageFile(String id) async {
    final file = await _messageFile(id);
    if (file.existsSync()) await file.delete();
  }
}

/// A single session history entry.
class ChatSessionEntry {
  const ChatSessionEntry({
    required this.id,
    required this.sessionName,
    required this.provider,
    required this.model,
    required this.workingDir,
    required this.createdAt,
    this.lastMessageAt,
    this.messageCount = 0,
  });

  final String id;
  final String sessionName;
  final String provider;
  final String model;
  final String workingDir;
  final DateTime createdAt;
  final DateTime? lastMessageAt;
  final int messageCount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionName': sessionName,
    'provider': provider,
    'model': model,
    'workingDir': workingDir,
    'createdAt': createdAt.toIso8601String(),
    'lastMessageAt': lastMessageAt?.toIso8601String(),
    'messageCount': messageCount,
  };

  factory ChatSessionEntry.fromJson(Map<String, dynamic> json) => ChatSessionEntry(
    id: json['id'] as String? ?? '',
    sessionName: json['sessionName'] as String? ?? '',
    provider: json['provider'] as String? ?? 'copilot',
    model: json['model'] as String? ?? '',
    workingDir: json['workingDir'] as String? ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    lastMessageAt: json['lastMessageAt'] != null
        ? DateTime.tryParse(json['lastMessageAt'] as String)
        : null,
    messageCount: json['messageCount'] as int? ?? 0,
  );
}
