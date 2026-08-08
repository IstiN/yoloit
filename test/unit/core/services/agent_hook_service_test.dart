import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/services/agent_hook_service.dart';

void main() {
  group('AgentHookService.installHooks', () {
    late Directory home;
    late Directory workspace;

    String canonicalScript() => '${home.path}/.yoloit/bin/yoloit-hook.sh';
    String canonicalJson() => '${home.path}/.yoloit/bin/hooks.json';
    String linkScript() => '${workspace.path}/.github/hooks/yoloit-hook.sh';
    String linkJson() => '${workspace.path}/.github/hooks/hooks.json';

    setUp(() {
      home = Directory.systemTemp.createTempSync('yoloit-hook-home');
      workspace = Directory.systemTemp.createTempSync('yoloit-hook-ws');
      AgentHookService.debugHomeDir = home.path;
    });

    tearDown(() {
      AgentHookService.debugHomeDir = null;
      if (home.existsSync()) home.deleteSync(recursive: true);
      if (workspace.existsSync()) workspace.deleteSync(recursive: true);
    });

    test('writes canonical files and symlinks them into the workspace',
        () async {
      await AgentHookService.installHooks(workspace.path);

      expect(File(canonicalScript()).existsSync(), isTrue);
      expect(File(canonicalJson()).existsSync(), isTrue);
      expect(await Link(linkScript()).target(), canonicalScript());
      expect(await Link(linkJson()).target(), canonicalJson());

      // The makeExecutable branch chmods the script link.
      final mode = FileStat.statSync(linkScript()).mode;
      expect(mode & 0x49, isNonZero);

      final json = File(canonicalJson()).readAsStringSync();
      expect(json, contains('"sessionStart"'));
    });

    test('is idempotent when links already point at the canonical files',
        () async {
      await AgentHookService.installHooks(workspace.path);
      final before = FileStat.statSync(canonicalScript()).modified;

      await AgentHookService.installHooks(workspace.path);

      expect(await Link(linkScript()).target(), canonicalScript());
      expect(await Link(linkJson()).target(), canonicalJson());
      // _writeIfChanged left the canonical file untouched.
      expect(FileStat.statSync(canonicalScript()).modified, before);
    });

    test('replaces a link whose target drifted to another file', () async {
      await AgentHookService.installHooks(workspace.path);
      final other = File('${workspace.path}/other.sh')
        ..writeAsStringSync('# other');
      await Link(linkScript()).delete();
      await Link(linkScript()).create(other.path);
      expect(await Link(linkScript()).target(), other.path);

      await AgentHookService.installHooks(workspace.path);

      expect(await Link(linkScript()).target(), canonicalScript());
    });

    test('replaces a stale plain file with a symlink', () async {
      await AgentHookService.installHooks(workspace.path);
      await Link(linkJson()).delete();
      File(linkJson()).writeAsStringSync('{"stale":true}');

      await AgentHookService.installHooks(workspace.path);

      expect(await Link(linkJson()).target(), canonicalJson());
      expect(File(linkJson()).readAsStringSync(), contains('"sessionStart"'));
    });

    test('creates links from scratch when nothing exists yet', () async {
      // No prior install — both _symlinkIfNeeded calls take the fresh-create
      // path (neither link nor plain file present).
      await AgentHookService.installHooks(workspace.path);

      expect(Link(linkScript()).existsSync(), isTrue);
      expect(Link(linkJson()).existsSync(), isTrue);
    });
  });
}
