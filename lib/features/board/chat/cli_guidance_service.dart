import 'dart:io';

import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';

class CliGuidanceService {
  CliGuidanceService._();
  static final instance = CliGuidanceService._();

  static final _guidanceDocRelativePaths = <String>[
    'docs${Platform.pathSeparator}cli-agent-guidance.md',
    'docs${Platform.pathSeparator}cli-mermaid.md',
  ];

  String? _cachedGuidanceMarkdown;

  /// Call this when the inject-CLI-help setting changes so the next chat
  /// session picks up the new value.
  void clearCache() => _cachedGuidanceMarkdown = null;

  Future<String> prependGuidance(
    String message, {
    ChatRuntimeContext? runtimeContext,
  }) async {
    final guidance = await _loadGuidanceMarkdown();
    final boardId = runtimeContext?.boardId?.trim();
    final boardName = runtimeContext?.boardName?.trim();
    final panelId = runtimeContext?.panelId?.trim();
    final panelTitle = runtimeContext?.panelTitle?.trim();
    final hasBoardContext =
        (boardId != null && boardId.isNotEmpty) ||
        (boardName != null && boardName.isNotEmpty) ||
        (panelId != null && panelId.isNotEmpty) ||
        (panelTitle != null && panelTitle.isNotEmpty);
    final boardContext =
        hasBoardContext
            ? '''
Current YoLoIT UI context:
- Current board id: ${boardId ?? 'unknown'}
- Current board name: ${boardName ?? 'unknown'}
- Current chat panel id: ${panelId ?? 'unknown'}
- Current chat panel title: ${panelTitle ?? 'unknown'}

Prefer this board by default when running `yoloit` commands unless the user explicitly asks for another board.
'''
            : '';
    if (boardContext.isEmpty) {
      return '$guidance\n\nUser request:\n$message';
    }
    return '$guidance\n\n$boardContext\nUser request:\n$message';
  }

  Future<String> _loadGuidanceMarkdown() async {
    final inject = await SessionPrefs.isInjectCliHelpEnabled();
    final cached = _cachedGuidanceMarkdown;
    if (!inject) {
      // Return minimal guidance without CLI help tree
      return '''
You are running inside YoLoIT chat.
Prefer YoLoIT CLI commands over ad-hoc shell mutations.
Use `yoloit help` to see available commands.
''';
    }
    if (cached != null && cached.isNotEmpty) return cached;
    final helpTree = await _loadYoloitHelpTree();
    if (helpTree != null && helpTree.isNotEmpty) {
      _cachedGuidanceMarkdown = '''
You are running inside YoLoIT chat.
Prefer YoLoIT CLI commands over ad-hoc shell mutations.

`yoloit --help` (compact tree):
```text
$helpTree
```

Use `yoloit panel:help "<board>" "<panel>"` for panel action params/examples.
For multi-step board changes, prefer `yoloit board:apply` with YAML operations.
''';
      return _cachedGuidanceMarkdown!;
    }
    final files = _resolveGuidanceDocFiles();
    final sections = <String>[];
    for (final file in files) {
      if (!await file.exists()) continue;
      final markdown = (await file.readAsString()).trim();
      if (markdown.isEmpty) continue;
      sections.add(markdown);
    }
    if (sections.isNotEmpty) {
      _cachedGuidanceMarkdown = sections.join('\n\n');
      return _cachedGuidanceMarkdown!;
    }
    const fallback = '''
You are running inside YoLoIT chat.
Prefer YoLoIT CLI for long-running processes:
- Use board.run_configs panel actions (list/add/run/input/output/stop).
- Avoid foreground long-lived commands in the chat shell.
''';
    _cachedGuidanceMarkdown = fallback.trim();
    return _cachedGuidanceMarkdown!;
  }

  Future<String?> _loadYoloitHelpTree() async {
    Future<ProcessResult?> runHelp(String executable, List<String> args) async {
      try {
        return await Process.run(
          executable,
          args,
        ).timeout(const Duration(seconds: 4));
      } catch (_) {
        return null;
      }
    }

    final yoloitBin = _resolveYoloitBin();
    final result =
        yoloitBin != null
            ? await runHelp(yoloitBin, const ['help', '--format', 'short'])
            : await runHelp('yoloit', const ['help', '--format', 'short']);
    if (result == null || result.exitCode != 0) return null;
    final stdout = result.stdout.toString().trim();
    if (stdout.isEmpty) return null;
    return stdout;
  }

  List<File> _resolveGuidanceDocFiles() {
    final roots = <Directory>[];
    final files = <File>[];
    final seenPaths = <String>{};

    void addRoot(String path) {
      if (path.isEmpty) return;
      final dir = Directory(path).absolute;
      if (roots.any((existing) => existing.path == dir.path)) return;
      roots.add(dir);
    }

    addRoot(Directory.current.path);
    addRoot(File(Platform.resolvedExecutable).parent.path);

    for (final root in roots) {
      var current = root;
      for (var depth = 0; depth < 8; depth++) {
        for (final relativePath in _guidanceDocRelativePaths) {
          final candidate = File(
            '${current.path}${Platform.pathSeparator}$relativePath',
          );
          if (!candidate.existsSync()) continue;
          if (seenPaths.add(candidate.path)) {
            files.add(candidate);
          }
        }
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }
    return files;
  }

  String? _resolveYoloitBin() {
    // Check the installed location first — written by CliServer on startup.
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      final installed = File('$home/.config/yoloit/yoloit');
      if (installed.existsSync()) return installed.path;
    }

    final roots = <Directory>[];
    void addRoot(String path) {
      if (path.isEmpty) return;
      final dir = Directory(path).absolute;
      if (roots.any((existing) => existing.path == dir.path)) return;
      roots.add(dir);
    }

    addRoot(Directory.current.path);
    addRoot(File(Platform.resolvedExecutable).parent.path);

    for (final root in roots) {
      var current = root;
      for (var depth = 0; depth < 8; depth++) {
        final candidate = File(
          '${current.path}${Platform.pathSeparator}tools${Platform.pathSeparator}yoloit',
        );
        if (candidate.existsSync()) return candidate.path;
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }
    return null;
  }
}

