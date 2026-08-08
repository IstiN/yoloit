import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';

void main() {
  group('CliGuidanceService.findSourceTreeCliInRoots', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('cli_guidance_test');
    });

    tearDown(() {
      if (tmp.existsSync()) {
        tmp.deleteSync(recursive: true);
      }
    });

    File createCli(String dirPath, {bool nestedLayout = false}) {
      final rel = nestedLayout ? 'yoloit/tools/yoloit' : 'tools/yoloit';
      final file = File(p.join(dirPath, rel));
      file.createSync(recursive: true);
      return file;
    }

    test('finds tools/yoloit directly at a root', () {
      final root = Directory(p.join(tmp.path, 'repo'))..createSync();
      final cli = createCli(root.path);

      expect(
        CliGuidanceService.instance.findSourceTreeCliInRoots([root.path]),
        cli.path,
      );
    });

    test('walks up from a nested child directory', () {
      final root = Directory(p.join(tmp.path, 'repo2'))..createSync();
      final cli = createCli(root.path);
      final deep = Directory(
        p.join(root.path, 'lib', 'features'),
      )..createSync(recursive: true);

      expect(
        CliGuidanceService.instance.findSourceTreeCliInRoots([deep.path]),
        cli.path,
      );
    });

    test('finds the nested yoloit/tools/yoloit layout', () {
      final root = Directory(p.join(tmp.path, 'outer'))..createSync();
      final cli = createCli(root.path, nestedLayout: true);

      expect(
        CliGuidanceService.instance.findSourceTreeCliInRoots([root.path]),
        cli.path,
      );
    });

    test('returns the match from the first root that has one', () {
      final rootA = Directory(p.join(tmp.path, 'a'))..createSync();
      final rootB = Directory(p.join(tmp.path, 'b'))..createSync();
      final cliA = createCli(rootA.path);
      createCli(rootB.path);

      expect(
        CliGuidanceService.instance.findSourceTreeCliInRoots([
          rootA.path,
          rootB.path,
        ]),
        cliA.path,
      );
    });

    test('skips null and blank roots', () {
      final root = Directory(p.join(tmp.path, 'c'))..createSync();
      final cli = createCli(root.path);

      expect(
        CliGuidanceService.instance.findSourceTreeCliInRoots([
          null,
          '',
          '   ',
          root.path,
        ]),
        cli.path,
      );
    });

    test('returns null when no root contains the CLI', () {
      final empty1 = Directory(p.join(tmp.path, 'empty1'))..createSync();
      final empty2 = Directory(p.join(tmp.path, 'empty2'))..createSync();

      expect(
        CliGuidanceService.instance.findSourceTreeCliInRoots([
          empty1.path,
          empty2.path,
        ]),
        isNull,
      );
    });

    test('gives up after 10 directory levels', () {
      // CLI sits 11 levels above the starting directory — out of reach.
      final cli = createCli(tmp.path);
      var deepPath = tmp.path;
      for (var i = 0; i < 11; i++) {
        deepPath = p.join(deepPath, 'd$i');
      }
      Directory(deepPath).createSync(recursive: true);

      expect(
        CliGuidanceService.instance.findSourceTreeCliInRoots([deepPath]),
        isNot(cli.path),
      );
    });

    test('tolerates duplicate roots', () {
      final empty = Directory(p.join(tmp.path, 'dup'))..createSync();

      expect(
        CliGuidanceService.instance.findSourceTreeCliInRoots([
          empty.path,
          empty.path,
        ]),
        isNull,
      );
    });
  });
}
