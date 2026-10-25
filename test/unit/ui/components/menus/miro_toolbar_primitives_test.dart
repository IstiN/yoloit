import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/ui/components/menus/miro_toolbar_primitives.dart';

void main() {
  group('miro toolbar shape primitives', () {
    const labels = <String, String>{
      'circle': 'Oval',
      'diamond': 'Rhombus',
      'triangle': 'Triangle',
      'hexagon': 'Hexagon',
      'frame': 'Frame',
      'rectangle': 'Rectangle',
    };

    const icons = <String, IconData>{
      'circle': Icons.circle_outlined,
      'diamond': Icons.diamond_outlined,
      'triangle': Icons.change_history_rounded,
      'hexagon': Icons.hexagon_outlined,
      'frame': Icons.crop_square_rounded,
      'rectangle': Icons.rectangle_outlined,
    };

    test('returns labels and icons for every supported shape', () {
      for (final shape in labels.keys) {
        expect(miroToolbarShapeLabel(shape), labels[shape]);
        expect(miroToolbarShapeIcon(shape), icons[shape]);
      }
    });

    test('unknown shapes use rectangle defaults', () {
      expect(miroToolbarShapeLabel('unknown'), 'Rectangle');
      expect(miroToolbarShapeLabel(''), 'Rectangle');
      expect(miroToolbarShapeIcon('unknown'), Icons.rectangle_outlined);
      expect(miroToolbarShapeIcon(''), Icons.rectangle_outlined);
    });
  });
}
