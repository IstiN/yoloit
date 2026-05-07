import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BoardTerminalSessionHistory {
  BoardTerminalSessionHistory._();

  static final instance = BoardTerminalSessionHistory._();
  static const _key = 'board_terminal_session_history';

  Future<List<BoardTerminalSessionEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map(
            (e) => BoardTerminalSessionEntry.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> upsert(BoardTerminalSessionEntry entry) async {
    final entries = await loadAll();
    final idx = entries.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      final previous = entries[idx];
      entries[idx] = entry.copyWith(createdAt: previous.createdAt);
    } else {
      entries.insert(0, entry);
    }
    entries.sort(
      (a, b) => (b.lastActiveAt ?? b.createdAt).compareTo(
        a.lastActiveAt ?? a.createdAt,
      ),
    );
    if (entries.length > 50) {
      entries.removeRange(50, entries.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> delete(String id) async {
    final entries = await loadAll();
    entries.removeWhere((e) => e.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}

class BoardTerminalSessionEntry {
  const BoardTerminalSessionEntry({
    required this.id,
    required this.sessionName,
    required this.workingDir,
    required this.createdAt,
    this.envGroupIds = const [],
    this.lastActiveAt,
  });

  final String id;
  final String sessionName;
  final String workingDir;
  final List<String> envGroupIds;
  final DateTime createdAt;
  final DateTime? lastActiveAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionName': sessionName,
    'workingDir': workingDir,
    if (envGroupIds.isNotEmpty) 'envGroupIds': envGroupIds,
    'createdAt': createdAt.toIso8601String(),
    'lastActiveAt': lastActiveAt?.toIso8601String(),
  };

  factory BoardTerminalSessionEntry.fromJson(Map<String, dynamic> json) {
    return BoardTerminalSessionEntry(
      id: json['id'] as String? ?? '',
      sessionName: json['sessionName'] as String? ?? '',
      workingDir: json['workingDir'] as String? ?? '',
      envGroupIds: (json['envGroupIds'] as List?)?.cast<String>() ?? const [],
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      lastActiveAt:
          json['lastActiveAt'] != null
              ? DateTime.tryParse(json['lastActiveAt'] as String)
              : null,
    );
  }

  BoardTerminalSessionEntry copyWith({
    String? id,
    String? sessionName,
    String? workingDir,
    List<String>? envGroupIds,
    DateTime? createdAt,
    DateTime? lastActiveAt,
  }) {
    return BoardTerminalSessionEntry(
      id: id ?? this.id,
      sessionName: sessionName ?? this.sessionName,
      workingDir: workingDir ?? this.workingDir,
      envGroupIds: envGroupIds ?? this.envGroupIds,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }
}
