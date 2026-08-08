import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/widgets/widget_registry_service_vm.dart';

void main() {
  late Directory home;
  late Directory source;
  final service = WidgetRegistryService.instance;

  setUp(() {
    home = Directory.systemTemp.createTempSync('yoloit-widget-home');
    source = Directory.systemTemp.createTempSync('yoloit-widget-src');
    WidgetRegistryService.debugHomeDir = home.path;
    service.invalidate();
  });

  tearDown(() {
    WidgetRegistryService.debugHomeDir = null;
    service.invalidate();
    if (home.existsSync()) home.deleteSync(recursive: true);
    if (source.existsSync()) source.deleteSync(recursive: true);
  });

  Directory createWidgetDir(
    Directory parent,
    String name, {
    String widgetName = 'Test Widget',
  }) {
    final dir = Directory('${parent.path}${Platform.pathSeparator}$name')
      ..createSync(recursive: true);
    File('${dir.path}${Platform.pathSeparator}widget.js')
        .writeAsStringSync('// $name');
    File('${dir.path}${Platform.pathSeparator}manifest.json')
        .writeAsStringSync('{"name":"$widgetName"}');
    return dir;
  }

  group('install', () {
    test('installs a widget directory into the apps dir', () async {
      final dir = createWidgetDir(source, 'my-widget', widgetName: 'My Widget');

      final manifest = await service.install(dir.path);

      expect(manifest, isNotNull);
      expect(manifest!.id, 'my-widget');
      expect(manifest.name, 'My Widget');
      expect(manifest.isSingleFile, isFalse);
      final installed = Directory(
        '${service.appsDir}${Platform.pathSeparator}my-widget',
      );
      expect(installed.existsSync(), isTrue);
      expect(
        File(
          '${installed.path}${Platform.pathSeparator}widget.js',
        ).readAsStringSync(),
        '// my-widget',
      );
    });

    test('replaces an existing install of the same widget', () async {
      final dir = createWidgetDir(source, 'dup-widget', widgetName: 'First');
      await service.install(dir.path);

      File('${dir.path}${Platform.pathSeparator}manifest.json')
          .writeAsStringSync('{"name":"Second"}');
      final manifest = await service.install(dir.path);

      expect(manifest, isNotNull);
      expect(manifest!.name, 'Second');
    });

    test('skips copying when the source is already inside the apps dir',
        () async {
      final appsDir = Directory(service.appsDir)..createSync(recursive: true);
      final dir = createWidgetDir(appsDir, 'inner', widgetName: 'Inner');

      final manifest = await service.install(dir.path);

      expect(manifest, isNotNull);
      expect(manifest!.id, 'inner');
      expect(manifest.name, 'Inner');
      expect(manifest.widgetPath, dir.path);
    });

    test('installs a single .js file', () async {
      final file = File('${source.path}${Platform.pathSeparator}solo.js')
        ..writeAsStringSync('// solo');

      final manifest = await service.install(file.path);

      expect(manifest, isNotNull);
      expect(manifest!.id, 'solo');
      expect(manifest.isSingleFile, isTrue);
      expect(
        File(
          '${service.appsDir}${Platform.pathSeparator}solo.js',
        ).readAsStringSync(),
        '// solo',
      );
    });

    test('does not copy a .js file that already lives in the apps dir',
        () async {
      Directory(service.appsDir).createSync(recursive: true);
      final file = File('${service.appsDir}${Platform.pathSeparator}here.js')
        ..writeAsStringSync('// here');

      final manifest = await service.install(file.path);

      expect(manifest, isNotNull);
      expect(manifest!.id, 'here');
      expect(manifest.isSingleFile, isTrue);
      expect(file.readAsStringSync(), '// here');
    });

    test('returns null for a non-existent source path', () async {
      final manifest = await service.install(
        '${source.path}${Platform.pathSeparator}missing',
      );
      expect(manifest, isNull);
    });

    test('returns null for a non-js file', () async {
      final file = File('${source.path}${Platform.pathSeparator}notes.txt')
        ..writeAsStringSync('not a widget');
      expect(await service.install(file.path), isNull);
    });
  });

  group('find', () {
    test('loads a widget directly from an absolute path without installing',
        () async {
      final dir = createWidgetDir(source, 'dev-widget', widgetName: 'Dev');

      final manifest = await service.find(dir.path);

      expect(manifest, isNotNull);
      expect(manifest!.id, 'dev-widget');
      // Not installed into the apps dir.
      expect(
        Directory(
          '${service.appsDir}${Platform.pathSeparator}dev-widget',
        ).existsSync(),
        isFalse,
      );
    });

    test('expands ~ paths using the home directory', () async {
      final dir = createWidgetDir(home, 'tilde-widget', widgetName: 'Tilde');

      final manifest = await service.find('~/tilde-widget');

      expect(manifest, isNotNull);
      expect(manifest!.widgetPath, dir.path);
    });

    test('returns null for a missing absolute path', () async {
      final manifest = await service.find(
        '${source.path}${Platform.pathSeparator}nope',
      );
      expect(manifest, isNull);
    });

    test('returns null for an absolute dir without widget.js', () async {
      final dir = Directory('${source.path}${Platform.pathSeparator}empty')
        ..createSync();
      expect(await service.find(dir.path), isNull);
    });

    test('finds an installed widget by id', () async {
      final dir = createWidgetDir(source, 'by-id', widgetName: 'By Id');
      await service.install(dir.path);

      final manifest = await service.find('by-id');

      expect(manifest, isNotNull);
      expect(manifest!.id, 'by-id');
      expect(manifest.name, 'By Id');
    });

    test('returns null for an unknown id', () async {
      expect(await service.find('definitely-not-installed'), isNull);
    });
  });
}
