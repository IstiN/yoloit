import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_icon.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/services/board_icon_resolver.dart';

/// Renders the icon of a board.
///
/// Resolution order:
/// 1. Explicit override from board metadata (file / builtin preset / emoji).
/// 2. Auto-detected icon from the board's default folder (e.g. a Flutter app
///    icon).
/// 3. A generated letter avatar derived from the board name and id.
class BoardIcon extends StatelessWidget {
  const BoardIcon({super.key, required this.board, this.size = 20});

  final BoardDocument board;
  final double size;

  /// Test seam: bypasses filesystem auto-detection in widget tests.
  @visibleForTesting
  static BoardIconSpec? Function(BoardDocument board)? debugResolverOverride;

  @override
  Widget build(BuildContext context) {
    final spec =
        debugResolverOverride != null
            ? debugResolverOverride!(board)
            : kIsWeb
            ? board.icon
            : BoardIconResolver.instance.resolveForBoard(board);
    final radius = size * 0.28;
    Widget child;
    if (spec == null) {
      child = BoardIconFallback(name: board.name, seed: board.id, size: size);
    } else {
      child = switch (spec.kind) {
        BoardIconSpec.kindEmoji => _EmojiIcon(emoji: spec.value, size: size),
        BoardIconSpec.kindBuiltin => _BuiltinIcon(spec: spec, size: size),
        _ => _FileIcon(path: spec.value, size: size, board: board),
      };
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
    );
  }
}

class _EmojiIcon extends StatelessWidget {
  const _EmojiIcon({required this.emoji, required this.size});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.appColors.surfaceElevated,
      child: Center(
        child: Text(
          emoji,
          style: TextStyle(fontSize: size * 0.72, height: 1),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _BuiltinIcon extends StatelessWidget {
  const _BuiltinIcon({required this.spec, required this.size});

  final BoardIconSpec spec;
  final double size;

  @override
  Widget build(BuildContext context) {
    final preset = kBoardIconPresets[spec.value];
    if (preset == null) {
      return BoardIconFallback(name: '?', seed: spec.value, size: size);
    }
    final colors = context.appColors;
    final isSvg = preset.asset.toLowerCase().endsWith('.svg');
    return ColoredBox(
      color: colors.surfaceElevated,
      child: Padding(
        padding: EdgeInsets.all(size * 0.12),
        child:
            isSvg
                ? SvgPicture.asset(preset.asset, width: size, height: size)
                : Image.asset(
                  preset.asset,
                  width: size,
                  height: size,
                  gaplessPlayback: true,
                ),
      ),
    );
  }
}

class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.path, required this.size, required this.board});

  final String path;
  final double size;
  final BoardDocument board;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return BoardIconFallback(name: board.name, seed: board.id, size: size);
    }
    final file = File(path);
    if (!file.existsSync()) {
      return BoardIconFallback(name: board.name, seed: board.id, size: size);
    }
    if (path.toLowerCase().endsWith('.svg')) {
      return SvgPicture.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholderBuilder:
            (_) =>
                BoardIconFallback(name: board.name, seed: board.id, size: size),
      );
    }
    return Image.file(
      file,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      cacheWidth: (size * 3).round(),
      errorBuilder:
          (_, _, _) =>
              BoardIconFallback(name: board.name, seed: board.id, size: size),
    );
  }
}

/// Generated letter avatar used when a board has no icon.
///
/// Colors are derived deterministically from [seed] so every board gets a
/// stable, distinct gradient.
class BoardIconFallback extends StatelessWidget {
  const BoardIconFallback({
    super.key,
    required this.name,
    required this.seed,
    required this.size,
  });

  final String name;
  final String seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hue = (seed.hashCode.abs() % 360).toDouble();
    final begin = HSLColor.fromAHSL(1, hue, 0.45, 0.42).toColor();
    final end = HSLColor.fromAHSL(1, (hue + 32) % 360, 0.5, 0.3).toColor();
    final letter = _firstLetter(name);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [begin, end],
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: context.appColors.textPrimary.withAlpha(235),
            fontSize: size * 0.52,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }

  static String _firstLetter(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}
