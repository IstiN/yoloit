import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores a registry of past chat sessions for browsing/resuming.
class ChatSessionHistory {
  ChatSessionHistory._();
  static final instance = ChatSessionHistory._();

  static const _key = 'chat_session_history';

  /// Save or update a session entry.
  Future<void> upsert(ChatSessionEntry entry) async {
    final entries = await loadAll();
    final idx = entries.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      entries[idx] = entry;
    } else {
      entries.insert(0, entry);
    }
    // Keep last 50 sessions
    if (entries.length > 50) entries.removeRange(50, entries.length);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  /// Load all session entries.
  Future<List<ChatSessionEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => ChatSessionEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Delete a session entry by ID.
  Future<void> delete(String id) async {
    final entries = await loadAll();
    entries.removeWhere((e) => e.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(entries.map((e) => e.toJson()).toList()));
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
