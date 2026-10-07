import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/ui/app_svg_icons.dart';

void main() {
  testWidgets('SvgIcon renders a Lucide glyph at the requested size',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SvgIcon(AppSvgIcons.folderPlus, size: 14, color: Colors.white),
        ),
      ),
    );

    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(picture.width, 14);
    expect(picture.height, 14);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('SvgIcon falls back to the icon theme color', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: IconTheme(
            data: IconThemeData(color: Colors.green),
            child: SvgIcon(AppSvgIcons.trash),
          ),
        ),
      ),
    );

    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('every bundled icon parses as valid SVG', (tester) async {
    const icons = [
      AppSvgIcons.folderPlus,
      AppSvgIcons.filePlus,
      AppSvgIcons.pencil,
      AppSvgIcons.copy,
      AppSvgIcons.clipboardCopy,
      AppSvgIcons.folderOpen,
      AppSvgIcons.appWindow,
      AppSvgIcons.trash,
      AppSvgIcons.refresh,
    ];
    for (final icon in icons) {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SvgIcon(icon))),
      );
      expect(find.byType(SvgPicture), findsOneWidget,
          reason: 'icon should render: $icon');
      await tester.pumpWidget(const SizedBox());
    }
  });
}
