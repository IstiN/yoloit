import 'dart:io';

/// macOS-specific service that ensures the `yoloit` CLI is accessible from
/// terminals and GUI apps after installation.
///
/// Runs a best-effort health-check on startup:
/// 1. User-local symlink: `~/.config/yoloit/yoloit`
/// 2. Shell profile PATH entries (`~/.zshrc`, `~/.bashrc`)
/// 3. System-wide symlink: `/usr/local/bin/yoloit` (via AppleScript sudo)
/// 4. System PATH entry: `/etc/paths.d/yoloit` (via AppleScript sudo)
class MacosCliSetupService {
  MacosCliSetupService._();
  static final instance = MacosCliSetupService._();

  Future<void> ensureInstalled() async {
    if (!Platform.isMacOS) return;

    final appBundle = _resolveAppBundle();
    if (appBundle == null) return;

    final cliSource = File(
      '$appBundle/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/tools/yoloit',
    );
    if (!cliSource.existsSync()) return;

    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return;

    // 1. User-local symlink (always works without sudo)
    await _installUserLocalSymlink(cliSource.path, home);

    // 2. Shell profile PATH entries
    await _ensureShellProfiles(home);

    // 3. System-wide symlink (best-effort via AppleScript sudo)
    await _installSystemSymlink(cliSource.path);

    // 4. System PATH entry (best-effort via AppleScript sudo)
    await _installPathsDEntry(home);
  }

  Future<void> _installUserLocalSymlink(String cliSource, String home) async {
    final userDir = '$home/.config/yoloit';
    await Directory(userDir).create(recursive: true);
    final userLink = File('$userDir/yoloit');
    if (userLink.existsSync()) userLink.deleteSync();
    try {
      await Process.run('ln', ['-s', cliSource, userLink.path]);
    } catch (_) {
      // Best-effort
    }
  }

  Future<void> _ensureShellProfiles(String home) async {
    const pathLine = 'export PATH="\$HOME/.config/yoloit:\$PATH"';
    const comment = '# YoLoIT CLI';

    for (final rc in ['$home/.zshrc', '$home/.bashrc']) {
      final file = File(rc);
      if (!file.existsSync()) continue;
      final content = await file.readAsString();
      if (content.contains(pathLine)) continue;
      await file.writeAsString('\n$comment\n$pathLine\n', mode: FileMode.append);
    }
  }

  Future<void> _installSystemSymlink(String cliSource) async {
    const systemLink = '/usr/local/bin/yoloit';
    try {
      final result = await Process.run('ln', ['-sf', cliSource, systemLink]);
      if (result.exitCode != 0) {
        // Try with sudo via AppleScript dialog
        await _runWithSudo(
          'mkdir -p /usr/local/bin && ln -sf "$cliSource" "$systemLink"',
        );
      }
    } catch (_) {
      // Best-effort
    }
  }

  Future<void> _installPathsDEntry(String home) async {
    const pathsFile = '/etc/paths.d/yoloit';
    final content = '$home/.config/yoloit\n';
    try {
      final result = await Process.run(
        'sh',
        ['-c', 'echo "$content" | tee "$pathsFile" > /dev/null'],
      );
      if (result.exitCode != 0) {
        await _runWithSudo(
          'echo "$content" | tee "$pathsFile" > /dev/null',
        );
      }
    } catch (_) {
      // Best-effort
    }
  }

  Future<void> _runWithSudo(String shellCommand) async {
    try {
      await Process.run('osascript', [
        '-e',
        'do shell script "$shellCommand" with administrator privileges',
      ]);
    } catch (_) {
      // User cancelled or failed — ignore
    }
  }

  String? _resolveAppBundle() {
    final exe = Platform.resolvedExecutable;
    // .../YoLoIT.app/Contents/MacOS/YoLoIT
    final parts = exe.split('/Contents/');
    if (parts.length < 2) return null;
    return parts[0];
  }
}
