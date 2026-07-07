import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/templates/data/template_loader_web.dart';
import 'package:yoloit/features/templates/data/template_sources_service_web.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TemplateSourcesService web', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('default source is GitHub-backed', () {
      final service = TemplateSourcesService.instance;
      expect(service.defaultSource.type, TemplateSourceType.github);
      expect(service.defaultSource.githubOwner, 'IstiN');
      expect(service.defaultSource.githubRepo, 'yoloit');
    });

    test('builtInSource points at bundled assets', () {
      final service = TemplateSourcesService.instance;
      expect(service.builtInSource.type, TemplateSourceType.local);
      expect(service.builtInSource.localPath, 'yoloit/templates');
    });

    test('loadAll returns built-in and default sources when empty', () async {
      final sources = await TemplateSourcesService.instance.loadAll();
      expect(sources.length, 2);
      expect(sources.first.id, 'yoloit-builtins');
      expect(sources.last.id, 'yoloit-github');
    });

    test('saveAll and loadAll round-trip', () async {
      final service = TemplateSourcesService.instance;
      final custom = const TemplateSource(
        id: 'custom-local',
        type: TemplateSourceType.local,
        localPath: '/custom/templates',
      );
      await service.saveAll([service.builtInSource, custom]);

      final sources = await service.loadAll();
      expect(sources.any((s) => s.id == 'custom-local'), isTrue);
      expect(sources.any((s) => s.id == 'yoloit-builtins'), isTrue);
      expect(sources.any((s) => s.id == 'yoloit-github'), isTrue);
    });

    test('addOrUpdate replaces existing source', () async {
      final service = TemplateSourcesService.instance;
      await service.addOrUpdate(
        const TemplateSource(
          id: 'custom-local',
          type: TemplateSourceType.local,
          localPath: '/first',
        ),
      );
      await service.addOrUpdate(
        const TemplateSource(
          id: 'custom-local',
          type: TemplateSourceType.local,
          localPath: '/second',
        ),
      );

      final sources = await service.loadAll();
      final custom = sources.firstWhere((s) => s.id == 'custom-local');
      expect(custom.localPath, '/second');
    });

    test('remove deletes source', () async {
      final service = TemplateSourcesService.instance;
      await service.addOrUpdate(
        const TemplateSource(
          id: 'to-remove',
          type: TemplateSourceType.local,
          localPath: '/tmp',
        ),
      );
      await service.remove('to-remove');

      final sources = await service.loadAll();
      expect(sources.any((s) => s.id == 'to-remove'), isFalse);
    });
  });

  group('LocalTemplateLoader web', () {
    test('load returns templates for bundled assets', () async {
      const loader = LocalTemplateLoader();
      final source = TemplateSource(
        id: 'builtins',
        type: TemplateSourceType.local,
        localPath: 'yoloit/templates',
      );
      final templates = await loader.load(source);
      expect(templates, isNotEmpty);
      expect(templates.map((t) => t.id), contains('flutter-project'));
    });

    test('load ignores missing assets gracefully', () async {
      const loader = LocalTemplateLoader();
      final source = TemplateSource(
        id: 'missing',
        type: TemplateSourceType.local,
        localPath: 'yoloit/templates',
      );
      final templates = await loader.load(source);
      expect(templates, isNotEmpty);
    });

    test('sync is a no-op', () async {
      const loader = LocalTemplateLoader();
      await loader.sync(
        const TemplateSource(id: 'x', type: TemplateSourceType.local, localPath: 'x'),
      );
      expect(true, isTrue);
    });
  });

  group('GitHubTemplateLoader web', () {
    test('load always returns empty', () async {
      const loader = GitHubTemplateLoader();
      final templates = await loader.load(
        const TemplateSource(
          id: 'gh',
          type: TemplateSourceType.github,
          githubOwner: 'o',
          githubRepo: 'r',
        ),
      );
      expect(templates, isEmpty);
    });

    test('sync is a no-op', () async {
      const loader = GitHubTemplateLoader();
      await loader.sync(
        const TemplateSource(
          id: 'gh',
          type: TemplateSourceType.github,
          githubOwner: 'o',
          githubRepo: 'r',
        ),
      );
      expect(true, isTrue);
    });
  });
}
