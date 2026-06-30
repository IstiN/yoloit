import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/utils/color_utils.dart';

void main() {
  test('parseColor accepts JetBrains ICLS hex without hash', () {
    expect(parseColor('2b2b2b'), const Color(0xFF2B2B2B));
    expect(parseColor('cc7832'), const Color(0xFFCC7832));
  });

  test('parseColor accepts hash-prefixed hex', () {
    expect(parseColor('#2b2b2b'), const Color(0xFF2B2B2B));
  });
}
