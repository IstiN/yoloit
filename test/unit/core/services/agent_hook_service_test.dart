import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/services/agent_hook_service.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';

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

  group('AgentHookService polling', () {
    late Directory home;
    late Directory hooksDir;
    late AgentHookService service;
    StreamSubscription<HookEvent>? subscription;

    String hookFile(String name) => '${hooksDir.path}/$name';

    void writeHookEvent(
      String name, {
      required String event,
      String cwd = '/ws/demo',
      String cwdHash = 'abc123',
      String? tool,
      int ts = 1,
    }) {
      File(hookFile(name)).writeAsStringSync(
        jsonEncode({
          'event': event,
          'cwd': cwd,
          'cwdHash': cwdHash,
          'tool': ?tool,
          'ts': ts,
        }),
      );
    }

    Future<List<HookEvent>> collectEvents() async {
      final events = <HookEvent>[];
      subscription = service.events.listen(events.add);
      service.start();
      // Let the immediate poll plus at least one timer poll run.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      return events;
    }

    setUp(() {
      home = Directory.systemTemp.createTempSync('yoloit-hook-poll-home');
      AgentHookService.debugHomeDir = home.path;
      hooksDir = Directory('${home.path}/.yoloit/hooks');
      service = AgentHookService(
        pollInterval: const Duration(milliseconds: 20),
      );
    });

    tearDown(() async {
      service.stop();
      await subscription?.cancel();
      subscription = null;
      AgentHookService.debugHomeDir = null;
      if (home.existsSync()) home.deleteSync(recursive: true);
    });

    test('start/stop without a hooks dir emits nothing and does not throw',
        () async {
      final events = await collectEvents();
      expect(events, isEmpty);
    });

    test('emits HookEvents for json files and deletes them', () async {
      hooksDir.createSync(recursive: true);
      writeHookEvent(
        'abc_100_preToolUse.json',
        event: 'preToolUse',
        tool: 'Bash',
      );

      final events = await collectEvents();

      expect(events, hasLength(1));
      expect(events.single.event, 'preToolUse');
      expect(events.single.workspacePath, '/ws/demo');
      expect(events.single.workspaceHash, 'abc123');
      expect(events.single.tool, 'Bash');
      expect(events.single.timestamp, 1);
      expect(events.single.phase, isA<ToolPhase>());
      // The event file was consumed.
      expect(File(hookFile('abc_100_preToolUse.json')).existsSync(), isFalse);
    });

    test('skips .tmp files, non-json files and subdirectories', () async {
      hooksDir.createSync(recursive: true);
      writeHookEvent('abc_1_sessionEnd.json', event: 'sessionEnd');
      File(hookFile('abc_2_preToolUse.json.tmp'))
          .writeAsStringSync(jsonEncode({'event': 'preToolUse'}));
      File(hookFile('notes.txt')).writeAsStringSync('not an event');
      Directory(hookFile('a_dir.json')).createSync();

      final events = await collectEvents();

      expect(events, hasLength(1));
      expect(events.single.event, 'sessionEnd');
      expect(events.single.phase, isA<DonePhase>());
      // Non-event files are left alone.
      expect(File(hookFile('abc_2_preToolUse.json.tmp')).existsSync(), isTrue);
      expect(File(hookFile('notes.txt')).existsSync(), isTrue);
      expect(Directory(hookFile('a_dir.json')).existsSync(), isTrue);
    });

    test('deletes unparseable event files without emitting an event',
        () async {
      hooksDir.createSync(recursive: true);
      File(hookFile('abc_3_bad.json')).writeAsStringSync('{broken');

      final events = await collectEvents();

      expect(events, isEmpty);
      expect(File(hookFile('abc_3_bad.json')).existsSync(), isFalse);
    });

    test('processes events from later polls via the timer', () async {
      hooksDir.createSync(recursive: true);
      final events = <HookEvent>[];
      subscription = service.events.listen(events.add);
      service.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Written after start() — only the periodic timer can pick it up.
      writeHookEvent('abc_4_errorOccurred.json', event: 'errorOccurred');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(events, hasLength(1));
      expect(events.single.event, 'errorOccurred');
      expect(events.single.phase, isA<ErrorPhase>());
    });

    test('maps hook events to phases and defaults missing fields', () async {
      hooksDir.createSync(recursive: true);
      writeHookEvent('h_1.json', event: 'userPromptSubmitted');
      writeHookEvent(
        'h_2.json',
        event: 'postToolUse',
        tool: 'Bash',
      );
      writeHookEvent('h_3.json', event: 'sessionStart');

      final events = await collectEvents();

      expect(events, hasLength(3));
      expect(events[0].phase, isA<ThinkingPhase>());
      expect(events[1].phase, isNull);
      expect(events[2].phase, isNull);
      // Missing optional fields fall back to defaults.
      const raw = HookEvent(
        event: 'unknown',
        workspacePath: '',
        workspaceHash: '',
        timestamp: 0,
      );
      expect(raw.tool, isNull);
      expect(raw.phase, isNull);
    });
  });
}
