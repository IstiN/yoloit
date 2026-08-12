import 'dart:io';

import 'package:yoloit/core/platform/platform_shell.dart';

/// Resolves agent CLI executables for setup checks and provider bootstrapping.
///
/// GUI-launched YoLoIT processes inherit a minimal PATH. This helper mirrors
/// [PlatformShell.enrichedPath] and also probes well-known install locations
/// such as `~/.kimi-code/bin/kimi` and `~/.local/bin/cursor-agent`.
abstract final class AgentCliDiscovery {
  /// Cache for subprocess lookups: (command → resolved path).
  /// Avoids spawning `which`/`where` repeatedly for the same binary.
  static final _execCache = <String, String?>{};

  static Map<String, String> extendedEnvironment() {
    final env = Map<String, String>.from(Platform.environment);
    env['PATH'] = PlatformShell.instance.enrichedPath(env['PATH'] ?? '');
    return env;
  }

  static Future<String?> findExecutable(String command) async {
    if (_execCache.containsKey(command)) {
      return _execCache[command];
    }
    final onPath = await _findOnPath(command);
    final result = onPath ?? _findKnownLocation(command);
    _execCache[command] = result;
    return result;
  }

  static Future<String?> _findOnPath(String command) async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run(
          'where',
          [command],
          environment: extendedEnvironment(),
          runInShell: true,
        ).timeout(const Duration(seconds: 5));
        final out = (result.stdout as String).trim().split('\n').first.trim();
        if (result.exitCode == 0 && out.isNotEmpty) return out;
      } catch (_) {}
      return null;
    }

    try {
      final result = await Process.run('/bin/sh', [
        '-lc',
        'command -v ${_shellQuote(command)} 2>/dev/null',
      ], environment: extendedEnvironment()).timeout(const Duration(seconds: 5));
      final out = (result.stdout as String).trim().split('\n').first.trim();
      if (result.exitCode == 0 && out.isNotEmpty) return out;
    } catch (_) {}
    return null;
  }

  static String? _findKnownLocation(String command) {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    if (home.isEmpty) return null;

    final candidates = switch (command) {
      'kimi' => <String>[
        '$home/.kimi-code/bin/kimi',
        if (Platform.isWindows) '$home/AppData/Local/Programs/kimi-code/kimi.exe',
      ],
      'cursor-agent' => <String>[
        '$home/.local/bin/cursor-agent',
        if (Platform.isWindows)
          '$home/AppData/Local/cursor-agent/cursor-agent.exe',
        '/Applications/Cursor.app/Contents/Resources/app/bin/cursor-agent',
      ],
      'cursor' => <String>[
        '/Applications/Cursor.app/Contents/Resources/app/bin/cursor',
        if (Platform.isWindows)
          '${Platform.environment['LOCALAPPDATA'] ?? ''}\\Programs\\cursor\\resources\\app\\bin\\cursor.exe',
      ],
      _ => const <String>[],
    };

    for (final path in candidates) {
      if (path.isEmpty) continue;
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";
}
