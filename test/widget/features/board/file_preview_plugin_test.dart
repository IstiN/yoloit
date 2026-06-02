import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/file_preview_plugin.dart';

void main() {
  const plugin = FilePreviewPlugin();

  testWidgets('shows clear error for missing image path', (tester) async {
    final missingPath =
        '${Directory.systemTemp.path}/yoloit_missing_preview_image.png';

    await tester.pumpWidget(_previewHarness(plugin, missingPath));
    await tester.pump();

    expect(find.text('File not found'), findsOneWidget);
    expect(find.text(missingPath), findsOneWidget);
  });

  test('highlights JSON keys, strings, numbers, booleans, and nulls', () {
    final colors = AppColorScheme.fromAccent(Colors.deepPurple);
    final spans = filePreviewCodeSyntaxSpans(
      '"name": "Teammate", "active": true, "score": 42, "meta": null',
      extension: 'json',
      colors: colors,
    );

    final styled = spans.where((span) => span.style?.color != null).toList();
    expect(
      styled.map((span) => span.text),
      containsAll(['"name"', '"Teammate"', 'true', '42', 'null']),
    );
    expect(
      styled.map((span) => span.style!.color).toSet().length,
      greaterThanOrEqualTo(4),
    );
  });
}

Widget _previewHarness(FilePreviewPlugin plugin, String path) {
  final panel = BoardPanelInstance(
    id: 'preview',
    type: FilePreviewPlugin.kTypeId,
    title: 'Preview',
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 480, height: 360),
    state: {'path': path, 'title': path.split(Platform.pathSeparator).last},
  );

  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 480,
        height: 360,
        child: Builder(
          builder:
              (context) => plugin.buildContent(
                context,
                panel,
                BoardPanelRenderContext(
                  isSelected: false,
                  onFocus: () {},
                  onDelete: () {},
                  onUpdateState: (_) {},
                  onShowEditor: () {},
                ),
              ),
        ),
      ),
    ),
  );
}
