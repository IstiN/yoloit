/// Stub [File] implementation for the web build.
///
/// The VM [CliTextArgumentResolver] uses [File] to read YoLoIT clip temp
/// files. In the browser those files do not exist, so this stub always reports
/// that the file is missing and returns an empty string.
class File {
  File(this.path);

  final String path;

  bool existsSync() => false;

  String readAsStringSync() => '';
}
