import 'package:flutter/foundation.dart';

// Conditional import so the right implementation is used on web vs desktop.
import 'package:yoloit/core/platform/file_storage_adapter_factory.dart'
    as impl;

/// Platform-agnostic file-system-like storage used by services that today
/// read/write files under `PlatformDirs` paths.
///
/// On desktop this delegates to `dart:io` files. On web it stores data in
/// browser storage (`shared_preferences` / localStorage) using the file path
/// as a scoped key.
abstract class FileStorageAdapter {
  const FileStorageAdapter();

  /// Shared instance — VM or web depending on the build target.
  static FileStorageAdapter get instance => _instance;
  static final FileStorageAdapter _instance = impl.getAdapter();

  /// Returns whether anything has been stored at [path].
  Future<bool> exists(String path);

  /// Reads UTF-8 text stored at [path], or `null` if missing.
  Future<String?> readString(String path);

  /// Reads raw bytes stored at [path], or `null` if missing.
  Future<Uint8List?> readBytes(String path);

  /// Writes UTF-8 text to [path], creating parent directories implicitly.
  Future<void> writeString(String path, String contents);

  /// Writes raw bytes to [path].
  Future<void> writeBytes(String path, Uint8List bytes);

  /// Deletes the entry at [path] if it exists.
  Future<void> delete(String path);

  /// Lists file paths stored under [directoryPath].
  /// VM: uses `Directory.listSync`. Web: returns keys with the given prefix.
  Future<List<String>> list(String directoryPath);
}
