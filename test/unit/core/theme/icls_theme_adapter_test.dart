import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:yoloit/core/theme/icls_theme_adapter.dart';

void main() {
  const sampleIcls = '''
<scheme name="YoLo Test" parent_scheme="Darcula">
  <colors>
    <option name="CONSOLE_BACKGROUND_KEY" value="2b2b2b"/>
  </colors>
  <attributes>
    <option name="TEXT">
      <value>
        <option name="FOREGROUND" value="bbbbbb"/>
        <option name="BACKGROUND" value="2b2b2b"/>
      </value>
    </option>
    <option name="DEFAULT_KEYWORD">
      <value>
        <option name="FOREGROUND" value="cc7832"/>
      </value>
    </option>
  </attributes>
</scheme>
''';

  test('parses scheme name and dark background', () {
    final parsed = IclsThemeAdapter.parse(sampleIcls);
    expect(parsed.name, 'YoLo Test');
    expect(parsed.scheme.background, const Color(0xFF2B2B2B));
  });

  test('maps keyword foreground to accent', () {
    final parsed = IclsThemeAdapter.parse(sampleIcls);
    expect(parsed.scheme.primary, const Color(0xFFCC7832));
  });

  test('rejects malformed xml', () {
    expect(
      () => IclsThemeAdapter.parse('<scheme><unclosed>'),
      throwsA(isA<XmlException>()),
    );
  });
}
