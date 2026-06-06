import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract class SessionHistoryStore<T> {
  String get key;
  T fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson(T entry);
  String idOf(T entry);

  Future<List<T>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<T> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(entries.map(toJson).toList()));
  }

  Future<void> delete(String id) async {
    final entries = await loadAll();
    entries.removeWhere((e) => idOf(e) == id);
    await saveAll(entries);
  }
}
