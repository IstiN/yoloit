import 'dart:convert' show LineSplitter;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/widgets/chat_markdown_styles.dart';

/// Incrementally renders a streaming markdown body.
///
/// A streamed AI response emits N body updates (one per token or chunk) and
/// every update with the previous [MemoizedMarkdownBody] implementation
/// triggered a full markdown re-parse of the growing document — O(N^2) total
/// parse work. After throttling (~80ms) the cost is still
/// O((N / chunks_per_sec) * body_size), which profiling showed as the
/// dominant CPU hog during long responses.
///
/// This widget splits the body at the last *closed* paragraph boundary
/// (a `\n\n` run outside any fenced code block), treats everything before
/// that boundary as a stable, memoized [MarkdownBody] subtree, and re-parses
/// only the trailing tail on each update. The prefix grows only when the
/// stream crosses a paragraph boundary (typically a handful of times per
/// response), so the per-update cost is bounded by the tail length rather
/// than the full document.
///
/// Code fences (` ``` ` and `~~~` at line start) defer the split: while a
/// fence is open, the entire body is treated as the tail so we never split
/// mid-block and re-parse the open fence incorrectly.
class IncrementalMarkdownBody extends StatefulWidget {
  const IncrementalMarkdownBody({
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

  // ---------------------------------------------------------------------------
  // Test instrumentation — incremented inside [_build] whenever a new
  // [MarkdownBody] is constructed for the prefix or the tail. Tests reset
  // these between rebuilds to assert that the prefix is reused across
  // intra-paragraph appends.
  // ---------------------------------------------------------------------------

  @visibleForTesting
  static int debugPrefixParseCount = 0;

  @visibleForTesting
  static int debugTailParseCount = 0;

  @visibleForTesting
  static void debugResetParseCounters() {
    debugPrefixParseCount = 0;
    debugTailParseCount = 0;
  }

  @override
  State<IncrementalMarkdownBody> createState() =>
      _IncrementalMarkdownBodyState();
}

class _IncrementalMarkdownBodyState extends State<IncrementalMarkdownBody> {
  // The prefix widget is cached on (prefix string, theme inputs). Returning
  // the identical MarkdownBody instance from build() short-circuits
  // Element.updateChild and skips the re-parse.
  String? _cachedPrefix;
  Widget? _cachedPrefixWidget;
  AppColorScheme? _cachedColors;
  Color? _cachedTextColor;
  Color? _cachedCodeBg;

  // The trailing-tail MarkdownBody is rebuilt each frame by design; we cache
  // the previous widget to detect whitespace-only deltas and avoid pointless
  // re-parses in that case.
  String? _cachedTailData;
  Widget? _cachedTailWidget;
  AppColorScheme? _cachedTailColors;
  Color? _cachedTailTextColor;
  Color? _cachedTailCodeBg;

  @override
  Widget build(BuildContext context) {
    final split = _splitMarkdown(widget.data);
    final prefix = split.prefix;
    final tail = split.tail;

    final prefixWidget = _buildPrefixWidget(context, prefix);
    final tailWidget = _buildTailWidget(context, tail);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?prefixWidget,
        ?tailWidget,
      ],
    );
  }

  Widget? _buildPrefixWidget(BuildContext context, String prefix) {
    if (prefix.isEmpty) {
      _cachedPrefixWidget = null;
      _cachedPrefix = '';
      return null;
    }
    if (_cachedPrefixWidget != null &&
        _cachedPrefix == prefix &&
        identical(_cachedColors, widget.colors) &&
        _cachedTextColor == widget.textColor &&
        _cachedCodeBg == widget.codeBg) {
      return _cachedPrefixWidget!;
    }
    IncrementalMarkdownBody.debugPrefixParseCount++;
    _cachedPrefix = prefix;
    _cachedColors = widget.colors;
    _cachedTextColor = widget.textColor;
    _cachedCodeBg = widget.codeBg;
    final styleSheet = chatMarkdownStyle(
      context: context,
      colors: widget.colors,
      textColor: widget.textColor,
      codeBg: widget.codeBg,
    );
    _cachedPrefixWidget = RepaintBoundary(
      child: MarkdownBody(
        data: prefix,
        selectable: false,
        onTapLink: widget.onTapLink,
        styleSheet: styleSheet,
      ),
    );
    return _cachedPrefixWidget!;
  }

  Widget? _buildTailWidget(BuildContext context, String tail) {
    if (tail.isEmpty) {
      _cachedTailWidget = null;
      _cachedTailData = '';
      return null;
    }
    // Whitespace-only deltas do not change the visible parse output, so we
    // can reuse the previous tail widget and skip a parse.
    final visibleUnchanged =
        _cachedTailWidget != null &&
        _visibleContentEquals(_cachedTailData ?? '', tail) &&
        identical(_cachedTailColors, widget.colors) &&
        _cachedTailTextColor == widget.textColor &&
        _cachedTailCodeBg == widget.codeBg;
    if (visibleUnchanged) {
      return _cachedTailWidget!;
    }
    IncrementalMarkdownBody.debugTailParseCount++;
    _cachedTailData = tail;
    _cachedTailColors = widget.colors;
    _cachedTailTextColor = widget.textColor;
    _cachedTailCodeBg = widget.codeBg;
    final styleSheet = chatMarkdownStyle(
      context: context,
      colors: widget.colors,
      textColor: widget.textColor,
      codeBg: widget.codeBg,
    );
    _cachedTailWidget = RepaintBoundary(
      child: MarkdownBody(
        data: tail,
        selectable: false,
        onTapLink: widget.onTapLink,
        styleSheet: styleSheet,
      ),
    );
    return _cachedTailWidget!;
  }

  // Two strings parse to the same visible content iff their non-whitespace,
  // non-newline runs are identical. Markdown treats line breaks and runs of
  // spaces as either soft breaks or ignored whitespace, so trimming each
  // line and dropping blank lines is a faithful proxy for "did the
  // MarkdownBody output change?".
  static bool _visibleContentEquals(String a, String b) {
    final aLines =
        const LineSplitter()
            .convert(a)
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
    final bLines =
        const LineSplitter()
            .convert(b)
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
    if (aLines.length != bLines.length) return false;
    for (var i = 0; i < aLines.length; i++) {
      if (aLines[i] != bLines[i]) return false;
    }
    return true;
  }
}

/// Pure split function used by [_IncrementalMarkdownBodyState.build] and
/// exposed at top level so it can be tested independently.
///
/// Returns the [prefix] (everything up to and including the last blank-line
/// run that separates two non-blank blocks outside any code fence) and the
/// [tail] (everything after, which is re-parsed each update).
({String prefix, String tail}) _splitMarkdown(String body) {
  if (body.isEmpty) return (prefix: '', tail: '');

  final lines = const LineSplitter().convert(body);
  var inFence = false;
  final blankLineIndices = <int>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmedLeft = line.trimLeft();
    // A fence opens or closes on a line whose first non-whitespace run is
    // ``` or ~~~. This matches what markdown renderers consume and avoids
    // splitting inside an open fence.
    if (trimmedLeft.startsWith('```') || trimmedLeft.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (!inFence && line.trim().isEmpty) {
      blankLineIndices.add(i);
    }
  }

  // If the body ends inside an open fence, refuse to split: the next
  // append could close the fence (or append more code) and any split we
  // made here would be wrong.
  if (inFence) {
    return (prefix: '', tail: body);
  }

  // Find the last blank-line run that is followed by non-blank content.
  // That run is a stable paragraph boundary: the prefix up to it is
  // finalized and will never change semantically as the body grows.
  var lastSplitLineIdx = -1;
  for (var i = blankLineIndices.length - 1; i >= 0; i--) {
    final idx = blankLineIndices[i];
    var hasContentAfter = false;
    for (var j = idx + 1; j < lines.length; j++) {
      if (lines[j].trim().isNotEmpty) {
        hasContentAfter = true;
        break;
      }
    }
    if (hasContentAfter) {
      lastSplitLineIdx = idx;
      break;
    }
  }

  if (lastSplitLineIdx < 0) {
    // No blank-line run separates two non-blank blocks: everything is one
    // paragraph (or all blanks), so we render the full body as the tail.
    return (prefix: '', tail: body);
  }

  // Extend through the trailing blank lines of the run so the split lands
  // *after* all the separators, leaving the tail with no leading blanks.
  var endOfRun = lastSplitLineIdx;
  while (endOfRun + 1 < lines.length &&
      lines[endOfRun + 1].trim().isEmpty) {
    endOfRun++;
  }

  // Compute the character index where the trailing content starts. Lines
  // are joined by '\n', so each line of length L contributes L + 1 bytes
  // (the +1 is the separator), except for the very last line in the body
  // which has no trailing separator. By construction we stop *before* the
  // last line in the body (endOfRun < lines.length - 1 when there is a
  // tail), so the +1 is correct here.
  var charIdx = 0;
  for (var i = 0; i <= endOfRun; i++) {
    charIdx += lines[i].length + 1;
  }

  final prefix = body.substring(0, charIdx);
  final tail = body.substring(charIdx);
  return (prefix: prefix, tail: tail);
}
