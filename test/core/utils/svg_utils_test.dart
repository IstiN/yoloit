import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/utils/svg_utils.dart';

void main() {
  group('parseSvgAspectRatio', () {
    test('parses viewBox with spaces', () {
      const svg = '<svg viewBox="0 0 800 600"></svg>';
      expect(parseSvgAspectRatio(svg), 800 / 600);
    });

    test('parses viewBox with commas', () {
      const svg = '<svg viewBox="0,0,1600,900"></svg>';
      expect(parseSvgAspectRatio(svg), 1600 / 900);
    });

    test('parses viewBox with mixed separators', () {
      const svg = '<svg viewBox="0 0,400 300"></svg>';
      expect(parseSvgAspectRatio(svg), 400 / 300);
    });

    test('falls back to 16/9 when viewBox missing', () {
      const svg = '<svg width="100" height="100"></svg>';
      expect(parseSvgAspectRatio(svg), 16 / 9);
    });

    test('falls back when viewBox has wrong part count', () {
      const svg = '<svg viewBox="0 0 100"></svg>';
      expect(parseSvgAspectRatio(svg), 16 / 9);
    });

    test('falls back when width or height is zero', () {
      const svg = '<svg viewBox="0 0 0 100"></svg>';
      expect(parseSvgAspectRatio(svg), 16 / 9);
    });

    test('falls back when width or height is not numeric', () {
      const svg = '<svg viewBox="0 0 abc 100"></svg>';
      expect(parseSvgAspectRatio(svg), 16 / 9);
    });
  });
}
