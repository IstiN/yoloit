import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/kanban_plugin.dart';

/// Replicates the board-level Focus interceptor from board_view.dart /
/// board_view_sections.dart: meta/Ctrl+C,V,D are "board shortcuts" unless
/// focus sits inside an editable text.
class _BoardInterceptor extends StatelessWidget {
  const _BoardInterceptor({required this.child});

  final Widget child;

  static bool get _isFocusInEditableText {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorStateOfType<EditableTextState>() != null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (_isFocusInEditableText) return KeyEventResult.ignored;
      final isMeta = HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;
      if (isMeta && event.logicalKey == LogicalKeyboardKey.keyC) {
        debugPrint('BOARD INTERCEPTOR: swallowed meta+C as copyPanels');
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _handleKeyEvent,
      child: child,
    );
  }
}

void main() {
  testWidgets('kanban inline add field: select + Cmd+C copies text', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    var clipboardText = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.getData':
          return <String, dynamic>{'text': clipboardText};
        case 'Clipboard.setData':
          clipboardText = (call.arguments as Map?)?['text'] as String? ?? '';
          return null;
        case 'Clipboard.hasStrings':
          return <String, dynamic>{'value': clipboardText.isNotEmpty};
        default:
          return null;
      }
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    const plugin = KanbanPlugin();
    var state = <String, dynamic>{
      'columns': ['Todo'],
      'cards': <Map<String, dynamic>>[],
    };

    BoardPanelInstance panelForState() => BoardPanelInstance(
      id: 'kanban',
      type: KanbanPlugin.kTypeId,
      title: 'Kanban',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 640, height: 420),
      state: state,
    );

    late StateSetter refresh;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 420,
            child: _BoardInterceptor(
              child: StatefulBuilder(
                builder: (context, setState) {
                  refresh = setState;
                  return plugin.buildContent(
                    context,
                    panelForState(),
                    BoardPanelRenderContext(
                      isSelected: true,
                      onFocus: () {},
                      onDelete: () {},
                      onUpdateState: (nextState) {
                        state = nextState;
                        refresh(() {});
                      },
                      onShowEditor: () {},
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    // Open the inline add field.
    await tester.tap(find.byTooltip('Add card'));
    await tester.pump();
    final field = find.widgetWithText(TextField, 'Card title…');
    expect(field, findsOneWidget);

    await tester.enterText(field, 'quick card title');
    await tester.pump();

    // Focus the field (like a real click) and select all.
    await tester.tap(field);
    await tester.pump();
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection =
        TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    await tester.pump();

    final primary = FocusManager.instance.primaryFocus;
    debugPrint('PRIMARY FOCUS: ${primary?.debugLabel} '
        'contextWidget=${primary?.context?.widget.runtimeType}');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pump();

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    debugPrint('CLIPBOARD: "${data?.text}"');
    expect(data?.text, 'quick card title');

    // ── Phase 2: Cmd+V inside the inline field must paste INTO the field,
    // not be swallowed by the panel-level paste-to-column handler. ──
    controller.clear();
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pump();
    debugPrint('FIELD TEXT AFTER CMD+V: "${controller.text}"');
    expect(controller.text, 'quick card title');

    debugDefaultTargetPlatformOverride = null;
  });
}
