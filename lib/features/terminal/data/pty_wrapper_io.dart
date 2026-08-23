import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart' as flutter_pty;
import 'package:pty2/pty2.dart' as pty2;

/// Unified PTY facade over two backends:
///
/// - **pty2** (release builds on Unix): 80KB native reads (vs 1KB in
///   flutter_pty) and UTF-8 decoding in a worker isolate, so the UI isolate
///   receives decoded strings instead of per-KB byte chunks. Its long-lived
///   isolates block Flutter hot reload, so debug builds keep flutter_pty.
/// - **flutter_pty** (debug builds, and Windows where our dependency set
///   pins win32 5.x): the original backend.
///
/// Both are started with ack-based flow control: the native side blocks
/// after each chunk until [ackRead] releases it (see [ackOnData]), so a busy
/// UI isolate cannot be flooded faster than it processes output.
abstract class Pty {
  factory Pty.start(
    String executable, {
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 25,
    int columns = 80,
    bool ackRead = false,
  }) {
    if (usePty2) {
      return _Pty2Impl(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        rows: rows,
        columns: columns,
        ackRead: ackRead,
      );
    }
    return _FlutterPtyImpl(
      executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      rows: rows,
      columns: columns,
      ackRead: ackRead,
    );
  }

  /// Whether the pty2 backend is used. Defaults to release builds on Unix;
  /// pty2's long-lived isolates prevent Flutter hot reload, and its fork is
  /// Unix-only, so debug builds and Windows stay on flutter_pty.
  static bool get usePty2 =>
      debugUsePty2Override ?? (!kDebugMode && !Platform.isWindows);

  /// Test/benchmark hook to force the backend regardless of build mode.
  @visibleForTesting
  static bool? debugUsePty2Override;

  /// Decoded UTF-8 output of the process (stdout+stderr are merged by PTYs).
  Stream<String> get output;
  Future<int> get exitCode;
  int get pid;

  void write(Uint8List data);

  /// Note the parameter order: rows first, then columns.
  void resize(int rows, int cols);
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
  void ackRead();
}

/// Applies the ack contract of `ackProcessed`/`ackRead` flow control:
/// acks exactly once per delivered chunk, plus once on cancel so the native
/// reader (blocked waiting for the ack) can observe the closed fd and exit.
/// After the source ends, no ack is owed (the reader has already exited).
@visibleForTesting
Stream<T> ackOnData<T>(void Function() ack, Stream<T> source) {
  return Stream.multi((controller) {
    var sourceEnded = false;
    final sub = source.listen(
      (chunk) {
        ack();
        controller.add(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        sourceEnded = true;
        controller.addError(error, stackTrace);
      },
      onDone: () {
        sourceEnded = true;
        controller.close();
      },
    );
    controller.onCancel = () async {
      // Only ack if the source is still live: after done/error the native
      // read thread has already exited and no ack is owed.
      if (!sourceEnded) ack();
      await sub.cancel();
    };
  });
}

/// pty2 backend: output arrives as decoded UTF-8 strings from the worker
/// isolate, so no decoding happens on the UI isolate at all.
class _Pty2Impl implements Pty {
  _Pty2Impl(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 25,
    int columns = 80,
    bool ackRead = false,
  }) : _inner = pty2.PseudoTerminal.start(
          executable,
          arguments,
          workingDirectory: workingDirectory,
          environment: environment,
          ackProcessed: ackRead,
        ) {
    _inner.resize(columns, rows);
  }

  final pty2.PseudoTerminal _inner;

  @override
  Stream<String> get output => ackOnData(_inner.ackProcessed, _inner.out);

  @override
  Future<int> get exitCode => _inner.exitCode;

  @override
  int get pid => _inner.pid;

  @override
  void write(Uint8List data) {
    _inner.write(utf8.decode(data, allowMalformed: true));
  }

  @override
  void resize(int rows, int cols) {
    // pty2.resize takes (width, height) = (cols, rows).
    _inner.resize(cols, rows);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _inner.kill(signal);

  @override
  void ackRead() => _inner.ackProcessed();
}

/// flutter_pty backend: raw byte chunks, decoded on the UI isolate through
/// the buffered decoder (split multi-byte sequences are stitched).
class _FlutterPtyImpl implements Pty {
  _FlutterPtyImpl(
    String executable, {
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 25,
    int columns = 80,
    bool ackRead = false,
  }) : _inner = flutter_pty.Pty.start(
          executable,
          arguments: arguments,
          workingDirectory: workingDirectory,
          environment: environment,
          rows: rows,
          columns: columns,
          ackRead: ackRead,
        );

  final flutter_pty.Pty _inner;

  @override
  Stream<String> get output => ackOnData(
        _inner.ackRead,
        _inner.output.cast<List<int>>(),
      ).transform(const BufferedUtf8Decoder());

  @override
  Future<int> get exitCode => _inner.exitCode;

  @override
  int get pid => _inner.pid;

  @override
  void write(Uint8List data) => _inner.write(data);

  @override
  void resize(int rows, int cols) => _inner.resize(rows, cols);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _inner.kill(signal);

  @override
  void ackRead() => _inner.ackRead();
}

/// A Utf8Decoder that buffers incomplete trailing multi-byte sequences
/// instead of emitting U+FFFD replacement characters. Terminal escape
/// parsers are byte-order sensitive, so feeding them replacement chars for
/// split emoji/CJK corrupts state. The carry is flushed (as replacements)
/// only on stream end.
class BufferedUtf8Decoder extends StreamTransformerBase<List<int>, String> {
  const BufferedUtf8Decoder();

  @override
  Stream<String> bind(Stream<List<int>> stream) {
    const decoder = Utf8Decoder(allowMalformed: true);
    var carry = <int>[];
    return stream.map((chunk) {
      // Avoid the spread-copy when there is no incomplete tail from the
      // previous chunk (the overwhelmingly common case).
      final combined = carry.isEmpty ? chunk : [...carry, ...chunk];
      final validLen = _validUtf8Length(combined);
      if (validLen == 0) {
        carry = combined;
        return '';
      }
      // Reuse the list when fully valid (common case) — the decoder does not
      // retain it; sublist copies only when an incomplete tail exists.
      final toDecode =
          validLen == combined.length ? combined : combined.sublist(0, validLen);
      carry = combined.sublist(validLen);
      return decoder.convert(toDecode);
    }).where((s) => s.isNotEmpty);
  }

  /// Returns the length of the longest prefix of [bytes] that ends on a
  /// complete UTF-8 character. Only the tail can hold an incomplete
  /// sequence, so scanning the last 4 bytes (max sequence length) suffices.
  static int _validUtf8Length(List<int> bytes) {
    var i = bytes.length;
    final min = bytes.length > 4 ? bytes.length - 4 : 0;
    while (i > min) {
      i--;
      if (_isValidUtf8Boundary(bytes, i)) {
        // bytes[i] starts a character that is fully contained in [bytes];
        // the valid prefix extends past the whole character.
        return i + _utf8SequenceLength(bytes[i]);
      }
    }
    return 0;
  }

  static bool _isValidUtf8Boundary(List<int> bytes, int index) {
    final b = bytes[index];
    if (b < 0x80) return true;
    if ((b & 0xC0) == 0x80) return false;
    final len = _utf8SequenceLength(b);
    return index + len <= bytes.length;
  }

  static int _utf8SequenceLength(int firstByte) {
    if (firstByte < 0xC0) return 1;
    if (firstByte < 0xE0) return 2;
    if (firstByte < 0xF0) return 3;
    return 4;
  }
}
