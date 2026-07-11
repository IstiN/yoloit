import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/tools/board_tool.dart';
import 'package:yoloit/features/board/ui/board_settings_panels.dart';
import 'package:yoloit/features/board/ui/board_tools_panel.dart';

void main() {
  group('BoardToolsPanel', () {
    const board = BoardDocument(
      id: 'board-1',
      name: 'Test Board',
      viewport: BoardViewport(scale: 1),
    );

    Widget buildPanel({
      bool visible = true,
      BoardToolId activeTool = BoardToolId.select,
      DrawSettings drawSettings = const DrawSettings(),
      ConnectSettings connectSettings = const ConnectSettings(),
      bool historyPanelVisible = false,
      ValueChanged<BoardToolId>? onToolChanged,
      ValueChanged<DrawSettings>? onDrawSettingsChanged,
      ValueChanged<ConnectSettings>? onConnectSettingsChanged,
      VoidCallback? onToggle,
      VoidCallback? onShowHistory,
      VoidCallback? onUndo,
      VoidCallback? onRedo,
      VoidCallback? onAddNote,
      VoidCallback? onAddChat,
      VoidCallback? onAddTerminal,
      ValueChanged<String>? onAddGeneric,
    }) {
      return MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: BoardToolsPanel(
              board: board,
              platform: 'macos',
              visible: visible,
              activeTool: activeTool,
              drawSettings: drawSettings,
              connectSettings: connectSettings,
              onToolChanged: onToolChanged ?? (_) {},
              onDrawSettingsChanged: onDrawSettingsChanged ?? (_) {},
              onConnectSettingsChanged: onConnectSettingsChanged ?? (_) {},
              historyPanelVisible: historyPanelVisible,
              onToggle: onToggle ?? () {},
              onShowHistory: onShowHistory ?? () {},
              onUndo: onUndo,
              onRedo: onRedo,
              onAddNote: onAddNote,
              onAddChat: onAddChat,
              onAddTerminal: onAddTerminal,
              onAddGeneric: onAddGeneric,
            ),
          ),
        ),
      );
    }

    testWidgets('renders toggle button', (tester) async {
      await tester.pumpWidget(buildPanel());
      expect(find.byTooltip('Hide tools'), findsOneWidget);
    });

    testWidgets('toggle button shows correct tooltip when hidden', (tester) async {
      await tester.pumpWidget(buildPanel(visible: false));
      expect(find.byTooltip('Show tools'), findsOneWidget);
    });

    testWidgets('tapping toggle calls onToggle', (tester) async {
      var toggled = false;
      await tester.pumpWidget(
        buildPanel(onToggle: () => toggled = true),
      );
      await tester.tap(find.byTooltip('Hide tools'));
      expect(toggled, isTrue);
    });

    testWidgets('renders tool buttons when visible', (tester) async {
      await tester.pumpWidget(buildPanel());
      expect(find.byTooltip('Select (V)'), findsOneWidget);
      expect(find.byTooltip('Draw (D)'), findsOneWidget);
      expect(find.byTooltip('Connect (C)'), findsOneWidget);
    });

    testWidgets('tapping tool button calls onToolChanged', (tester) async {
      BoardToolId? changed;
      await tester.pumpWidget(
        buildPanel(onToolChanged: (v) => changed = v),
      );
      await tester.tap(find.byTooltip('Draw (D)'));
      expect(changed, BoardToolId.draw);
    });

    testWidgets('shows draw settings when draw tool is active', (tester) async {
      await tester.pumpWidget(
        buildPanel(activeTool: BoardToolId.draw),
      );
      expect(find.byType(DrawSettingsPanel), findsOneWidget);
      expect(find.byType(ConnectSettingsPanel), findsNothing);
    });

    testWidgets('shows connect settings when connect tool is active', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildPanel(activeTool: BoardToolId.connect),
      );
      expect(find.byType(ConnectSettingsPanel), findsOneWidget);
      expect(find.byType(DrawSettingsPanel), findsNothing);
    });

    testWidgets('renders undo/redo/history buttons', (tester) async {
      await tester.pumpWidget(buildPanel());
      expect(find.byTooltip('Undo latest panel change'), findsOneWidget);
      expect(find.byTooltip('Redo'), findsOneWidget);
      expect(find.byTooltip('Show board history'), findsOneWidget);
    });

    testWidgets('history button tooltip changes when visible', (tester) async {
      await tester.pumpWidget(
        buildPanel(historyPanelVisible: true),
      );
      expect(find.byTooltip('Hide board history'), findsOneWidget);
    });

    testWidgets('undo button calls onUndo', (tester) async {
      var called = false;
      await tester.pumpWidget(
        buildPanel(onUndo: () => called = true),
      );
      await tester.tap(find.byTooltip('Undo latest panel change'));
      expect(called, isTrue);
    });

    testWidgets('redo button calls onRedo', (tester) async {
      var called = false;
      await tester.pumpWidget(
        buildPanel(onRedo: () => called = true),
      );
      await tester.tap(find.byTooltip('Redo'));
      expect(called, isTrue);
    });

    testWidgets('renders add panel category buttons with handlers', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildPanel(
          onAddNote: () {},
          onAddChat: () {},
          onAddTerminal: () {},
          onAddGeneric: (_) {},
        ),
      );
      expect(find.byTooltip('Miro basics'), findsOneWidget);
      expect(find.byTooltip('AI and terminal'), findsOneWidget);
      expect(find.byTooltip('Files and web'), findsOneWidget);
      expect(find.byTooltip('Planning'), findsOneWidget);
      expect(find.byTooltip('Advanced'), findsOneWidget);
    });

    testWidgets('renders disabled add panel category buttons without handlers', (
      tester,
    ) async {
      await tester.pumpWidget(buildPanel());
      expect(
        find.byTooltip('Miro basics unavailable on this board'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('AI and terminal unavailable on this board'),
        findsOneWidget,
      );
    });

    testWidgets('advanced category offers Audio Recorder on macOS', (
      tester,
    ) async {
      await tester.pumpWidget(buildPanel(onAddGeneric: (_) {}));
      await tester.tap(find.byTooltip('Advanced'));
      await tester.pumpAndSettle();

      expect(find.text('Audio Recorder'), findsOneWidget);
    });

    testWidgets('hovering a different category switches the submenu', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildPanel(onAddNote: () {}, onAddGeneric: (_) {}),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.byTooltip('Planning')));
      await tester.pumpAndSettle();
      expect(find.text('Kanban Board'), findsOneWidget);

      await gesture.moveTo(tester.getCenter(find.byTooltip('Miro basics')));
      await tester.pumpAndSettle();
      expect(find.text('Kanban Board'), findsNothing);
      expect(find.text('Markdown Note'), findsOneWidget);
    });

    testWidgets('leaving the toolbar closes the submenu', (tester) async {
      await tester.pumpWidget(
        buildPanel(onAddNote: () {}, onAddGeneric: (_) {}),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.byTooltip('Miro basics')));
      await tester.pumpAndSettle();
      expect(find.text('Markdown Note'), findsOneWidget);

      // Move to empty space far from the toolbar and its submenu.
      await gesture.moveTo(const Offset(400, 400));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('Markdown Note'), findsNothing);
    });

    group('on web', () {
      Widget buildWebPanel({
        bool visible = true,
        BoardToolId activeTool = BoardToolId.select,
        DrawSettings drawSettings = const DrawSettings(),
        ConnectSettings connectSettings = const ConnectSettings(),
        bool historyPanelVisible = false,
        VoidCallback? onAddNote,
        VoidCallback? onAddChat,
        VoidCallback? onAddTerminal,
        ValueChanged<String>? onAddGeneric,
      }) {
        return MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: BoardToolsPanel(
                board: board,
                platform: 'web',
                visible: visible,
                activeTool: activeTool,
                drawSettings: drawSettings,
                connectSettings: connectSettings,
                onToolChanged: (_) {},
                onDrawSettingsChanged: (_) {},
                onConnectSettingsChanged: (_) {},
                historyPanelVisible: historyPanelVisible,
                onToggle: () {},
                onShowHistory: () {},
                onUndo: null,
                onRedo: null,
                onAddNote: onAddNote,
                onAddChat: onAddChat,
                onAddTerminal: onAddTerminal,
                onAddGeneric: onAddGeneric,
              ),
            ),
          ),
        );
      }

      testWidgets('basics category offers markdown, sticky, and shape', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildWebPanel(onAddNote: () {}, onAddGeneric: (_) {}),
        );
        await tester.tap(find.byTooltip('Miro basics'));
        await tester.pumpAndSettle();

        expect(find.text('Markdown Note'), findsOneWidget);
        expect(find.text('Sticky Note'), findsOneWidget);
        expect(find.text('Shape / Frame'), findsOneWidget);
      });

      testWidgets('planning category offers kanban, checklist, timer, calendar, table, chart', (
        tester,
      ) async {
        await tester.pumpWidget(buildWebPanel(onAddGeneric: (_) {}));
        await tester.tap(find.byTooltip('Planning'));
        await tester.pumpAndSettle();

        expect(find.text('Kanban Board'), findsOneWidget);
        expect(find.text('Checklist'), findsOneWidget);
        expect(find.text('Timer'), findsOneWidget);
        expect(find.text('Calendar'), findsOneWidget);
        expect(find.text('Table'), findsOneWidget);
        expect(find.text('Chart'), findsOneWidget);
      });

      testWidgets('AI category offers AI Chat but not terminal or YoLo assistant', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildWebPanel(onAddChat: () {}, onAddGeneric: (_) {}),
        );
        await tester.tap(find.byTooltip('AI and terminal'));
        await tester.pumpAndSettle();

        expect(find.text('AI Chat'), findsOneWidget);
        expect(find.text('Terminal'), findsNothing);
        expect(find.text('YoLo Assistant'), findsNothing);
      });

      testWidgets('files category offers webpage but not file-backed panels', (
        tester,
      ) async {
        await tester.pumpWidget(buildWebPanel(onAddGeneric: (_) {}));
        await tester.tap(find.byTooltip('Files and web'));
        await tester.pumpAndSettle();

        expect(find.text('Webpage'), findsOneWidget);
        expect(find.text('File Tree'), findsNothing);
        expect(find.text('Files'), findsNothing);
        expect(find.text('File Preview'), findsNothing);
      });

      testWidgets('advanced category offers web-safe plugins only', (
        tester,
      ) async {
        await tester.pumpWidget(buildWebPanel(onAddGeneric: (_) {}));
        await tester.tap(find.byTooltip('Advanced'));
        await tester.pumpAndSettle();

        expect(find.text('Custom Widget'), findsOneWidget);
        expect(find.text('UI View'), findsOneWidget);
        expect(find.text('Setup Guide'), findsNothing);
        expect(find.text('Playlist'), findsNothing);
      });
    });
  });

  group('MiroLeftToolbarButton', () {
    Widget buildButton({
      bool active = false,
      VoidCallback? onTap,
    }) {
      return MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: MiroLeftToolbarButton(
            icon: Icons.undo,
            tooltip: 'Undo',
            color: Colors.grey,
            active: active,
            onTap: onTap,
          ),
        ),
      );
    }

    testWidgets('renders icon', (tester) async {
      await tester.pumpWidget(buildButton());
      expect(find.byIcon(Icons.undo), findsOneWidget);
    });

    testWidgets('displays tooltip', (tester) async {
      await tester.pumpWidget(buildButton());
      expect(find.byTooltip('Undo'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildButton(onTap: () => tapped = true));
      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('shows active border and background', (tester) async {
      await tester.pumpWidget(buildButton(active: true));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(decoration.color, isNot(Colors.transparent));
    });

    testWidgets('disabled when onTap is null', (tester) async {
      await tester.pumpWidget(buildButton());
      final inkWell = tester.widget<InkWell>(find.byType(InkWell));
      expect(inkWell.onTap, isNull);
    });
  });

  group('PanelCatalogCategoryButton', () {
    const board = BoardDocument(
      id: 'board-1',
      name: 'Test Board',
      viewport: BoardViewport(scale: 1),
    );

    Widget buildButton({
      required PanelCatalogCategory category,
      VoidCallback? onAddNote,
      VoidCallback? onAddChat,
      VoidCallback? onAddTerminal,
      ValueChanged<String>? onAddGeneric,
    }) {
      return MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: PanelCatalogCategoryButton(
            board: board,
            platform: 'macos',
            category: category,
            icon: Icons.category,
            tooltip: 'Category',
            color: Colors.grey,
            onAddNote: onAddNote,
            onAddChat: onAddChat,
            onAddTerminal: onAddTerminal,
            onAddGeneric: onAddGeneric,
          ),
        ),
      );
    }

    testWidgets('renders icon', (tester) async {
      await tester.pumpWidget(
        buildButton(category: PanelCatalogCategory.basics),
      );
      expect(find.byIcon(Icons.category), findsOneWidget);
    });

    testWidgets('shows tooltip with items available', (tester) async {
      await tester.pumpWidget(
        buildButton(
          category: PanelCatalogCategory.basics,
          onAddNote: () {},
          onAddGeneric: (_) {},
        ),
      );
      expect(find.byTooltip('Category'), findsOneWidget);
    });

    testWidgets('disabled tooltip when no handlers provided', (tester) async {
      await tester.pumpWidget(
        buildButton(
          category: PanelCatalogCategory.basics,
          onAddGeneric: null,
          onAddNote: null,
        ),
      );
      expect(
        find.byTooltip('Category unavailable on this board'),
        findsOneWidget,
      );
    });

    testWidgets('tapping opens menu with items', (tester) async {
      await tester.pumpWidget(
        buildButton(
          category: PanelCatalogCategory.basics,
          onAddNote: () {},
          onAddGeneric: (_) {},
        ),
      );
      await tester.tap(find.byIcon(Icons.category));
      await tester.pumpAndSettle();

      expect(find.text('Markdown Note'), findsOneWidget);
      expect(find.text('Sticky Note'), findsOneWidget);
      expect(find.text('Shape / Frame'), findsOneWidget);
    });

    testWidgets('menu item tap calls onAddNote', (tester) async {
      var called = false;
      await tester.pumpWidget(
        buildButton(
          category: PanelCatalogCategory.basics,
          onAddNote: () => called = true,
          onAddGeneric: (_) {},
        ),
      );
      await tester.tap(find.byIcon(Icons.category));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Markdown Note'));
      await tester.pumpAndSettle();
      expect(called, isTrue);
    });

    testWidgets('hovering opens the submenu without a tap', (tester) async {
      await tester.pumpWidget(
        buildButton(
          category: PanelCatalogCategory.basics,
          onAddNote: () {},
          onAddGeneric: (_) {},
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byIcon(Icons.category)));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('Markdown Note'), findsOneWidget);
      expect(find.text('Sticky Note'), findsOneWidget);
    });
  });
}
