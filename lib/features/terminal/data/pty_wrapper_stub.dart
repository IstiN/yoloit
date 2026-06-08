import 'dart:async';
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

  Stream<Uint8List> get output => Stream<Uint8List>.empty();
  Future<int> get exitCode => Future.value(0);
  int get pid => 0;

  void write(Uint8List data) {}
  void resize(int rows, int cols) {}
  bool kill([dynamic signal]) => false;
  void ackRead() {}
}
