import 'dart:io';

/// Opens [url] in the platform default browser.
///
/// No-op on unsupported platforms or if the launch command fails.
Future<void> openUrl(String url) async {
  String command;
  List<String> args;
  if (Platform.isMacOS) {
    command = 'open';
    args = <String>[url];
  } else if (Platform.isLinux) {
    command = 'xdg-open';
    args = <String>[url];
  } else if (Platform.isWindows) {
    command = 'start';
    args = <String>['', url];
  } else {
    return;
  }
  try {
    await Process.run(command, args);
  } on ProcessException {
    // Ignore — there is no browser to open or the command is missing.
  }
}
