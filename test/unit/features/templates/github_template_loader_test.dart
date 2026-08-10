import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/templates/data/template_loader.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

import '../../../helpers/fake_http_overrides.dart';

void main() {
  group('GitHubTemplateLoader', () {
    late Directory tempDir;
    late FakeHttpOverrides overrides;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('github_templates_test_');
      PlatformDirs.setInstance(
        MacosPlatformDirs(homeOverride: tempDir.path),
      );
      overrides = FakeHttpOverrides();
      HttpOverrides.global = overrides;
    });

    tearDown(() async {
      HttpOverrides.global = null;
      PlatformDirs.reset();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('fetchJsonForTest (_fetchJson)', () {
      test('returns decoded JSON for valid 200 response', () async {
        overrides.responder = (uri, headers) => FakeHttpResponse(
          200,
          utf8.encode(
            jsonEncode([
              <String, dynamic>{'name': 'foo', 'type': 'dir'},
            ]),
          ),
        );
        const loader = GitHubTemplateLoader();
        final result = await loader.fetchJsonForTest(
          'https://api.github.com/repos/test/test/contents/path',
          headers: const <String, String>{},
        );
        expect(result, isA<List<dynamic>>());
        expect(
          (result as List<dynamic>).first['name'],
          'foo',
        );
      });

      test('returns null for empty body', () async {
        overrides.responder =
            (uri, headers) => const FakeHttpResponse(200, <int>[]);
        const loader = GitHubTemplateLoader();
        final result = await loader.fetchJsonForTest(
          'https://api.github.com/repos/test/test/contents/path',
          headers: const <String, String>{},
        );
        expect(result, isNull);
      });

      test('returns null for invalid JSON', () async {
        overrides.responder = (uri, headers) =>
            FakeHttpResponse(200, utf8.encode('not valid json {{{'));
        const loader = GitHubTemplateLoader();
        final result = await loader.fetchJsonForTest(
          'https://api.github.com/repos/test/test/contents/path',
          headers: const <String, String>{},
        );
        expect(result, isNull);
      });

      test('returns null for non-200 status', () async {
        overrides.responder =
            (uri, headers) => const FakeHttpResponse(403, <int>[]);
        const loader = GitHubTemplateLoader();
        final result = await loader.fetchJsonForTest(
          'https://api.github.com/repos/test/test/contents/path',
          headers: const <String, String>{},
        );
        expect(result, isNull);
      });
    });

    group('sync', () {
      test('throws ArgumentError when githubOwner is null', () async {
        // A local-type source has null githubOwner/githubRepo, which sync()
        // must reject with an ArgumentError.
        final source = TemplateSource(
          id: 'no-owner',
          type: TemplateSourceType.local,
          localPath: tempDir.path,
        );
        const loader = GitHubTemplateLoader();
        await expectLater(
          loader.sync(source),
          throwsA(isA<ArgumentError>()),
        );
      });

      test(
        'fetches contents and writes template.yaml to cache dir',
        () async {
          const yamlContent = 'id: test-template\nname: Test Template\n';
          const downloadUrl =
              'https://raw.githubusercontent.com/owner/repo/main/yoloit/templates/my-template/template.yaml';

          overrides.responder = (uri, headers) {
            final path = uri.path;
            // Subdirectory listing — check first (more specific).
            if (path.contains(
              '/contents/yoloit/templates/my-template',
            )) {
              return FakeHttpResponse(
                200,
                utf8.encode(
                  jsonEncode([
                    <String, dynamic>{
                      'name': 'template.yaml',
                      'type': 'file',
                      'download_url': downloadUrl,
                    },
                  ]),
                ),
              );
            }
            // Base path listing.
            if (path.endsWith('/contents/yoloit/templates')) {
              return FakeHttpResponse(
                200,
                utf8.encode(
                  jsonEncode([
                    <String, dynamic>{
                      'name': 'my-template',
                      'type': 'dir',
                    },
                  ]),
                ),
              );
            }
            // Download template.yaml content.
            if (uri.toString() == downloadUrl) {
              return FakeHttpResponse(200, utf8.encode(yamlContent));
            }
            return const FakeHttpResponse(404, <int>[]);
          };

          final source = TemplateSource(
            id: 'gh-test',
            type: TemplateSourceType.github,
            githubOwner: 'owner',
            githubRepo: 'repo',
          );
          const loader = GitHubTemplateLoader();
          await loader.sync(source);

          final cacheDir = Directory(
            p.join(
              tempDir.path,
              '.config',
              'yoloit',
              'templates',
              'cache',
              'gh-test',
            ),
          );
          final templateFile = File(
            p.join(cacheDir.path, 'my-template', 'template.yaml'),
          );
          expect(await templateFile.exists(), isTrue);
          expect(await templateFile.readAsString(), yamlContent);
        },
      );

      test('skips directories without template.yaml', () async {
        overrides.responder = (uri, headers) {
          final path = uri.path;
          if (path.contains(
            '/contents/yoloit/templates/no-yaml',
          )) {
            return FakeHttpResponse(
              200,
              utf8.encode(
                jsonEncode([
                  <String, dynamic>{
                    'name': 'README.md',
                    'type': 'file',
                    'download_url': 'https://example.test/readme',
                  },
                ]),
              ),
            );
          }
          if (path.endsWith('/contents/yoloit/templates')) {
            return FakeHttpResponse(
              200,
              utf8.encode(
                jsonEncode([
                  <String, dynamic>{
                    'name': 'no-yaml',
                    'type': 'dir',
                  },
                ]),
              ),
            );
          }
          return const FakeHttpResponse(404, <int>[]);
        };

        final source = TemplateSource(
          id: 'gh-skip',
          type: TemplateSourceType.github,
          githubOwner: 'owner',
          githubRepo: 'repo',
        );
        const loader = GitHubTemplateLoader();
        await loader.sync(source);

        final cacheDir = Directory(
          p.join(
            tempDir.path,
            '.config',
            'yoloit',
            'templates',
            'cache',
            'gh-skip',
          ),
        );
        // Cache dir is created by sync(), but no subdirectory should exist
        // because the subdir had no template.yaml.
        expect(await cacheDir.exists(), isTrue);
        final subDir = Directory(p.join(cacheDir.path, 'no-yaml'));
        expect(await subDir.exists(), isFalse);
      });
    });
  });
}
