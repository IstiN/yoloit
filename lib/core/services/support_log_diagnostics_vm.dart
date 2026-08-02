import 'dart:io';

import 'package:yoloit/core/services/app_logger.dart';
import 'package:yoloit/core/services/build_info.dart';

Future<String> buildSupportDiagnostics() async {
  final buf = StringBuffer();
  _appendPlatformInfo(buf);
  await _appendArchitectureInfo(buf);
  await _appendToolchainVersions(buf);
  _appendBuildInfo(buf);
  await _appendResvgAvailability(buf);
  await _appendGitInfo(buf);
  await _appendSubmoduleStatus(buf);
  return buf.toString();
}

void _appendPlatformInfo(StringBuffer buf) {
  buf.writeln(
    'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
  );
  buf.writeln('Dart: ${Platform.version}');
  buf.writeln('Resolved executable: ${Platform.resolvedExecutable}');
  buf.writeln('PATH: ${Platform.environment['PATH'] ?? '(empty)'}');
}

/// Runs [executable] and writes `<label>: <trimmed stdout>` when the command
/// succeeds. Writes the [onFailure] line when the command cannot be run.
Future<void> _appendCommandOutput(
  StringBuffer buf,
  String label,
  String executable,
  List<String> args, {
  String? onFailure,
}) async {
  try {
    final result = await Process.run(executable, args);
    if (result.exitCode == 0) {
      buf.writeln('$label: ${(result.stdout as String).trim()}');
    }
  } catch (_) {
    if (onFailure != null) {
      buf.writeln(onFailure);
    }
  }
}

// Architecture (system + binary)
Future<void> _appendArchitectureInfo(StringBuffer buf) async {
  await _appendCommandOutput(
    buf,
    'System architecture',
    'uname',
    const ['-m'],
    onFailure: 'System architecture: unknown',
  );
  await _appendCommandOutput(
    buf,
    'Binary file info',
    'file',
    [Platform.resolvedExecutable],
    onFailure: 'Binary file info: unavailable',
  );
  await _appendCommandOutput(
    buf,
    'Binary architectures',
    'lipo',
    ['-info', Platform.resolvedExecutable],
    onFailure: 'Binary architectures: unavailable',
  );
}

// Flutter / Dart toolchain versions
Future<void> _appendToolchainVersions(StringBuffer buf) async {
  try {
    final result = await Process.run('flutter', const ['--version']);
    if (result.exitCode == 0) {
      final lines = (result.stdout as String).trim().split('\n');
      if (lines.isNotEmpty) {
        buf.writeln('Flutter: ${lines.first.trim()}');
      }
    }
  } catch (_) {
    buf.writeln('Flutter: not found on PATH');
  }

  await _appendCommandOutput(
    buf,
    'Dart CLI',
    'dart',
    const ['--version'],
    onFailure: 'Dart CLI: not found on PATH',
  );
}

// Embedded build info (CI-generated)
void _appendBuildInfo(StringBuffer buf) {
  buf.writeln('Build git commit: $kBuildGitCommit');
  buf.writeln('Build git branch: $kBuildGitBranch');
  buf.writeln('Build submodules: $kBuildSubmodules');
  buf.writeln('Submodule mermaid_renderer_flutter: $kSubmoduleMermaidHash');
  buf.writeln('Submodule xterm: $kSubmoduleXtermHash');
  buf.writeln('Mermaid renderer version: $kMermaidRendererVersion');
  buf.writeln('Mermaid bundle hash: $kMermaidBundleHash');
  buf.writeln('Mermaid bundle size: $kMermaidBundleSize');
  buf.writeln('xterm version: $kXtermVersion');
  buf.writeln('flutter_svg version: $kFlutterSvgVersion');
  buf.writeln('resvg version: $kResvgVersion');
}

// resvg availability
Future<void> _appendResvgAvailability(StringBuffer buf) async {
  try {
    final result = await Process.run('which', const ['resvg']);
    if (result.exitCode == 0) {
      final path = (result.stdout as String).trim();
      buf.writeln('resvg PATH: $path');
      try {
        final ver = await Process.run(path, const ['--version']);
        if (ver.exitCode == 0) {
          buf.writeln('resvg PATH version: ${(ver.stdout as String).trim()}');
        }
      } catch (_) {}
    } else {
      buf.writeln('resvg PATH: not found');
    }
  } catch (_) {
    buf.writeln('resvg PATH: not found (which failed)');
  }
}

// Git info
Future<void> _appendGitInfo(StringBuffer buf) async {
  await _appendCommandOutput(
    buf,
    'Git HEAD',
    'git',
    const ['rev-parse', '--short', 'HEAD'],
  );
  await _appendCommandOutput(
    buf,
    'Git branch',
    'git',
    const ['rev-parse', '--abbrev-ref', 'HEAD'],
  );

  try {
    final status = await Process.run('git', const ['status', '--short']);
    if (status.exitCode == 0) {
      final out = (status.stdout as String).trim();
      if (out.isNotEmpty) {
        buf.writeln('Git dirty files:');
        for (final line in out.split('\n')) {
          buf.writeln('  $line');
        }
      } else {
        buf.writeln('Git dirty files: none');
      }
    }
  } catch (_) {}
}

// Submodule hashes
Future<void> _appendSubmoduleStatus(StringBuffer buf) async {
  try {
    final sm = await Process.run(
      'git',
      const ['submodule', 'status', '--recursive'],
    );
    if (sm.exitCode == 0) {
      final lines = (sm.stdout as String).trim().split('\n');
      if (lines.isNotEmpty && lines.first.isNotEmpty) {
        buf.writeln('Submodules:');
        for (final line in lines) {
          buf.writeln('  $line');
        }
      } else {
        buf.writeln('Submodules: none');
      }
    }
  } catch (_) {
    buf.writeln('Submodules: unable to read');
  }
}

Future<String> buildSupportCopyPayload(String memoryLog) async {
  final appLog = await AppLogger.instance.readLog();
  final path = await AppLogger.instance.logPath;
  final diagnostics = await buildSupportDiagnostics();
  return [
    'YoLoIT Support Logs',
    'Generated: ${DateTime.now().toIso8601String()}',
    'App log path: $path',
    '',
    '== System diagnostics ==',
    diagnostics,
    '',
    '== Recent support events ==',
    memoryLog,
    '',
    '== App log ==',
    appLog,
  ].join('\n');
}
