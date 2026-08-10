import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/widgets/link_delete_badges.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const panelA = BoardPanelInstance(
    id: 'a',
    type: 'board.note.markdown',
    title: 'A',
    bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 80),
  );
  const panelB = BoardPanelInstance(
    id: 'b',
    type: 'board.note.markdown',
    title: 'B',
    bounds: BoardPanelBounds(x: 300, y: 0, width: 100, height: 80),
  );
  const linkAB = BoardPanelLink(id: 'l1', fromPanelId: 'a', toPanelId: 'b');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<BoardCubit> pumpBadges(
    WidgetTester tester, {
    required List<BoardPanelInstance> panels,
    required List<BoardPanelLink> links,
  }) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cubit = BoardCubit();
    addTearDown(cubit.close);
    cubit.emit(
      BoardState(
        boards: [
          BoardDocument(
            id: 'board',
            name: 'Board',
            panels: panels,
            links: links,
          ),
        ],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: SizedBox(
              width: 800,
              height: 600,
              child: Stack(
                children: [
                  LinkDeleteBadges(
                    links: links,
                    panels: panels,
                    origin: Offset.zero,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return cubit;
  }

  testWidgets('renders a hoverable badge that deletes the link on tap', (
    tester,
  ) async {
    final cubit = await pumpBadges(
      tester,
      panels: const [panelA, panelB],
      links: const [linkAB],
    );

    final badgeRegion = find.descendant(
      of: find.byType(LinkDeleteBadges),
      matching: find.byType(MouseRegion),
    );
    expect(badgeRegion, findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);

    // Hovering expands the badge and reveals the close icon.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: tester.getCenter(badgeRegion));
    await tester.pump();
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: badgeRegion,
        matching: find.byType(GestureDetector),
      ),
    );
    await tester.pumpAndSettle();

    expect(cubit.state.activeBoard!.links, isEmpty);
  });

  testWidgets('hides badges for links with hidden or missing panels', (
    tester,
  ) async {
    await pumpBadges(
      tester,
      panels: [panelA, panelB.copyWith(hidden: true)],
      links: const [
        linkAB,
        BoardPanelLink(id: 'l2', fromPanelId: 'a', toPanelId: 'ghost'),
        BoardPanelLink(id: 'l3', fromPanelId: 'ghost', toPanelId: 'a'),
      ],
    );

    expect(
      find.descendant(
        of: find.byType(LinkDeleteBadges),
        matching: find.byType(MouseRegion),
      ),
      findsNothing,
    );
  });
}
