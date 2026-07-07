import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/board/common/session_history_store.dart';

part 'chat_session_history.g.dart';

/// Stores a registry of past chat sessions for browsing/resuming.
///
/// Metadata is kept in SharedPreferences for fast access.
/// Full message history is stored as JSON files on disk under
/// `<PlatformDirs.instance.dataDir>/chat_sessions/<id>.json`.
class ChatSessionHistory extends SessionHistoryStore<ChatSessionEntry> {
  ChatSessionHistory._();
  static final instance = ChatSessionHistory._();

  @override
  String get key => 'chat_session_history';

  @override
  ChatSessionEntry fromJson(Map<String, dynamic> json) =>
      ChatSessionEntry.fromJson(json);

  @override
  Map<String, dynamic> toJson(ChatSessionEntry entry) => entry.toJson();

  @override
  String idOf(ChatSessionEntry entry) => entry.id;

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
    await saveAll(entries);
    // Persist messages to disk
    if (messages != null && messages.isNotEmpty) {
      await _saveMessages(entry.id, messages);
    }
  }

  /// Load messages for a specific session.
  Future<List<Map<String, dynamic>>> loadMessages(String id) async {
    final path = await _messagePath(id);
    if (!await FileStorageAdapter.instance.exists(path)) return [];
    try {
      final raw = await FileStorageAdapter.instance.readString(path);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // ── File helpers ──────────────────────────────────────────────────────────

  Future<String> _messagePath(String id) async {
    final safe = id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return '${PlatformDirs.instance.dataDir}/chat_sessions/$safe.json';
  }

  Future<void> _saveMessages(
    String id,
    List<Map<String, dynamic>> messages,
  ) async {
    final path = await _messagePath(id);
    await FileStorageAdapter.instance.writeString(path, jsonEncode(messages));
  }

  Future<void> _deleteMessageFile(String id) async {
    final path = await _messagePath(id);
    if (await FileStorageAdapter.instance.exists(path)) {
      await FileStorageAdapter.instance.delete(path);
    }
  }
}

/// A single session history entry.
@JsonSerializable()
class ChatSessionEntry {
  const ChatSessionEntry({
    required this.id,
    required this.sessionName,
    required this.provider,
    required this.model,
    required this.workingDir,
    required this.createdAt,
    this.envGroupIds = const [],
    this.lastMessageAt,
    this.messageCount = 0,
  });

  @JsonKey(defaultValue: '')
  final String id;
  @JsonKey(defaultValue: '')
  final String sessionName;
  @JsonKey(defaultValue: 'copilot')
  final String provider;
  @JsonKey(defaultValue: '')
  final String model;
  @JsonKey(defaultValue: '')
  final String workingDir;
  @JsonKey(defaultValue: <String>[])
  final List<String> envGroupIds;
  @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
  final DateTime createdAt;
  final DateTime? lastMessageAt;
  @JsonKey(defaultValue: 0)
  final int messageCount;

  static DateTime _dateTimeFromJson(dynamic json) =>
      json == null ? DateTime.now() : DateTime.parse(json as String);
  static String _dateTimeToJson(DateTime dt) => dt.toIso8601String();

  Map<String, dynamic> toJson() => _$ChatSessionEntryToJson(this);

  factory ChatSessionEntry.fromJson(Map<String, dynamic> json) =>
      _$ChatSessionEntryFromJson(json);
}
