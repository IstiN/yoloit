import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Stub Pty for web builds where dart:ffi is unavailable.
class Pty {
  Pty.start(
    this.executable, {
    this.arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 25,
    int columns = 80,
    bool ackRead = false,
  });

  final String executable;
  final List<String> arguments;

  Stream<String> get output => Stream<String>.empty();

  /// No byte channel on the web stub (no PTY at all) — mirrors the io
  /// facade's default.
  Stream<Uint8List>? get outputBytes => null;

  Future<int> get exitCode => Future.value(0);
  int get pid => 0;

  void write(Uint8List data) {}
  void resize(int rows, int cols) {}
  bool kill([dynamic signal]) => false;
  void ackRead() {}
}

/// Web stub: no native ack flow control exists, so the source passes through.
Stream<T> ackOnData<T>(void Function() ack, Stream<T> source) => source;

/// Web stub matching pty_wrapper_io.dart's decoder. No PTY exists on the
/// web, so a plain malformed-tolerant UTF-8 decode is sufficient.
class BufferedUtf8Decoder extends StreamTransformerBase<List<int>, String> {
  const BufferedUtf8Decoder();

  @override
  Stream<String> bind(Stream<List<int>> stream) {
    const decoder = Utf8Decoder(allowMalformed: true);
    return stream.map(decoder.convert).where((s) => s.isNotEmpty);
  }
}
