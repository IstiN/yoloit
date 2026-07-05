/// Web stub for the `dart:io` symbols used by [ProviderModelCatalogService].
class Process {
  static Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    throw UnsupportedError('Process spawning is not supported on web');
  }

  Stream<List<int>> get stdout => const Stream.empty();
  Stream<List<int>> get stderr => const Stream.empty();
  Future<int> get exitCode => Future.value(1);
}

class Platform {
  static Map<String, String> get environment => const {};
}
