import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yoloit/features/mindmap/sidebar/show_hide_sidebar.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';

const _darkBg = Color(0xFF0D1117);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 500,
  double height = 420,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    BlocProvider<ReviewCubit>(
      create: (_) => ReviewCubit(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: _darkBg),
        home: Scaffold(
          body: SizedBox(width: width, height: height, child: child),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _golden(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(Scaffold),
    matchesGoldenFile('goldens/$name.png'),
  );
}

ShowHideSidebarData _buildSampleData() {
  return ShowHideSidebarData(
    workspaces: [
      ShowHideSidebarNode(
        id: 'ws:alpha',
        type: 'workspace',
        label: 'Alpha Workspace',
        hidden: false,
        children: [
          ShowHideSidebarNode(
            id: 'agent:alpha',
            type: 'agent',
            label: 'Copilot Session',
            hidden: false,
            children: [
              ShowHideSidebarNode(
                id: 'repo:alpha',
                type: 'repo',
                label: 'alpha-repo (main)',
                hidden: false,
              ),
            ],
          ),
          ShowHideSidebarNode(
            id: 'run:alpha',
            type: 'run',
            label: 'flutter test',
            hidden: true,
          ),
        ],
      ),
      ShowHideSidebarNode(
        id: 'ws:beta',
        type: 'workspace',
        label: 'Beta Project',
        hidden: false,
        children: [
          ShowHideSidebarNode(
            id: 'agent:beta',
            type: 'agent',
            label: 'Claude Session',
            hidden: false,
          ),
        ],
      ),
    ],
    orphans: [],
    hiddenCount: 2,
  );
}

void main() {
  group('Golden — MindMapShowHideSidebar', () {
    testWidgets('populated sidebar with workspaces and hidden nodes', (tester) async {
      await _pump(
        tester,
        MindMapShowHideSidebar(
          data: _buildSampleData(),
          onToggleHide: (_) {},
          onToggleGroup: (_) {},
          onFocusNode: (_) {},
          onShowAll: () {},
          onCreateWorkspace: () {},
        ),
      );
      await _golden(tester, 'sidebar_populated');
    });

    testWidgets('empty sidebar (no workspaces)', (tester) async {
      await _pump(
        tester,
        MindMapShowHideSidebar(
          data: const ShowHideSidebarData(
            workspaces: [],
            orphans: [],
            hiddenCount: 0,
          ),
          onToggleHide: (_) {},
          onToggleGroup: (_) {},
          onCreateWorkspace: () {},
        ),
        height: 200,
      );
      await _golden(tester, 'sidebar_empty');
    });

    testWidgets('sidebar with orphan nodes', (tester) async {
      await _pump(
        tester,
        MindMapShowHideSidebar(
          data: ShowHideSidebarData(
            workspaces: [],
            orphans: [
              const ShowHideSidebarNode(
                id: 'orphan:1',
                type: 'repo',
                label: 'detached-repo',
                hidden: false,
              ),
              const ShowHideSidebarNode(
                id: 'orphan:2',
                type: 'run',
                label: 'ci-run',
                hidden: true,
              ),
            ],
            hiddenCount: 1,
          ),
          onToggleHide: (_) {},
          onToggleGroup: (_) {},
        ),
        height: 240,
      );
      await _golden(tester, 'sidebar_orphans');
    });

    testWidgets('sidebar with all nodes hidden', (tester) async {
      await _pump(
        tester,
        MindMapShowHideSidebar(
          data: ShowHideSidebarData(
            workspaces: [
              ShowHideSidebarNode(
                id: 'ws:hidden',
                type: 'workspace',
                label: 'Hidden Workspace',
                hidden: true,
                children: [
                  const ShowHideSidebarNode(
                    id: 'agent:hidden',
                    type: 'agent',
                    label: 'Hidden Agent',
                    hidden: true,
                  ),
                ],
              ),
            ],
            orphans: [],
            hiddenCount: 3,
          ),
          onToggleHide: (_) {},
          onToggleGroup: (_) {},
          onShowAll: () {},
        ),
      );
      await _golden(tester, 'sidebar_all_hidden');
    });
  });
}
