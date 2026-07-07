import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';

const _cliAgentGuidanceAsset = 'assets/prompts/cli_agent_guidance.md';

class CliGuidanceService {
  CliGuidanceService._();
  static final instance = CliGuidanceService._();

  String? _cachedHelp;
  String? _cachedMermaidShort;

  void clearCache() {
    _cachedHelp = null;
    _cachedMermaidShort = null;
  }

  /// Public access to the CLI help output for preview purposes.
  Future<String?> fetchHelp() async {
    _cachedHelp ??= await _fetchHelpFormat('short');
    return _cachedHelp;
  }

  /// Compact command tree generated from the live CLI registry.
  Future<String?> fetchMermaidShort() async {
    _cachedMermaidShort ??= await _fetchHelpFormat('mermaid_short');
    return _cachedMermaidShort;
  }

  Future<String> prependGuidance(
    String message, {
    ChatRuntimeContext? runtimeContext,
  }) async {
    final base = await rootBundle.loadString(_cliAgentGuidanceAsset);
    final help = _cachedHelp ?? await fetchHelp();
    _cachedHelp = help;

    final boardId = runtimeContext?.boardId?.trim();
    final boardName = runtimeContext?.boardName?.trim();
    final panelId = runtimeContext?.panelId?.trim();
    final panelTitle = runtimeContext?.panelTitle?.trim();
    final hasBoardContext =
        (boardId != null && boardId.isNotEmpty) ||
        (boardName != null && boardName.isNotEmpty) ||
        (panelId != null && panelId.isNotEmpty) ||
        (panelTitle != null && panelTitle.isNotEmpty);

    final parts = <String>[base.trim()];
    if (help != null && help.isNotEmpty) {
      parts.add('Available `yoloit` commands:\n```\n$help\n```');
    }
    if (hasBoardContext) {
      parts.add(
        'Current YoLoIT UI context:\n'
        '- Current board id: ${boardId ?? 'unknown'}\n'
        '- Current board name: ${boardName ?? 'unknown'}\n'
        '- Current chat panel id: ${panelId ?? 'unknown'}\n'
        '- Current chat panel title: ${panelTitle ?? 'unknown'}\n\n'
        'Prefer this board by default when running `yoloit` commands unless the user explicitly asks for another board.',
      );
    }
    parts.add('User request:\n$message');
    return parts.join('\n\n');
  }

  Future<String> prependBoardReminder(
    String message, {
    ChatRuntimeContext? runtimeContext,
  }) async {
    final boardName = runtimeContext?.boardName?.trim();
    final boardId = runtimeContext?.boardId?.trim();
    final boardRef =
        boardName != null && boardName.isNotEmpty
            ? boardName
            : boardId != null && boardId.isNotEmpty
            ? boardId
            : null;
    final parts = <String>[
      'YoLoIT board reminder:',
      '- For board/canvas/panel changes, use `yoloit` CLI commands. Do not edit project files unless the user explicitly asks to change repo files.',
      '- If the target panel/type/action is unclear, run `yoloit panels`, `yoloit panel:types`, or `yoloit panel:help` first.',
      '- For shape/sticky/frame requests, prefer `yoloit shape:create`, `yoloit sticky:create`, `yoloit frame:create`, or `yoloit board:apply`.',
    ];
    if (boardRef != null) {
      parts.add('- Current board: `$boardRef`.');
    }
    parts.add('User request:\n$message');
    return parts.join('\n');
  }

  Future<String?> _fetchHelpFormat(String format) async {
    if (kIsWeb) return null;
    final bin = _resolveYoloitBin();
    if (bin == null) return null;
    try {
      final cliPort = Platform.environment['YOLOIT_CLI_PORT'];
      final result = await Process.run(
        bin,
        <String>['help', '--format', format],
        runInShell: false,
        environment: cliPort != null ? <String, String>{'YOLOIT_CLI_PORT': cliPort} : null,
      ).timeout(const Duration(seconds: 10));
      if (result.exitCode == 0) {
        final out = result.stdout.toString().trim();
        return out.isNotEmpty ? out : null;
      }
    } catch (_) {}
    return null;
  }

  String? _resolveYoloitBin() {
    if (kIsWeb) return null;
    final explicit = Platform.environment['YOLOIT_CLI_PATH'];
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit.trim();
    }

    final installed = CliServer.installedCliExecutable;
    if (installed != null) return installed.path;

    return _findSourceTreeCli();
  }

  String? _findSourceTreeCli() {
    final roots = <String?>[
      Directory.current.path,
      Platform.environment['PWD'],
      Platform.environment['YOLOIT_PROJECT_ROOT'],
      Platform.environment['PROJECT_DIR'],
      p.dirname(Platform.resolvedExecutable),
    ];
    final seen = <String>{};
    for (final raw in roots) {
      if (raw == null || raw.trim().isEmpty) continue;
      var dir = Directory(p.normalize(p.absolute(raw.trim())));
      for (var depth = 0; depth < 10; depth++) {
        if (!seen.add(dir.path)) break;
        for (final candidate in <File>[
          File(p.join(dir.path, 'tools', 'yoloit')),
          File(p.join(dir.path, 'yoloit', 'tools', 'yoloit')),
        ]) {
          if (candidate.existsSync()) return candidate.path;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return null;
  }
}
