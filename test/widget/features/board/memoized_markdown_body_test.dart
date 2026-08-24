import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/chat/widgets/memoized_markdown_body.dart';

/// The memoized markdown body exists to skip re-parsing unchanged markdown:
/// flutter_markdown_plus parses the whole document inside build(), and chat
/// setStates fire on every streaming flush, so returning the identical child
/// instance for unchanged data is what saves the work.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final theme = AppThemePreset.neonPurple.theme;
  final colors = theme.extension<AppColorScheme>()!;

  Widget wrap(Widget child) {
    return MaterialApp(theme: theme, home: Scaffold(body: child));
  }

  MarkdownBody markdownOf(WidgetTester tester) {
    return tester.widget<MarkdownBody>(find.byType(MarkdownBody));
  }

  testWidgets('renders the markdown content', (tester) async {
    await tester.pumpWidget(
      wrap(
        MemoizedMarkdownBody(
          data: 'hello **world**',
          colors: colors,
          textColor: Colors.white,
          codeBg: Colors.black,
        ),
      ),
    );
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(markdownOf(tester).data, 'hello **world**');
  });

  testWidgets('reuses the identical child instance when data is unchanged', (
    tester,
  ) async {
    Widget build(String data) => wrap(
      MemoizedMarkdownBody(
        data: data,
        colors: colors,
        textColor: Colors.white,
        codeBg: Colors.black,
      ),
    );

    await tester.pumpWidget(build('same'));
    final first = markdownOf(tester);

    // Simulate a streaming-flush setState that rebuilds the tree without
    // changing this bubble's content.
    await tester.pumpWidget(build('same'));
    expect(identical(markdownOf(tester), first), isTrue);

    await tester.pumpWidget(build('same + new token'));
    final updated = markdownOf(tester);
    expect(identical(updated, first), isFalse);
    expect(updated.data, 'same + new token');
  });
}
