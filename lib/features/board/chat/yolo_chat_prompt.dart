import 'dart:io';

import 'package:flutter/services.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_locator.dart';

const yoloChatSystemPromptAsset = 'assets/prompts/yolo_chat_system_prompt.md';

/// Loads the base system prompt from the MD asset file (cached — the asset
/// is immutable for the process lifetime).
Future<String> _loadBasePrompt() async {
  return _cachedBasePrompt ??= (await rootBundle.loadString(
    yoloChatSystemPromptAsset,
  )).trim();
}

String? _cachedBasePrompt;

/// Short-help cache TTL: CLI help output only changes when the CLI binary
/// changes, but keep a short window so in-app CLI updates are picked up.
const _shortHelpTtl = Duration(seconds: 30);
bool _hasCachedShortHelp = false;
String? _cachedShortHelp;
DateTime? _cachedShortHelpAt;
Future<String?>? _shortHelpInFlight;
String? _cachedComposedPrompt;

/// Resolves the yoloit CLI executable path (same logic as YoloitCliToolExecutor).
String? _resolveYoloitExecutable() {
  final explicit = Platform.environment['YOLOIT_CLI_PATH'];
  if (explicit != null && explicit.trim().isNotEmpty) return explicit.trim();
  return findYoloitCliScript();
}

/// Fetches the short CLI help via `yoloit help --format short`.
/// Returns null if the binary is not found or the call fails.
Future<String?> _loadShortHelp() async {
  try {
    final exe = _resolveYoloitExecutable();
    if (exe == null) return null;
    final cliPort = Platform.environment['YOLOIT_CLI_PORT'];
    final result = await Process.run(
      exe,
      ['help', '--format', 'short'],
      runInShell: false,
      environment: cliPort != null ? {'YOLOIT_CLI_PORT': cliPort} : null,
    ).timeout(const Duration(seconds: 10));
    if (result.exitCode == 0) {
      final out = result.stdout.toString().trim();
      return out.isNotEmpty ? out : null;
    }
  } catch (_) {}
  return null;
}

/// Loads the full system prompt:
///   1. Base prompt from MD asset
///   2. Short CLI help appended dynamically (cached briefly — spawning the
///      `yoloit help` subprocess per chat message showed up as a CPU hotspot)
Future<String> loadYoloChatSystemPrompt() async {
  final base = await _loadBasePrompt();
  final help = await _loadShortHelpCached();
  if (help == null || help.isEmpty) return base;
  return _cachedComposedPrompt ??=
      '$base\n\n## Available YoLoIT CLI Commands\n\n$help';
}

Future<String?> _loadShortHelpCached() {
  final cachedAt = _cachedShortHelpAt;
  if (_hasCachedShortHelp &&
      cachedAt != null &&
      DateTime.now().difference(cachedAt) < _shortHelpTtl) {
    return Future<String?>.value(_cachedShortHelp);
  }
  return _shortHelpInFlight ??= _loadShortHelp().then((help) {
    _hasCachedShortHelp = true;
    _cachedShortHelp = help;
    _cachedShortHelpAt = DateTime.now();
    _cachedComposedPrompt = null;
    _shortHelpInFlight = null;
    return help;
  });
}
