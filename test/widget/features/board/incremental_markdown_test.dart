import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/chat/widgets/chat_markdown_styles.dart';
import 'package:yoloit/features/board/chat/widgets/incremental_markdown_body.dart';

/// TDD tests for [IncrementalMarkdownBody]: incrementally render a streaming
/// markdown body by splitting it on the last closed paragraph boundary so the
/// finalized prefix is reused across rebuilds while only the streaming tail
/// is re-parsed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final theme = AppThemePreset.neonPurple.theme;
  final colors = theme.extension<AppColorScheme>()!;

  Widget wrap(Widget child) {
    return MaterialApp(theme: theme, home: Scaffold(body: child));
  }

  Widget incMarkdown(String data) {
    return IncrementalMarkdownBody(
      data: data,
      colors: colors,
      textColor: Colors.white,
      codeBg: Colors.black,
    );
  }

  Widget refMarkdown(String data, BuildContext context) {
    return MarkdownBody(
      data: data,
      selectable: false,
      styleSheet: chatMarkdownStyle(
        context: context,
        colors: colors,
        textColor: Colors.white,
        codeBg: Colors.black,
      ),
    );
  }

  setUp(IncrementalMarkdownBody.debugResetParseCounters);
  tearDown(IncrementalMarkdownBody.debugResetParseCounters);

  group('a. paragraph-cache hit', () {
    testWidgets(
      'intra-paragraph appends do not re-parse the prefix widget',
      (tester) async {
        final body = StringBuffer('p1\n\np2\n\np3\n\np4\n\np5');

        await tester.pumpWidget(wrap(incMarkdown(body.toString())));
        await tester.pump();

        // Capture the cached prefix MarkdownBody. We expect exactly two
        // MarkdownBody widgets: one for the finalized prefix
        // "p1\n\np2\n\np3\n\n" and one for the streaming tail "p5".
        final initialBodies =
            tester
                .widgetList<MarkdownBody>(find.byType(MarkdownBody))
                .toList();
        expect(initialBodies, hasLength(2));

        // Reset counters so the assertion below reflects only the append loop.
        IncrementalMarkdownBody.debugResetParseCounters();

        // 100 appends to the trailing paragraph (intra-paragraph tokens).
        for (var i = 0; i < 100; i++) {
          body.write('x');
          await tester.pumpWidget(wrap(incMarkdown(body.toString())));
          await tester.pump();
        }

        // The prefix parser must NOT be re-invoked for tail-only changes:
        // we crossed zero paragraph boundaries during this loop, so the
        // cached prefix widget is reused bit-for-bit.
        expect(
          IncrementalMarkdownBody.debugPrefixParseCount,
          lessThanOrEqualTo(1),
          reason:
              'prefix should be cached and reused across intra-paragraph appends',
        );

        // The trailing tail was re-parsed (bounded by tail length, not body
        // length).
        expect(IncrementalMarkdownBody.debugTailParseCount, greaterThan(0));

        // The cached prefix MarkdownBody is `identical` to the initial one
        // — its subtree identity persists across all 100 rebuilds.
        final updatedBodies =
            tester
                .widgetList<MarkdownBody>(find.byType(MarkdownBody))
                .toList();
        expect(identical(updatedBodies.first, initialBodies.first), isTrue);
      },
    );
  });

  group('b. final render equality', () {
    testWidgets(
      'rendered text matches MarkdownBody on the same body',
      (tester) async {
        const fullBody =
            'paragraph one\n\nparagraph two **with bold**\n\nparagraph three';

        await tester.pumpWidget(wrap(incMarkdown(fullBody)));
        await tester.pump();
        final incrementalText = extractRenderedText(tester);

        // Replace the tree with a single MarkdownBody on the same body for a
        // direct comparison.
        await tester.pumpWidget(
          wrap(refMarkdown(fullBody, tester.element(find.byType(Scaffold)))),
        );
        await tester.pump();
        final markdownText = extractRenderedText(tester);

        expect(incrementalText, isNotEmpty);
        expect(incrementalText, markdownText);
      },
    );
  });

  group('c. mid-stream rebuild cost', () {
    testWidgets(
      'prefix MarkdownBody instance is preserved across 50 intra-paragraph appends',
      (tester) async {
        final body = StringBuffer('p1\n\np2\n\np3\n\np4\n\np5');

        await tester.pumpWidget(wrap(incMarkdown(body.toString())));
        await tester.pump();

        final initialBodies =
            tester
                .widgetList<MarkdownBody>(find.byType(MarkdownBody))
                .toList();
        expect(initialBodies, hasLength(2));

        for (var i = 0; i < 50; i++) {
          body.write('x');
          await tester.pumpWidget(wrap(incMarkdown(body.toString())));
          await tester.pump();
        }

        final updatedBodies =
            tester
                .widgetList<MarkdownBody>(find.byType(MarkdownBody))
                .toList();
        expect(updatedBodies, hasLength(2));
        // The prefix (first MarkdownBody) is reused bit-for-bit.
        expect(identical(updatedBodies.first, initialBodies.first), isTrue);
        // The tail (second MarkdownBody) is rebuilt each frame.
        expect(identical(updatedBodies.last, initialBodies.last), isFalse);
      },
    );
  });

  group('d. markdown at boundaries', () {
    testWidgets(
      'a new paragraph introduced mid-stream moves the split but keeps the '
      'finalized prefix reusable for subsequent intra-paragraph appends',
      (tester) async {
        final body = StringBuffer('p1\n\np2');

        await tester.pumpWidget(wrap(incMarkdown(body.toString())));
        await tester.pump();

        // Cross a paragraph boundary: body grows by `\n\np3`.
        body.write('\n\np3');
        await tester.pumpWidget(wrap(incMarkdown(body.toString())));
        await tester.pump();

        final afterSplitText = extractRenderedText(tester);
        // All three paragraphs render.
        expect(afterSplitText, contains('p1'));
        expect(afterSplitText, contains('p2'));
        expect(afterSplitText, contains('p3'));

        // Now append intra-paragraph tokens to p3; the new prefix
        // ("p1\n\np2\n\n") must be reused.
        final afterSplitBodies =
            tester
                .widgetList<MarkdownBody>(find.byType(MarkdownBody))
                .toList();
        expect(afterSplitBodies, hasLength(2));
        expect(
          afterSplitBodies.first.data,
          'p1\n\np2\n\n',
          reason: 'prefix ends at the last paragraph boundary',
        );
        expect(afterSplitBodies.last.data, 'p3');

        IncrementalMarkdownBody.debugResetParseCounters();
        for (var i = 0; i < 20; i++) {
          body.write('x');
          await tester.pumpWidget(wrap(incMarkdown(body.toString())));
          await tester.pump();
        }

        // The new prefix is stable across these 20 intra-paragraph appends.
        expect(
          IncrementalMarkdownBody.debugPrefixParseCount,
          lessThanOrEqualTo(1),
        );

        // Final render still has all three paragraphs (now p3 has tokens).
        final finalText = extractRenderedText(tester);
        expect(finalText, contains('p3xxxxxxxxxxxxxxx'));
      },
    );
  });

  group('e. empty / whitespace-only appends', () {
    testWidgets('whitespace-only appends do not trigger a tail parse', (
      tester,
    ) async {
      final body = StringBuffer('p1');

      await tester.pumpWidget(wrap(incMarkdown(body.toString())));
      await tester.pump();

      IncrementalMarkdownBody.debugResetParseCounters();

      // Append a few whitespace-only chunks.
      for (final chunk in ['   ', '\n\n', '\n  \n']) {
        body.write(chunk);
        await tester.pumpWidget(wrap(incMarkdown(body.toString())));
        await tester.pump();
      }

      // The tail render is still "p1" (possibly with trailing whitespace) so
      // the parsed content does not change visually — the implementation
      // should skip redundant parses for whitespace-only deltas.
      expect(
        IncrementalMarkdownBody.debugTailParseCount,
        lessThanOrEqualTo(1),
        reason:
            'whitespace-only deltas should not trigger a fresh tail parse',
      );
    });
  });

  group('f. code-fence edge case', () {
    testWidgets(
      'an unclosed code fence keeps the streaming body as a single tail, '
      'and closing the fence lets a subsequent paragraph finalize',
      (tester) async {
        final body = StringBuffer('```dart\nfoo() {\n');

        await tester.pumpWidget(wrap(incMarkdown(body.toString())));
        await tester.pump();

        // Inside an open fence, the implementation should NOT split — the
        // whole body is a single tail. We assert this by counting: only one
        // MarkdownBody widget is in the tree.
        final openFenceBodies =
            tester
                .widgetList<MarkdownBody>(find.byType(MarkdownBody))
                .toList();
        expect(openFenceBodies, hasLength(1));
        expect(openFenceBodies.single.data, '```dart\nfoo() {\n');

        // Append more code lines; we are still in an open fence, so no split.
        body.write('  bar();\n');
        await tester.pumpWidget(wrap(incMarkdown(body.toString())));
        await tester.pump();
        final stillOpenBodies =
            tester
                .widgetList<MarkdownBody>(find.byType(MarkdownBody))
                .toList();
        expect(stillOpenBodies, hasLength(1));

        // Close the fence, then add a paragraph separator and a new
        // paragraph. The implementation should now split.
        body.write('}\n```\n\nafter-fence paragraph\n');
        await tester.pumpWidget(wrap(incMarkdown(body.toString())));
        await tester.pump();

        final closedFenceBodies =
            tester
                .widgetList<MarkdownBody>(find.byType(MarkdownBody))
                .toList();
        expect(closedFenceBodies, hasLength(2));
        // The prefix contains the closed code block plus the trailing blank
        // line run.
        expect(
          closedFenceBodies.first.data,
          '```dart\nfoo() {\n  bar();\n}\n```\n\n',
        );
        expect(closedFenceBodies.last.data, 'after-fence paragraph\n');
      },
    );
  });

  group('g. falls back to full parse', () {
    testWidgets(
      'open-code-fence body renders identically to MarkdownBody',
      (tester) async {
        const fullBody = '```dart\nfoo() {\n  bar();\n}\n```';

        await tester.pumpWidget(wrap(incMarkdown(fullBody)));
        await tester.pump();
        final incrementalText = extractRenderedText(tester);

        await tester.pumpWidget(
          wrap(refMarkdown(fullBody, tester.element(find.byType(Scaffold)))),
        );
        await tester.pump();
        final markdownText = extractRenderedText(tester);

        expect(incrementalText, isNotEmpty);
        expect(incrementalText, markdownText);
      },
    );
  });
}

/// Walks the widget tree under test and concatenates the text from every
/// [RichText] (markdown content is rendered as inline spans, not [Text]
/// widgets, so `find.byType(Text)` misses it).
String extractRenderedText(WidgetTester tester) {
  final buffer = StringBuffer();
  void walk(TextSpan? span) {
    if (span == null) return;
    if (span.text != null && span.text!.isNotEmpty) {
      buffer.write(span.text);
    }
    final children = span.children;
    if (children != null) {
      for (final c in children) {
        if (c is TextSpan) walk(c);
      }
    }
  }

  for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
    final text = rt.text;
    if (text is TextSpan) walk(text);
  }
  return buffer.toString();
}
