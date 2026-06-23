import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/table/model/table_models.dart';

void main() {
  group('TableRow.fromJson', () {
    test('parses top-level cell values', () {
      final row = TableRow.fromJson({
        'id': 'r1',
        'category': 'Продукты',
        'amount': 3500,
      });
      expect(row.id, 'r1');
      expect(row.cells['category'], 'Продукты');
      expect(row.cells['amount'], 3500);
    });

    test('flattens nested cells map', () {
      final row = TableRow.fromJson({
        'id': 'r1',
        'cells': {
          'category': 'Продукты',
          'amount': 3500,
        },
      });
      expect(row.id, 'r1');
      expect(row.cells['category'], 'Продукты');
      expect(row.cells['amount'], 3500);
      expect(row.cells.containsKey('cells'), isFalse);
    });

    test('generates id when missing', () {
      final row = TableRow.fromJson({
        'category': 'Транспорт',
        'amount': 1200,
      });
      expect(row.id, isNotEmpty);
      expect(row.cells['category'], 'Транспорт');
    });
  });
}
