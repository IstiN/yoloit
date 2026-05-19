import 'dart:convert';
import 'dart:io';

/// Captures [Process.run]-style calls for unit testing platform services.
///
/// Usage:
/// ```dart
/// final runner = FakeProcessRunner();
/// runner.mockResult('open', exitCode: 0, stdout: '');
/// final svc = MacosPlatformLauncher(processRunner: runner.run);
/// await svc.openUrl('https://example.com');
/// expect(runner.calls.last.executable, 'open');
/// ```
class FakeProcessRunner {
  final List<ProcessCall> calls = [];
  final Map<String, ProcessResult> _results = {};
  final Map<String, ProcessResult> _resultsByCallKey = {};
  final Map<String, List<ProcessResult>> _resultQueues = {};
  final Set<String> _throwOn = {};

  /// Registers a result to return when [executable] is invoked.
  void mockResult(
    String executable, {
    int exitCode = 0,
    String stdout = '',
    String stderr = '',
  }) {
    _results[executable] = ProcessResult(0, exitCode, stdout, stderr);
  }

  /// Registers a result for a specific executable + argument list.
  void mockResultFor(
    String executable,
    List<String> arguments, {
    int exitCode = 0,
    String stdout = '',
    String stderr = '',
  }) {
    _resultsByCallKey[_callKey(executable, arguments)] =
        ProcessResult(0, exitCode, stdout, stderr);
  }

  /// Returns results in order for repeated invocations of [executable].
  void mockResultQueue(String executable, List<ProcessResult> results) {
    _resultQueues[executable] = List<ProcessResult>.from(results);
  }

  /// Makes [run] throw when [executable] is invoked.
  void mockThrow(String executable) {
    _throwOn.add(executable);
  }

  static String _callKey(String executable, List<String> arguments) =>
      '$executable::${arguments.join('\0')}';

  /// Mimics [Process.run] signature. Returns the registered result or a
  /// success result with empty output if no mock was registered.
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) async {
    calls.add(
      ProcessCall(
        executable: executable,
        arguments: arguments,
        runInShell: runInShell,
      ),
    );
    if (_throwOn.contains(executable)) {
      throw StateError('mock throw: $executable');
    }
    final callKey = _callKey(executable, arguments);
    if (_resultsByCallKey.containsKey(callKey)) {
      return _resultsByCallKey[callKey]!;
    }
    final queue = _resultQueues[executable];
    if (queue != null && queue.isNotEmpty) {
      return queue.removeAt(0);
    }
    return _results[executable] ?? ProcessResult(0, 0, '', '');
  }

  ProcessCall? get lastCall => calls.isEmpty ? null : calls.last;

  void reset() {
    calls.clear();
    _results.clear();
    _resultsByCallKey.clear();
    _resultQueues.clear();
    _throwOn.clear();
  }
}

class ProcessCall {
  final String executable;
  final List<String> arguments;
  final bool runInShell;

  const ProcessCall({
    required this.executable,
    required this.arguments,
    this.runInShell = false,
  });

  @override
  String toString() => '$executable ${arguments.join(' ')}';
}
