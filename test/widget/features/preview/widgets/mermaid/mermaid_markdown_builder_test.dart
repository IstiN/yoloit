import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_markdown_builder.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_renderer_widget.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_theme.dart';

void main() {
  final colors = AppColorScheme.fromAccent(Colors.deepPurple);

  MermaidBlockBuilder buildBuilder() => MermaidBlockBuilder(
    renderer: null,
    colors: colors,
    mermaidTheme: const MermaidThemeOptions(
      renderOptions: MermaidRenderOptions(backgroundColor: '#FFFFFF'),
      cacheToken: 'dark:test',
      canvasColor: Colors.white,
      scrimColor: Colors.black54,
    ),
  );

  md.Element preWithCode(String? language, String code) {
    final codeEl = md.Element('code', [md.Text(code)]);
    if (language != null) {
      codeEl.attributes['class'] = 'language-$language';
    }
    return md.Element('pre', [codeEl]);
  }

  /// Pumps a minimal app and hands the builder a real [BuildContext].
  Future<T> withContext<T>(
    WidgetTester tester,
    T Function(BuildContext context) action,
  ) async {
    late T result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            result = action(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets('returns null for an element without children', (tester) async {
    final builder = buildBuilder();
    final empty = md.Element('pre', []);

    final widget = await withContext(
      tester,
      (context) => builder.visitElementAfterWithContext(
        context,
        empty,
        null,
        null,
      ),
    );

    expect(widget, isNull);
  });

  testWidgets('returns null when no code child is present', (tester) async {
    final builder = buildBuilder();
    final noCode = md.Element('pre', [md.Text('plain text')]);

    final widget = await withContext(
      tester,
      (context) => builder.visitElementAfterWithContext(
        context,
        noCode,
        null,
        null,
      ),
    );

    expect(widget, isNull);
  });

  testWidgets('returns null for a code block without a language', (
    tester,
  ) async {
    final builder = buildBuilder();
    final pre = preWithCode(null, 'graph TD; A --> B');

    final widget = await withContext(
      tester,
      (context) => builder.visitElementAfterWithContext(context, pre, null, null),
    );

    expect(widget, isNull);
  });

  testWidgets('returns null for a non-mermaid code block', (tester) async {
    final builder = buildBuilder();
    final pre = preWithCode('dart', 'void main() {}');

    final widget = await withContext(
      tester,
      (context) => builder.visitElementAfterWithContext(context, pre, null, null),
    );

    expect(widget, isNull);
  });

  testWidgets('builds a MermaidDiagram for mermaid code blocks', (
    tester,
  ) async {
    final builder = buildBuilder();
    final pre = preWithCode('mermaid', '  graph TD; A --> B\n');

    final widget = await withContext(
      tester,
      (context) => builder.visitElementAfterWithContext(context, pre, null, null),
    );

    expect(widget, isA<MermaidDiagram>());
    final diagram = widget! as MermaidDiagram;
    // Source is trimmed before rendering and cache-keying.
    expect(diagram.code, 'graph TD; A --> B');
    expect(diagram.key, isA<ValueKey<String>>());
    expect(diagram.mermaidTheme.cacheToken, 'dark:test');
  });
}
