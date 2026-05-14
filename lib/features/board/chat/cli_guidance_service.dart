import 'dart:io';

import 'package:yoloit/features/board/chat/chat_provider.dart';

class CliGuidanceService {
  CliGuidanceService._();
  static final instance = CliGuidanceService._();

  static final _guidanceDocRelativePaths = <String>[
    'docs${Platform.pathSeparator}cli-agent-guidance.md',
    'docs${Platform.pathSeparator}cli-mermaid.md',
  ];

  String? _cachedGuidanceMarkdown;

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
    final cached = _cachedGuidanceMarkdown;
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
            ? await runHelp(yoloitBin, const ['--help'])
            : await runHelp('yoloit', const ['--help']);
    if (result == null || result.exitCode != 0) return null;
    final stdout = result.stdout.toString().trim();
    if (stdout.isEmpty) return null;
    return _compactHelpAsTree(stdout);
  }

  String _compactHelpAsTree(String helpText) {
    final lines = helpText.split('\n');
    final out = StringBuffer('yoloit');
    String? section;
    final sectionCommands = <String, List<_HelpItem>>{};
    final seen = <String>{};

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.isEmpty) continue;
      final upper = line.toUpperCase();
      final isSectionTitle =
          line == upper &&
          RegExp(r'^[A-Z ]+$').hasMatch(line) &&
          !line.startsWith('USAGE');
      if (isSectionTitle) {
        final title = line.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        section = title;
        sectionCommands.putIfAbsent(section, () => <_HelpItem>[]);
        seen.clear();
        continue;
      }
      if (section == null || section == 'examples') continue;
      if (!rawLine.startsWith('  ')) continue;
      final trimmed = rawLine.trimLeft();
      final parts = trimmed.split(RegExp(r'\s{2,}'));
      final command = parts.first.trim();
      if (command.isEmpty || command == 'yoloit <command> [args...]') continue;
      if (!seen.add(command)) continue;
      final desc = _compactDescription(
        parts.length > 1 ? parts.sublist(1).join(' ').trim() : null,
      );
      sectionCommands[section]!.add(
        _HelpItem(command: command, description: desc),
      );
    }

    for (final entry in sectionCommands.entries) {
      final title = entry.key;
      final commands = entry.value;
      if (commands.isEmpty) continue;

      out.writeln();
      out.writeln('  $title:');

      final plain = <_HelpItem>[];
      final grouped = <String, List<_HelpItem>>{};
      final groupOrder = <String>[];

      for (final item in commands) {
        final command = item.command;
        final head = command.split(' ').first;
        final colon = head.indexOf(':');
        if (colon <= 0) {
          plain.add(item);
          continue;
        }
        final prefix = head.substring(0, colon);
        final suffixHead = head.substring(colon + 1);
        final args =
            command.length > head.length ? command.substring(head.length) : '';
        grouped.putIfAbsent(prefix, () {
          groupOrder.add(prefix);
          return <_HelpItem>[];
        });
        grouped[prefix]!.add(
          _HelpItem(command: '$suffixHead$args', description: item.description),
        );
      }

      for (final p in plain) {
        out.writeln(_formatHelpLine('    ', p.command, p.description));
      }
      for (final group in groupOrder) {
        out.writeln('    $group:');
        for (final suffix in grouped[group]!) {
          out.writeln(
            _formatHelpLine('      ', suffix.command, suffix.description),
          );
        }
      }
    }
    return out.toString().trim();
  }

  String _formatHelpLine(String indent, String command, String? description) {
    if (description == null || description.isEmpty) return '$indent$command';
    return '$indent$command — $description';
  }

  String? _compactDescription(String? description) {
    if (description == null) return null;
    var value = description.trim();
    if (value.isEmpty) return null;
    value = value.replaceAll(RegExp(r'\s+'), ' ');
    value = value.replaceAll(
      RegExp(r'\(e\.g\.[^)]+\)', caseSensitive: false),
      '',
    );
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.isEmpty ? null : value;
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

class _HelpItem {
  const _HelpItem({required this.command, this.description});

  final String command;
  final String? description;
}
