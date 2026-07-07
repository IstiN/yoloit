import 'dart:convert';
import 'dart:io' if (dart.library.html) 'package:yoloit/core/platform/io_stub.dart';

import 'package:yoloit/core/utils/text_normalize.dart' as text_normalize;

/// Resolves YoLoIT clip temp-file paths to inline text for CLI arguments.
///
/// When the user pastes long text, [SmartClipboardPasteService] stores it under
/// `…/yoloit_clip/clip_<ts>.txt` and the chat UI shows that path. Models often
/// pass the path to `--text` instead of the file contents — this helper reads
/// those files before the CLI command is built or executed.
///
/// On the web `dart:io` is replaced by a stub [File] that always reports the
/// file as missing, so clip-file resolution becomes a no-op while all text
/// normalization helpers keep working.
class CliTextArgumentResolver {
  CliTextArgumentResolver._();

  static final RegExp _clipFilePath = RegExp(r'/yoloit_clip/clip_\d+\.txt$');

  static const Set<String> textKeys = <String>{
    'text',
    'tx',
    'content',
    'code',
    'item',
    'message',
    'markdown',
    'title',
    'body',
    'label',
    'file',
    'path',
    'filepath',
    'file_path',
  };

  /// State / action keys whose string values may reference clip temp files.
  static const Set<String> jsonKeys = <String>{'json', 'j', 'tree'};

  static final RegExp _chatSessionExport = RegExp(r'^\[\d{4}-\d{2}-\d{2}T');

  static final RegExp _chatUserBlock = RegExp(
    r'\[[^\]]+\]\s+USER\s*\n(.*?)(?=\n\n\[|\Z)',
    dotAll: true,
  );

  /// Plain-text clips longer than this are not inlined unless they are chat
  /// session exports (where only the last USER block is kept).
  static const int _maxClipPlaintextBytes = 8192;

  static const Set<String> stateTextKeys = <String>{
    'text',
    'content',
    'code',
    'item',
    'message',
    'markdown',
    'label',
    'body',
  };

  /// True when [value] is a YoLoIT clip temp-file path (resolved or not).
  static bool isClipTextFilePath(String value) {
    final path = _normalizePath(value);
    return path != null && _looksLikeClipTextFile(path);
  }

  /// Returns file contents when [value] points at a YoLoIT clip `.txt` file.
  static String? resolve(String value) {
    final path = _normalizePath(value);
    if (path == null || !_looksLikeClipTextFile(path)) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final raw = file.readAsStringSync();
      return _materializeClipContent(raw);
    } catch (_) {
      return null;
    }
  }

  /// When a clip file contains a YoLoIT chat session export, keep only the
  /// latest USER message instead of dumping the whole transcript into panel text.
  static String extractUsableClipText(String raw) {
    final normalized = text_normalize.normalizeText(raw);
    final trimmed = normalized.trim();
    if (trimmed.isEmpty || !_chatSessionExport.hasMatch(trimmed)) {
      return normalized;
    }
    final userBlocks = _chatUserBlock.allMatches(trimmed);
    if (userBlocks.isEmpty) return normalized;
    final last = userBlocks.last.group(1)?.trim();
    if (last == null || last.isEmpty) return normalized;
    return last;
  }

  static String? _materializeClipContent(String raw) {
    final normalized = text_normalize.normalizeText(raw);
    final trimmed = normalized.trim();
    if (trimmed.isEmpty) return null;
    if (looksLikeTerminalOrLogDump(trimmed)) return null;
    if (!_chatSessionExport.hasMatch(trimmed) &&
        raw.length > _maxClipPlaintextBytes) {
      return null;
    }
    final extracted = extractUsableClipText(raw).trim();
    if (extracted.isEmpty) return null;
    return extracted;
  }

  static bool looksLikeTerminalOrLogDump(String text) {
    final sample = text.length > 1200 ? text.substring(0, 1200) : text;
    if (sample.contains('Launching lib/main.dart')) return true;
    if (sample.contains('flutter: [')) return true;
    if (sample.contains('Performing hot reload')) return true;
    if (sample.contains('Another exception was thrown')) return true;
    if (sample.contains('Syncing files to device')) return true;
    if (sample.contains('A Dart VM Service on')) return true;
    if (sample.contains('YoLoIT — agentic')) return true;
    return false;
  }

  /// Resolves clip-file paths inside tool argument maps (mutates [arguments]).
  static void resolveInArguments(Map<String, Object?> arguments) {
    _promoteFilePathToText(arguments);
    for (final key in jsonKeys) {
      final value = arguments[key];
      if (value is! String || value.trim().isEmpty) continue;
      arguments[key] = resolveJsonParameter(value);
    }
    for (final entry in arguments.entries.toList()) {
      final value = entry.value;
      if (value is! String) continue;
      if (!_shouldResolveKey(entry.key)) continue;
      final resolved = resolve(value);
      if (resolved != null) {
        arguments[entry.key] = resolved;
      } else if (isClipTextFilePath(value)) {
        arguments.remove(entry.key);
      } else {
        arguments[entry.key] = unwrapShellQuotedText(value);
      }
    }
  }

  /// Expands clip paths inside a JSON tool body (`do` / `board:apply` payloads).
  static String resolveJsonParameter(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return value;

    if (isClipTextFilePath(trimmed)) {
      final direct = resolve(trimmed);
      if (direct != null) {
        return jsonEncode(<String, String>{'text': direct});
      }
      return jsonEncode(<String, dynamic>{});
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return jsonEncode(resolveActionArgs(decoded));
      }
      if (decoded is String) {
        final resolved = resolve(decoded) ?? decoded;
        return jsonEncode(<String, String>{'text': resolved});
      }
    } catch (_) {
      // Not JSON — leave unchanged.
    }
    return value;
  }

  static void _promoteFilePathToText(Map<String, Object?> arguments) {
    final hasText =
        !_isMissing(arguments['text']) || !_isMissing(arguments['tx']);
    if (hasText) return;
    for (final key in const ['file', 'path', 'filepath', 'file_path']) {
      final value = arguments[key];
      if (value is String && value.trim().isNotEmpty) {
        arguments['text'] = value;
        return;
      }
    }
  }

  static bool _shouldResolveKey(String key) => textKeys.contains(key);

  static String? _normalizePath(String value) {
    var trimmed = unwrapShellQuotedText(value).trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('@')) {
      trimmed = trimmed.substring(1).trim();
    }
    if (trimmed.startsWith('file://')) {
      trimmed = Uri.parse(trimmed).toFilePath();
    }
    return trimmed;
  }

  static bool _looksLikeClipTextFile(String path) {
    if (!path.contains('/yoloit_clip/clip_')) return false;
    if (!_clipFilePath.hasMatch(path)) return false;
    return path.endsWith('.txt');
  }

  /// Resolves clip-file paths inside CLI action argument maps.
  static Map<String, dynamic> resolveActionArgs(Map<String, dynamic> args) {
    final out = Map<String, dynamic>.from(args);
    for (final entry in args.entries) {
      final value = entry.value;
      if (value is! String) continue;
      if (!stateTextKeys.contains(entry.key) && !textKeys.contains(entry.key)) {
        continue;
      }
      final resolved = resolve(value);
      if (resolved != null) {
        out[entry.key] = resolved;
        continue;
      }
      if (isClipTextFilePath(value)) {
        out.remove(entry.key);
        continue;
      }
      out[entry.key] = unwrapShellQuotedText(value);
      if (jsonKeys.contains(entry.key)) {
        out[entry.key] = resolveJsonParameter(value);
      }
    }
    return out;
  }

  /// Resolves clip-file paths inside panel state maps (panel:create / apply).
  static Map<String, dynamic> resolvePanelState(Map<String, dynamic> state) {
    final out = Map<String, dynamic>.from(state);
    for (final key in stateTextKeys) {
      final value = out[key];
      if (value is! String) continue;
      final resolved = resolve(value);
      if (resolved != null) {
        out[key] = resolved;
      } else if (isClipTextFilePath(value)) {
        out.remove(key);
      } else {
        out[key] = unwrapShellQuotedText(value);
      }
    }
    return out;
  }

  /// Some tool executors pass a rendered command string through a non-shell
  /// path, so protective quotes can arrive as literal text. Strip only one
  /// matching outer quote pair for state text fields.
  static String unwrapShellQuotedText(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 2) return value;
    final first = trimmed.codeUnitAt(0);
    final last = trimmed.codeUnitAt(trimmed.length - 1);
    final isSingleQuoted = first == 0x27 && last == 0x27;
    final isDoubleQuoted = first == 0x22 && last == 0x22;
    if (!isSingleQuoted && !isDoubleQuoted) return value;
    return trimmed.substring(1, trimmed.length - 1);
  }

  static bool _isMissing(Object? value) {
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    return false;
  }
}
