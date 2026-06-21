import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/services/board_operation_applier.dart';
import 'package:yoloit/features/templates/data/template_loader.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

void main() {
  group('Built-in templates', () {
    test('all templates in yoloit/templates load without errors', () async {
      final root = Directory('yoloit/templates');
      expect(root.existsSync(), isTrue);

      final source = TemplateSource(
        id: 'builtins',
        type: TemplateSourceType.local,
        localPath: root.path,
      );
      const loader = LocalTemplateLoader();
      final templates = await loader.load(source);

      final expectedIds = <String>{
        'flutter-project',
        'home-notes',
        'weekly-review',
        'trip-planner',
        'habit-tracker',
        'brainstorm',
      };
      final loadedIds = templates.map((t) => t.id).toSet();
      expect(loadedIds, containsAll(expectedIds));

      for (final template in templates) {
        expect(template.id, isNotEmpty);
        expect(template.name, isNotEmpty);
        expect(template.operations, isNotEmpty);
      }
    });

    test('new chart/table templates produce valid panels', () async {
      final root = Directory('yoloit/templates');
      final source = TemplateSource(
        id: 'builtins',
        type: TemplateSourceType.local,
        localPath: root.path,
      );
      const loader = LocalTemplateLoader();
      final templates = await loader.load(source);
      const applier = BoardOperationApplier();

      final targetIds = <String>{
        'personal-expenses',
        'sales-dashboard',
        'fitness-progress',
      };
      for (final template in templates.where((t) => targetIds.contains(t.id))) {
        final board = BoardDocument(id: 'b-${template.id}', name: template.name);
        final result = applier.buildDocument(
          board,
          template.operations.map((op) => op.toJson()).toList(),
        );
        expect(result.panels, isNotEmpty,
            reason: '${template.id} should create panels');

        final tablePanels = result.panels.where((p) => p.type == 'board.table');
        final chartPanels = result.panels.where((p) => p.type == 'board.chart');
        expect(tablePanels, isNotEmpty,
            reason: '${template.id} should contain a table panel');
        expect(chartPanels, isNotEmpty,
            reason: '${template.id} should contain a chart panel');
      }
    });
  });
}
