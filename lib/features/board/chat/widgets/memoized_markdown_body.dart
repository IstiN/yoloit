import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/widgets/chat_markdown_styles.dart';

/// Caches the built [MarkdownBody] subtree keyed by (data, theme inputs).
///
/// flutter_markdown_plus re-parses the whole document inside build(), and
/// the chat panel setStates on every streaming flush (~12/s), hover and
/// scroll — without memoization every visible bubble re-parsed its full
/// markdown each time, which profiling showed as GC + text-layout spikes.
/// Returning the identical widget instance short-circuits
/// [Element.updateChild] and skips the rebuild (and re-parse) entirely.
///
/// The [colors] identity is part of the key: `context.appColors` resolves to
/// a stable [AppColorScheme] instance while the theme is unchanged, and any
/// theme change replaces it, so cached bubbles restyle exactly when the
/// theme actually changes.
class MemoizedMarkdownBody extends StatefulWidget {
  const MemoizedMarkdownBody({
    super.key,
    required this.data,
    required this.colors,
    required this.textColor,
    required this.codeBg,
    this.onTapLink,
  });

  final String data;
  final AppColorScheme colors;
  final Color textColor;
  final Color codeBg;
  final void Function(String text, String? href, String title)? onTapLink;

  @override
  State<MemoizedMarkdownBody> createState() => _MemoizedMarkdownBodyState();
}

class _MemoizedMarkdownBodyState extends State<MemoizedMarkdownBody> {
  Widget? _cached;
  String? _cachedData;
  AppColorScheme? _cachedColors;
  Color? _cachedTextColor;
  Color? _cachedCodeBg;

  @override
  Widget build(BuildContext context) {
    if (_cached == null ||
        _cachedData != widget.data ||
        !identical(_cachedColors, widget.colors) ||
        _cachedTextColor != widget.textColor ||
        _cachedCodeBg != widget.codeBg) {
      _cached = MarkdownBody(
        data: widget.data,
        selectable: false,
        onTapLink: widget.onTapLink,
        styleSheet: chatMarkdownStyle(
          context: context,
          colors: widget.colors,
          textColor: widget.textColor,
          codeBg: widget.codeBg,
        ),
      );
      _cachedData = widget.data;
      _cachedColors = widget.colors;
      _cachedTextColor = widget.textColor;
      _cachedCodeBg = widget.codeBg;
    }
    return _cached!;
  }
}
