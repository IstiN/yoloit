import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/core/cli/cli_text_argument_resolver.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

void main() {
  late Directory clipDir;
  late File clipFile;

  setUp(() async {
    clipDir = Directory('${PlatformDirs.instance.tempDir}/yoloit_clip');
    await clipDir.create(recursive: true);
    clipFile = File('${clipDir.path}/clip_1782420742881.txt');
    await clipFile.writeAsString('Effort →');
  });

  tearDown(() async {
    if (await clipFile.exists()) {
      await clipFile.delete();
    }
  });

  test('resolve reads yoloit_clip txt file contents', () {
    expect(CliTextArgumentResolver.resolve(clipFile.path), 'Effort →');
  });

  test(
    'resolve extracts last USER block from chat session clip export',
    () async {
      final chatClip = File('${clipDir.path}/clip_1782423620279.txt');
      await chatClip.writeAsString('''
[2026-06-24T14:33:38.250976] USER
Добавm low impact и low efforts примеры в эту карточку

[2026-06-25T23:50:56.141703] USER
добавь фейковых примеро в карточку

[2026-06-25T23:51:00.372020] ASSISTANT
Готово!
''');
      expect(
        CliTextArgumentResolver.resolve(chatClip.path),
        'добавь фейковых примеро в карточку',
      );
    },
  );

  test('resolveJsonParameter expands clip path inside json.text', () async {
    final resolved = CliTextArgumentResolver.resolveJsonParameter(
      jsonEncode(<String, String>{'text': clipFile.path}),
    );
    final decoded = jsonDecode(resolved) as Map<String, dynamic>;
    expect(decoded['text'], 'Effort →');
  });

  test('resolveJsonParameter accepts raw clip path body', () {
    final resolved = CliTextArgumentResolver.resolveJsonParameter(
      clipFile.path,
    );
    final decoded = jsonDecode(resolved) as Map<String, dynamic>;
    expect(decoded['text'], 'Effort →');
  });

  test('executor renders do set with resolved clip json body', () async {
    final executor = YoloitCliToolExecutor(execute: false);
    final result =
        jsonDecode(
              await executor.invoke('pdo', <String, Object?>{
                'b': 'board-1',
                'p': 'shape-1',
                'a': 'set',
                'j': jsonEncode(<String, String>{'text': clipFile.path}),
              }),
            )
            as Map<String, Object?>;

    expect(result['ok'], isTrue);
    expect(
      result['command'],
      "yoloit do board-1 shape-1 set '{\"text\":\"Effort →\"}'",
    );
  });

  test('resolve supports @-prefixed clip paths', () {
    expect(CliTextArgumentResolver.resolve('@${clipFile.path}'), 'Effort →');
  });

  test('resolve supports shell-quoted clip paths', () {
    expect(CliTextArgumentResolver.resolve("'${clipFile.path}'"), 'Effort →');
  });

  test('resolve leaves non-clip paths unchanged', () {
    const literal = '/tmp/other/file.txt';
    expect(CliTextArgumentResolver.resolve(literal), isNull);
  });

  test('normalizer promotes file path key to text and resolves clip file', () {
    final normalized = YoloitCliToolArgumentNormalizer.normalize(
      functionName: 'shs',
      arguments: <String, Object?>{'path': clipFile.path},
      userMessage: '',
    );
    expect(normalized['text'], 'Effort →');
  });

  test('resolveActionArgs reads clip file for do set payloads', () async {
    final args = CliTextArgumentResolver.resolveActionArgs({
      'action': 'set',
      'text': clipFile.path,
    });
    expect(args['text'], 'Effort →');
  });

  test('resolve rejects terminal log clip dumps', () async {
    final logClip = File('${clipDir.path}/clip_1782557536456.txt');
    await logClip.writeAsString('''
Launching lib/main.dart on macOS in debug mode...
flutter: [BoardView] Canvas background pointer down
Another exception was thrown: type String is not a subtype of num
''');
    expect(CliTextArgumentResolver.resolve(logClip.path), isNull);
    expect(CliTextArgumentResolver.isClipTextFilePath(logClip.path), isTrue);

    final args = CliTextArgumentResolver.resolveActionArgs({
      'text': logClip.path,
    });
    expect(args.containsKey('text'), isFalse);
  });

  test('resolve rejects oversized non-chat clip files', () async {
    final hugeClip = File('${clipDir.path}/clip_1782559999999.txt');
    await hugeClip.writeAsString('x' * 9000);
    expect(CliTextArgumentResolver.resolve(hugeClip.path), isNull);
  });

  test('resolveActionArgs unwraps literal shell quotes from text fields', () {
    final singleQuoted = CliTextArgumentResolver.resolveActionArgs({
      'text': "'Impact ↑'",
    });
    final doubleQuoted = CliTextArgumentResolver.resolveActionArgs({
      'text': '"Impact ↑"',
    });

    expect(singleQuoted['text'], 'Impact ↑');
    expect(doubleQuoted['text'], 'Impact ↑');
  });

  test(
    'executor renders sticky:append with clip text not literal --text',
    () async {
      final executor = YoloitCliToolExecutor(execute: false);
      final result =
          jsonDecode(
                await executor.invoke('sta', <String, Object?>{
                  'b': 'board-1',
                  'p': 'Fill-ins',
                  'tx': clipFile.path,
                }),
              )
              as Map<String, Object?>;

      expect(result['ok'], isTrue);
      expect(
        result['command'],
        "yoloit sticky:append board-1 Fill-ins --text 'Effort →'",
      );
    },
  );

  test('resolveJsonParameter wraps bare JSON string bodies', () {
    final resolved = CliTextArgumentResolver.resolveJsonParameter(
      jsonEncode('hello'),
    );
    final decoded = jsonDecode(resolved) as Map<String, dynamic>;
    expect(decoded['text'], 'hello');
  });

  test('installedCliPathForHome uses yoloit-debug in debug builds', () {
    expect(
      CliServer.installedCliPathForHome('/Users/me'),
      '/Users/me/.config/yoloit-dev/yoloit-debug',
    );
  });

  test('executor renders shape:set with clip file text inline', () async {
    final executor = YoloitCliToolExecutor(execute: false);
    final result =
        jsonDecode(
              await executor.invoke('shs', <String, Object?>{
                'b': 'board-1',
                'p': 'Effort',
                'tx': clipFile.path,
              }),
            )
            as Map<String, Object?>;

    expect(result['ok'], isTrue);
    expect(
      result['command'],
      "yoloit shape:set board-1 Effort --text 'Effort →'",
    );
  });

  test('executor renders uirnd with JSON object tree argument', () async {
    final executor = YoloitCliToolExecutor(execute: false);
    final tree = <String, Object?>{
      'type': 'column',
      'children': <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'data': 'Item 1'},
      ],
    };
    final result =
        jsonDecode(
              await executor.invoke('uirnd', <String, Object?>{
                'b': 'board-1',
                'p': 'Мой список',
                'j': tree,
              }),
            )
            as Map<String, Object?>;

    expect(result['ok'], isTrue);
    expect(result['command'], contains('ui:render'));
    expect(result['command'], contains('"type":"column"'));
    expect(result['command'], contains('Item 1'));
  });

    test('normalizer infers ui:create title and board.ui panel type', () {
      const message = 'добавь кастом view как пример со списком';
      final createArgs = YoloitCliToolArgumentNormalizer.normalize(
        functionName: 'uicrt',
        arguments: <String, Object?>{'b': 'board-1'},
        userMessage: message,
      );
      expect(createArgs['title'], 'Пример списка');

    final panelArgs = YoloitCliToolArgumentNormalizer.normalize(
      functionName: 'pmk',
      arguments: <String, Object?>{'b': 'board-1'},
      userMessage: message,
    );
    expect(panelArgs['type'], 'board.ui');
  });

  test('normalizer strips chat panel id from uirnd args', () {
    final normalized = YoloitCliToolArgumentNormalizer.normalize(
      functionName: 'uirnd',
      arguments: <String, Object?>{
        'b': 'board-1',
        'p': 'panel-yolo-assistant-badge',
        'j': <String, Object?>{'type': 'text', 'data': 'Hi'},
      },
      userMessage: '',
    );
    expect(normalized.containsKey('p'), isFalse);
    expect(normalized['tree'], contains('"type":"text"'));
  });
}
