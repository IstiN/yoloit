import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/templates/data/template_sources_service.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

void main() {
  late Directory home;
  late File storageFile;

  final service = TemplateSourcesService.instance;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('template-sources-test-');
    PlatformDirs.setInstance(LinuxPlatformDirs(homeOverride: home.path));
    storageFile = File(
      p.join(PlatformDirs.instance.configDir, 'template_sources.json'),
    );
  });

  tearDown(() async {
    PlatformDirs.reset();
    if (await home.exists()) {
      await home.delete(recursive: true);
    }
  });

  List<TemplateSource> expectedBuiltIns() {
    final builtIn = service.builtInSource;
    return builtIn == null
        ? [service.defaultSource]
        : [builtIn, service.defaultSource];
  }

  Future<void> writeSources(List<TemplateSource> sources) async {
    await storageFile.parent.create(recursive: true);
    await storageFile.writeAsString(encodeSourcesJson(sources));
  }

  Future<List<TemplateSource>> readStoredSources() async {
    return parseSourcesJson(await storageFile.readAsString());
  }

  const localSource = TemplateSource(
    id: 'local-extra',
    type: TemplateSourceType.local,
    localPath: '/tmp/templates',
  );

  const otherGithubSource = TemplateSource(
    id: 'other-github',
    type: TemplateSourceType.github,
    githubOwner: 'foo',
    githubRepo: 'bar',
  );

  group('TemplateSourcesService.loadAll', () {
    test('returns built-in defaults when the storage file is missing', () async {
      final sources = await service.loadAll();

      expect(sources, expectedBuiltIns());
      expect(await storageFile.exists(), isFalse);
    });

    test('returns built-in defaults when the storage file is blank', () async {
      await storageFile.parent.create(recursive: true);
      await storageFile.writeAsString('   \n');

      final sources = await service.loadAll();

      expect(sources, expectedBuiltIns());
      expect(await storageFile.readAsString(), '   \n');
    });

    test('returns built-in defaults when the storage file is corrupt', () async {
      await storageFile.parent.create(recursive: true);
      await storageFile.writeAsString('not json at all');

      final sources = await service.loadAll();

      expect(sources, expectedBuiltIns());
    });

    test('keeps configured sources and ensures built-ins are present', () async {
      await writeSources([localSource, otherGithubSource]);

      final sources = await service.loadAll();

      expect(sources, [...expectedBuiltIns(), localSource, otherGithubSource]);
    });

    test('does not duplicate the default source when already stored', () async {
      await writeSources([service.defaultSource, localSource]);

      final sources = await service.loadAll();

      expect(
        sources.where((s) => s.id == service.defaultSource.id).length,
        1,
      );
      expect(sources, contains(localSource));
    });

    test('leaves an up-to-date default source file untouched', () async {
      await writeSources([service.defaultSource]);
      final before = await storageFile.readAsString();

      final sources = await service.loadAll();

      expect(sources, contains(service.defaultSource));
      expect(await storageFile.readAsString(), before);
    });

    test('rewrites the legacy yoloit/yoloit default to the current one',
        () async {
      const legacy = TemplateSource(
        id: 'yoloit-github',
        type: TemplateSourceType.github,
        githubOwner: 'yoloit',
        githubRepo: 'yoloit',
        githubToken: 'secret-token',
        enabled: false,
      );
      await writeSources([legacy, localSource]);

      final sources = await service.loadAll();

      final normalized = sources.firstWhere(
        (s) => s.id == service.defaultSource.id,
      );
      expect(normalized.githubOwner, kDefaultGithubOwner);
      expect(normalized.githubRepo, kDefaultGithubRepo);
      expect(normalized.enabled, isFalse);
      expect(normalized.githubToken, 'secret-token');

      final stored = await readStoredSources();
      expect(stored.first.githubOwner, kDefaultGithubOwner);
      expect(stored.first.githubRepo, kDefaultGithubRepo);
    });

    test('rewrites a default source with empty owner or repo', () async {
      const incomplete = TemplateSource(
        id: 'yoloit-github',
        type: TemplateSourceType.github,
        githubOwner: '',
        githubRepo: '',
      );
      await writeSources([incomplete]);

      final sources = await service.loadAll();

      final normalized = sources.firstWhere(
        (s) => s.id == service.defaultSource.id,
      );
      expect(normalized.githubOwner, kDefaultGithubOwner);
      expect(normalized.githubRepo, kDefaultGithubRepo);
      expect(normalized.enabled, isTrue);
    });

    test('clears the GitHub cache when the legacy default is rewritten',
        () async {
      const legacy = TemplateSource(
        id: 'yoloit-github',
        type: TemplateSourceType.github,
        githubOwner: 'yoloit',
        githubRepo: 'yoloit',
      );
      await writeSources([legacy]);
      final cacheDir = Directory(
        p.join(
          PlatformDirs.instance.configDir,
          'templates',
          'cache',
          service.defaultSource.id,
        ),
      );
      await cacheDir.create(recursive: true);
      await File(p.join(cacheDir.path, 'cached.json')).writeAsString('{}');

      await service.loadAll();

      expect(await cacheDir.exists(), isFalse);
    });

    test('keeps the GitHub cache when nothing was rewritten', () async {
      await writeSources([service.defaultSource]);
      final cacheDir = Directory(
        p.join(
          PlatformDirs.instance.configDir,
          'templates',
          'cache',
          service.defaultSource.id,
        ),
      );
      await cacheDir.create(recursive: true);

      await service.loadAll();

      expect(await cacheDir.exists(), isTrue);
    });

    test('does not touch non-default github sources', () async {
      await writeSources([otherGithubSource]);

      final sources = await service.loadAll();

      expect(sources, contains(otherGithubSource));
      final stored = await readStoredSources();
      expect(stored, [otherGithubSource]);
    });
  });
}
