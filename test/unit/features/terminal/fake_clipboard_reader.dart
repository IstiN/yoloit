import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:super_clipboard/super_clipboard.dart';

/// In-memory [DataReaderFile] used by [FakeClipboardDataReader].
class FakeDataReaderFile implements DataReaderFile {
  FakeDataReaderFile(this._bytes, {this.throwOnRead = false});

  final Uint8List _bytes;
  final bool throwOnRead;

  @override
  String? get fileName => null;

  @override
  int? get fileSize => _bytes.length;

  @override
  Stream<Uint8List> getStream() => Stream.value(_bytes);

  @override
  void close() {}

  @override
  Future<Uint8List> readAll() {
    if (throwOnRead) return Future.error(StateError('read failed'));
    return Future.value(_bytes);
  }
}

/// In-memory [ClipboardDataReader] with configurable text and file payloads.
///
/// super_clipboard reads the system clipboard through a plugin that is not
/// available in unit tests, so tests compose a [ClipboardReader] from these
/// fakes instead.
class FakeClipboardDataReader extends ClipboardDataReader {
  FakeClipboardDataReader({
    this.plainText,
    Map<FileFormat, Uint8List> files = const {},
    Set<FileFormat> throwingFormats = const {},
  }) : _files = files,
       _throwingFormats = throwingFormats;

  final String? plainText;
  // Initializer-list assignments keep the public parameter names.
  // ignore: prefer_initializing_formals
  final Map<FileFormat, Uint8List> _files;

  /// Formats that report canProvide=true but fail while reading.
  // ignore: prefer_initializing_formals
  final Set<FileFormat> _throwingFormats;

  Uint8List? _bytesFor(FileFormat format) {
    for (final entry in _files.entries) {
      if (identical(entry.key, format)) return entry.value;
    }
    return null;
  }

  bool _throwsFor(FileFormat format) =>
      _throwingFormats.any((f) => identical(f, format));

  @override
  List<DataFormat> getFormats(List<DataFormat> allFormats) {
    return allFormats.where((format) {
      if (identical(format, Formats.plainText)) return plainText != null;
      if (format is FileFormat) {
        return _bytesFor(format) != null || _throwsFor(format);
      }
      return false;
    }).toList();
  }

  @override
  Future<T?> readValue<T extends Object>(ValueFormat<T> format) async {
    if (identical(format, Formats.plainText)) return plainText as T?;
    return null;
  }

  @override
  ReadProgress? getValue<T extends Object>(
    ValueFormat<T> format,
    AsyncValueChanged<T?> onValue, {
    ValueChanged<Object>? onError,
  }) {
    return null;
  }

  @override
  ReadProgress? getFile(
    FileFormat? format,
    AsyncValueChanged<DataReaderFile> onFile, {
    ValueChanged<Object>? onError,
    bool allowVirtualFiles = true,
    bool synthesizeFilesFromURIs = true,
  }) {
    if (format == null) return null;
    if (_throwsFor(format)) {
      _deliver(onFile, FakeDataReaderFile(Uint8List(0), throwOnRead: true));
      return null;
    }
    final bytes = _bytesFor(format);
    if (bytes == null) return null;
    _deliver(onFile, FakeDataReaderFile(bytes));
    return null;
  }

  void _deliver(
    AsyncValueChanged<DataReaderFile> onFile,
    DataReaderFile file,
  ) {
    final result = onFile(file);
    if (result is Future<void>) unawaited(result);
  }

  @override
  bool isSynthesized(DataFormat format) => false;

  @override
  bool isVirtual(DataFormat format) => false;

  @override
  Future<String?> getSuggestedName() async => null;

  @override
  Future<VirtualFileReceiver?> getVirtualFileReceiver({
    FileFormat? format,
  }) async => null;

  @override
  List<PlatformFormat> get platformFormats => const [];
}
