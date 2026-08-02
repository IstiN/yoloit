import 'dart:io';
import 'dart:typed_data';

import 'package:yoloit/core/platform/file_storage_adapter.dart';

FileStorageAdapter getAdapter() => const VmFileStorageAdapter();

/// Desktop / VM implementation of [FileStorageAdapter] backed by `dart:io`.
class VmFileStorageAdapter implements FileStorageAdapter {
  const VmFileStorageAdapter();

  File _file(String path) => File(path);

  Directory _dir(String path) => Directory(path);

  Future<void> _ensureParent(String path) async {
    final parent = _file(path).parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
  }

  @override
  Future<bool> exists(String path) => _file(path).exists();

  @override
  Future<String?> readString(String path) async {
    final file = _file(path);
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } on FormatException {
      return null;
    }
  }

  @override
  Future<Uint8List?> readBytes(String path) async {
    final file = _file(path);
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  }

  @override
  Future<void> writeString(String path, String contents) async {
    await _ensureParent(path);
    await _file(path).writeAsString(contents, flush: true);
  }

  @override
  Future<void> appendString(String path, String contents) async {
    await _ensureParent(path);
    await _file(path).writeAsString(contents, mode: FileMode.append);
  }

  @override
  Future<int?> length(String path) async {
    final file = _file(path);
    if (!await file.exists()) return null;
    return await file.length();
  }

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    await _ensureParent(path);
    await _file(path).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> delete(String path) async {
    final file = _file(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<List<String>> list(String directoryPath) async {
    final dir = _dir(directoryPath);
    if (!await dir.exists()) return const [];
    return dir
        .listSync(recursive: false)
        .whereType<File>()
        .map((f) => f.path)
        .toList();
  }
}
