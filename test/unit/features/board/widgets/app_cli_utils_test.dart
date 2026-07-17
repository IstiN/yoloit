import 'package:flutter_test/flutter_test.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:yoloit/features/board/widgets/app_cli_utils.dart';

void main() {
  test('basename normalizes paths with forward slashes', () {
    expect(AppCliUtils.basename('weather'), 'weather');
    expect(AppCliUtils.basename('widgets/weather'), 'weather');
    expect(AppCliUtils.basename('/a/b/cool.js'), 'cool.js');
  });

  test('extractTextLines collects text and label nodes', () {
    final lines = AppCliUtils.extractTextLines({
      'type': 'column',
      'children': [
        {'type': 'text', 'data': '22°C'},
        {'type': 'textButton', 'text': 'Go'},
        {
          'type': 'padding',
          'child': {'type': 'text', 'data': 'Moscow'},
        },
      ],
    });

    expect(lines, containsAll(['22°C', 'Go', 'Moscow']));
  });

  test('buildHelp merges manifest cli metadata', () {
    final help = AppCliUtils.buildHelp(
      manifest: const WidgetManifest(
        id: 'weather',
        name: 'Weather',
        description: 'Weather app',
        version: '1.0.0',
        icon: '🌤️',
        allowedCommands: [],
        networkEnabled: true,
        widgetPath: '/tmp/weather',
        isSingleFile: false,
        cli: {
          'summary': 'City weather',
          'examples': ['yoloit app:state weather'],
        },
      ),
      running: true,
    );

    expect(help['id'], 'weather');
    expect(help['running'], true);
    expect(help['summary'], 'City weather');
    expect(help['globalCommands'], isNotEmpty);
    expect(help['examples'], ['yoloit app:state weather']);
  });
}
