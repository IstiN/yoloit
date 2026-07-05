import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/file_storage_adapter.dart';

FileStorageAdapter getAdapter() => const WebFileStorageAdapter();

/// Web implementation of [FileStorageAdapter] backed by browser storage
/// (`shared_preferences` / localStorage). Paths are used as stable keys.
class WebFileStorageAdapter implements FileStorageAdapter {
  const WebFileStorageAdapter();

  static const _prefix = 'yoloit.fs.';

  String _key(String path) => '$_prefix$path';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<bool> exists(String path) async {
    final prefs = await _prefs;
    return prefs.containsKey(_key(path));
  }

  @override
  Future<String?> readString(String path) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_key(path));
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  @override
  Future<Uint8List?> readBytes(String path) async {
    final prefs = await _prefs;
    final raw = prefs.getString('${_key(path)}.bytes');
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeString(String path, String contents) async {
    final prefs = await _prefs;
    await prefs.setString(_key(path), contents);
  }

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    final prefs = await _prefs;
    await prefs.setString('${_key(path)}.bytes', base64Encode(bytes));
  }

  @override
  Future<void> delete(String path) async {
    final prefs = await _prefs;
    await prefs.remove(_key(path));
    await prefs.remove('${_key(path)}.bytes');
  }

  @override
  Future<List<String>> list(String directoryPath) async {
    final prefs = await _prefs;
    final prefix = _key(directoryPath);
    return prefs
        .getKeys()
        .where((k) => k.startsWith(prefix))
        .where((k) => !k.endsWith('.bytes'))
        .map((k) => k.substring(_prefix.length))
        .toList();
  }
}
