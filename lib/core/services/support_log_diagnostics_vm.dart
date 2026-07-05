import 'dart:io';

import 'package:yoloit/core/services/app_logger.dart';
import 'package:yoloit/core/services/build_info.dart';

Future<String> buildSupportDiagnostics() async {
  final buf = StringBuffer();
  buf.writeln(
    'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
  );
  buf.writeln('Dart: ${Platform.version}');
  buf.writeln('Resolved executable: ${Platform.resolvedExecutable}');
  buf.writeln('PATH: ${Platform.environment['PATH'] ?? '(empty)'}');

  // Architecture (system + binary)
  try {
    final result = await Process.run('uname', const ['-m']);
    if (result.exitCode == 0) {
      buf.writeln('System architecture: ${(result.stdout as String).trim()}');
    }
  } catch (_) {
    buf.writeln('System architecture: unknown');
  }

  try {
    final resolved = Platform.resolvedExecutable;
    final result = await Process.run('file', [resolved]);
    if (result.exitCode == 0) {
      buf.writeln('Binary file info: ${(result.stdout as String).trim()}');
    }
  } catch (_) {
    buf.writeln('Binary file info: unavailable');
  }

  try {
    final resolved = Platform.resolvedExecutable;
    final result = await Process.run('lipo', ['-info', resolved]);
    if (result.exitCode == 0) {
      buf.writeln('Binary architectures: ${(result.stdout as String).trim()}');
    }
  } catch (_) {
    buf.writeln('Binary architectures: unavailable');
  }

  // Flutter / Dart toolchain versions
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

  try {
    final result = await Process.run('dart', const ['--version']);
    if (result.exitCode == 0) {
      buf.writeln('Dart CLI: ${(result.stdout as String).trim()}');
    }
  } catch (_) {
    buf.writeln('Dart CLI: not found on PATH');
  }

  // Embedded build info (CI-generated)
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

  // resvg availability
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

  // Git info
  try {
    final rev = await Process.run('git', const ['rev-parse', '--short', 'HEAD']);
    if (rev.exitCode == 0) {
      buf.writeln('Git HEAD: ${(rev.stdout as String).trim()}');
    }
  } catch (_) {}

  try {
    final branch = await Process.run(
      'git',
      const ['rev-parse', '--abbrev-ref', 'HEAD'],
    );
    if (branch.exitCode == 0) {
      buf.writeln('Git branch: ${(branch.stdout as String).trim()}');
    }
  } catch (_) {}

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

  // Submodule hashes
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

  return buf.toString();
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
