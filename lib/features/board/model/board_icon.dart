import 'package:equatable/equatable.dart';

/// Describes a board icon chosen by the user.
///
/// Stored in `BoardDocument.metadata['icon']`. When absent, the UI tries to
/// auto-detect an icon from the board's default folder (e.g. a Flutter app
/// icon) and falls back to a generated letter avatar.
class BoardIconSpec extends Equatable {
  const BoardIconSpec({required this.kind, required this.value});

  /// Absolute path to a local image file (PNG/JPG/...).
  static const String kindFile = 'file';

  /// Bundled asset preset (see [kBoardIconPresets]).
  static const String kindBuiltin = 'builtin';

  /// A single emoji character.
  static const String kindEmoji = 'emoji';

  final String kind;
  final String value;

  Map<String, dynamic> toJson() => {'kind': kind, 'value': value};

  static BoardIconSpec? fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) return null;
    final kind = json['kind'] as String? ?? '';
    final value = json['value'] as String? ?? '';
    if (kind.isEmpty || value.isEmpty) return null;
    if (kind != kindFile && kind != kindBuiltin && kind != kindEmoji) {
      return null;
    }
    return BoardIconSpec(kind: kind, value: value);
  }

  /// Parses a CLI/LLM shorthand into a spec.
  ///
  /// Supported forms:
  /// - `auto`, `clear`, `none`, `default`, `-` → `null` (reset to auto-detect)
  /// - `emoji:<char>` → emoji icon
  /// - `builtin:<name>` → bundled preset (see [kBoardIconPresets])
  /// - `file:<path>` or any path ending in an image extension → local file
  /// - anything else that looks like a single emoji → emoji icon
  ///
  /// Throws [FormatException] when the value cannot be understood.
  static BoardIconSpec? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty ||
        trimmed == 'auto' ||
        trimmed == 'clear' ||
        trimmed == 'none' ||
        trimmed == 'default' ||
        trimmed == '-') {
      return null;
    }
    const emojiPrefix = 'emoji:';
    const builtinPrefix = 'builtin:';
    const filePrefix = 'file:';
    if (trimmed.startsWith(emojiPrefix)) {
      final emoji = trimmed.substring(emojiPrefix.length).trim();
      if (emoji.isEmpty) return null;
      return BoardIconSpec(kind: kindEmoji, value: emoji);
    }
    if (trimmed.startsWith(builtinPrefix)) {
      final name = trimmed.substring(builtinPrefix.length).trim();
      if (!kBoardIconPresets.containsKey(name)) {
        throw FormatException(
          'Unknown builtin icon "$name". '
          'Available: ${kBoardIconPresets.keys.join(', ')}',
        );
      }
      return BoardIconSpec(kind: kindBuiltin, value: name);
    }
    if (trimmed.startsWith(filePrefix)) {
      final path = trimmed.substring(filePrefix.length).trim();
      if (path.isEmpty) {
        throw const FormatException('Empty file icon path');
      }
      return BoardIconSpec(kind: kindFile, value: path);
    }
    if (_looksLikeImagePath(trimmed)) {
      return BoardIconSpec(kind: kindFile, value: trimmed);
    }
    if (_looksLikeEmoji(trimmed)) {
      return BoardIconSpec(kind: kindEmoji, value: trimmed);
    }
    throw FormatException(
      'Cannot parse board icon "$raw". Use auto, emoji:<char>, '
      'builtin:<name>, or a path to an image file.',
    );
  }

  static bool _looksLikeImagePath(String value) {
    final lower = value.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.svg');
  }

  static bool _looksLikeEmoji(String value) {
    // A short string without path separators is assumed to be an emoji.
    if (value.length > 8) return false;
    if (value.contains('/') || value.contains('\\') || value.contains('.')) {
      return false;
    }
    return value.runes.any((rune) => rune > 0x7F);
  }

  /// Human readable description used in CLI output.
  String describe() {
    return switch (kind) {
      kindEmoji => 'emoji:$value',
      kindBuiltin => 'builtin:$value',
      _ => value,
    };
  }

  @override
  List<Object?> get props => [kind, value];
}

/// A bundled icon preset selectable for a board.
class BoardIconPreset extends Equatable {
  const BoardIconPreset({
    required this.key,
    required this.asset,
    required this.label,
  });

  final String key;

  /// Asset path under `assets/` (SVG or raster).
  final String asset;
  final String label;

  @override
  List<Object?> get props => [key, asset, label];
}

/// Bundled presets available for board icons.
const Map<String, BoardIconPreset> kBoardIconPresets = {
  'yoloit': BoardIconPreset(
    key: 'yoloit',
    asset: 'assets/images/yoloit_mark.svg',
    label: 'YoLoIT',
  ),
  'yoloit_logo': BoardIconPreset(
    key: 'yoloit_logo',
    asset: 'assets/images/yoloit_logo.svg',
    label: 'YoLoIT logo',
  ),
  'yolo_assistant': BoardIconPreset(
    key: 'yolo_assistant',
    asset: 'assets/icon/yolo_assistant.svg',
    label: 'YoLo assistant',
  ),
  'copilot': BoardIconPreset(
    key: 'copilot',
    asset: 'assets/images/copilot_mark.svg',
    label: 'Copilot',
  ),
  'voice': BoardIconPreset(
    key: 'voice',
    asset: 'assets/images/yolo_voice_badge.svg',
    label: 'YoLo voice',
  ),
};
