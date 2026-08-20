import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/services/user_data_archive.dart';

/// Build a realistic YoLoIT user-state tree inside [root]:
///
/// ~/.config/yoloit/
///   agent_configs.json
///   state.json                 (CLI bookmarks — included by default)
///   skills_store.json
///   skills/yoloit/SKILL.md
///   runtime/port               (excluded)
///   templates/cache/x/y.json   (excluded)
///   credentials/foo.json       (excluded unless secrets=true)
///
/// ~/Library/Application Support/yoloit/
///   boards_history/board-1.json
///   chat_sessions/s1.json
///   asr_samples/a.wav          (excluded)
///   calendar_events/p.json
///
/// ~/.yoloit/
///   config.json
///   workspaces.json            (absolute paths inside)
class _Fixture {
  _Fixture(this.root);

  final Directory root;

  late final Directory home = Directory(p.join(root.path, 'Users', 'tester'));
  late final Directory configDir = Directory(
    p.join(home.path, '.config', 'yoloit'),
  );
  late final Directory dataDir = Directory(
    p.join(home.path, 'Library', 'Application Support', 'yoloit'),
  );
  late final Directory yoloitHome = Directory(p.join(home.path, '.yoloit'));

  void populate() {
    _mkdir(configDir);
    _mkdir(dataDir);
    _mkdir(yoloitHome);

    File(p.join(configDir.path, 'agent_configs.json'))
        .writeAsStringSync('{}');
    File(p.join(configDir.path, 'state.json'))
        .writeAsStringSync('{"currentBoard":"board-1"}');
    File(p.join(configDir.path, 'skills_store.json'))
        .writeAsStringSync('{"installed":["yoloit"]}');

    final skills = Directory(p.join(configDir.path, 'skills', 'yoloit'));
    skills.createSync(recursive: true);
    File(p.join(skills.path, 'SKILL.md'))
        .writeAsStringSync('# yoloit');

    final runtime = Directory(p.join(configDir.path, 'runtime'));
    runtime.createSync(recursive: true);
    File(p.join(runtime.path, 'port')).writeAsStringSync('12345');

    final cache = Directory(
      p.join(configDir.path, 'templates', 'cache', 'src1'),
    );
    cache.createSync(recursive: true);
    File(p.join(cache.path, 'x.json')).writeAsStringSync('{}');

    final creds = Directory(p.join(configDir.path, 'credentials'));
    creds.createSync(recursive: true);
    File(p.join(creds.path, 'foo.json'))
        .writeAsStringSync('{"value":"secret"}');

    File(p.join(dataDir.path, 'boards_history', 'board-1.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{}');
    File(p.join(dataDir.path, 'chat_sessions', 's1.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{}');
    File(p.join(dataDir.path, 'asr_samples', 'a.wav'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('RIFF');
    File(p.join(dataDir.path, 'calendar_events', 'p.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{}');

    File(p.join(yoloitHome.path, 'config.json'))
        .writeAsStringSync('{}');
    File(p.join(yoloitHome.path, 'workspaces.json')).writeAsStringSync(jsonEncode({
      'workspaces': [
        {
          'id': 'ws-1',
          'name': 'Demo',
          'paths': [p.join(home.path, 'code', 'api')],
        },
      ],
    }));
  }

  void _mkdir(Directory d) => d.createSync(recursive: true);

  ArchiveRoots roots({bool withPrefs = true}) => ArchiveRoots(
        platformDirs: MacosPlatformDirs(homeOverride: home.path),
        yoloitHome: yoloitHome.path,
        sharedPrefsAvailable: withPrefs,
      );

  UserDataArchive makeService({bool withPrefs = true}) =>
      UserDataArchive.withOverrides(
        roots: roots(withPrefs: withPrefs),
        sourceHome: home.path,
        sourceUsername: 'tester',
        sourceHostname: 'test-host',
      );

  /// Seed SharedPreferences mock with one board whose metadata.defaultFolder
  /// points into [home].
  void seedPrefs() {
    final board = {
      'id': 'board-1',
      'name': 'Sample',
      'metadata': {
        'defaultFolder': p.join(home.path, 'code', 'api'),
      },
      'panels': [
        {
          'id': 'p-1',
          'type': 'filetree',
          'params': {'rootPath': p.join(home.path, 'code', 'api', 'src')},
        },
        {
          'id': 'p-2',
          'type': 'terminal',
          'state': {'workingDir': p.join(home.path, 'code', 'api')},
        },
      ],
    };
    SharedPreferences.setMockInitialValues({
      'board.documents.v1': jsonEncode([board]),
      'theme_preset': 'neonPurple',
    });
  }
}

void main() {
  group('UserDataArchive', () {
    late _Fixture fix;
    late Directory scratch;

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('yoloit_archive_test_');
      fix = _Fixture(scratch);
      fix.populate();
      PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: fix.home.path));
    });

    tearDown(() {
      PlatformDirs.reset();
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });

    test('pack writes a tar archive with manifest', () async {
      fix.seedPrefs();
      final svc = fix.makeService();
      final out = File(p.join(scratch.path, 'out.tar'));
      final manifest = await svc.pack(outputPath: out.path);

      expect(out.existsSync(), isTrue);
      expect(manifest.schemaVersion, ArchiveManifest.currentSchemaVersion);
      expect(manifest.contents, containsAll(['prefs', 'config', 'data', 'workspaces']));
      expect(manifest.sourceHome, fix.home.path);
      expect(manifest.pathIndex, isNotEmpty);
    });

    test('pack excludes runtime/, templates/cache/, asr_samples/', () async {
      final svc = fix.makeService(withPrefs: false);
      final out = File(p.join(scratch.path, 'out.tar'));
      await svc.pack(outputPath: out.path);

      final tarBytes = out.readAsBytesSync();
      final entries = TarDecoder().decodeBytes(tarBytes).files.map((f) => f.name);
      expect(entries.any((n) => n.contains('runtime/')), isFalse,
          reason: 'runtime/ should be excluded');
      expect(entries.any((n) => n.contains('templates/cache/')), isFalse,
          reason: 'templates/cache/ should be excluded');
      expect(entries.any((n) => n.contains('asr_samples/')), isFalse,
          reason: 'asr_samples/ should be excluded');
    });

    test('pack excludes credentials/ by default', () async {
      final svc = fix.makeService(withPrefs: false);
      final out = File(p.join(scratch.path, 'out.tar'));
      await svc.pack(outputPath: out.path);

      final entries = TarDecoder().decodeBytes(out.readAsBytesSync()).files
          .map((f) => f.name)
          .toList();
      expect(entries.any((n) => n.contains('credentials/')), isFalse);
    });

    test('pack includes credentials/ when secrets=true', () async {
      final svc = fix.makeService(withPrefs: false);
      final out = File(p.join(scratch.path, 'out.tar'));
      await svc.pack(
        outputPath: out.path,
        include: const ArchiveIncludeOptions(secrets: true),
      );
      final entries = TarDecoder().decodeBytes(out.readAsBytesSync()).files
          .map((f) => f.name)
          .toList();
      expect(entries.any((n) => n.contains('credentials/foo.json')), isTrue);
    });

    test('pack includes state.json by default', () async {
      final svc = fix.makeService(withPrefs: false);
      final out = File(p.join(scratch.path, 'out.tar'));
      await svc.pack(outputPath: out.path);
      final entries = TarDecoder().decodeBytes(out.readAsBytesSync()).files
          .map((f) => f.name)
          .toList();
      expect(entries.contains('config/state.json'), isTrue);
    });

    test('pack honors include=false flags', () async {
      final svc = fix.makeService(withPrefs: false);
      final out = File(p.join(scratch.path, 'out.tar'));
      await svc.pack(
        outputPath: out.path,
        include: const ArchiveIncludeOptions(
          history: false,
          chatSessions: false,
          calendar: false,
          stateJson: false,
        ),
      );
      final entries = TarDecoder().decodeBytes(out.readAsBytesSync()).files
          .map((f) => f.name)
          .toSet();
      expect(entries.any((n) => n.contains('boards_history/')), isFalse);
      expect(entries.any((n) => n.contains('chat_sessions/')), isFalse);
      expect(entries.any((n) => n.contains('calendar_events/')), isFalse);
      expect(entries.contains('config/state.json'), isFalse);
    });

    test('manifest path_index captures workspace.path', () async {
      fix.seedPrefs();
      final svc = fix.makeService();
      final out = File(p.join(scratch.path, 'out.tar'));
      final manifest = await svc.pack(outputPath: out.path);
      final workspacePaths = manifest.pathIndex
          .where((e) => e.kind == 'workspace.path')
          .toList();
      expect(workspacePaths.length, 1);
      expect(workspacePaths.first.workspaceId, 'ws-1');
      expect(workspacePaths.first.old, endsWith('/code/api'));
    });

    test('manifest path_index captures board + panel paths', () async {
      fix.seedPrefs();
      final svc = fix.makeService();
      final out = File(p.join(scratch.path, 'out.tar'));
      final manifest = await svc.pack(outputPath: out.path);
      final kinds = manifest.pathIndex.map((e) => e.kind).toSet();
      expect(kinds.contains('board.defaultFolder'), isTrue);
      expect(kinds.contains('panel.params.rootPath'), isTrue);
      expect(kinds.contains('panel.state.workingDir'), isTrue);
    });

    test('inspect reads manifest without applying', () async {
      fix.seedPrefs();
      final svc = fix.makeService();
      final out = File(p.join(scratch.path, 'out.tar'));
      final written = await svc.pack(outputPath: out.path);
      final read = await svc.inspect(out.path);

      expect(read.schemaVersion, written.schemaVersion);
      expect(read.pathIndex.length, written.pathIndex.length);
      expect(read.sourceHome, written.sourceHome);
    });

    test('encryption round-trip preserves content', () async {
      fix.seedPrefs();
      final svc = fix.makeService();
      final out = File(p.join(scratch.path, 'encrypted.tar'));
      await svc.pack(outputPath: out.path, passphrase: 'hunter2');

      // Inspecting without passphrase should fail because file looks encrypted.
      expect(
        () => svc.inspect(out.path),
        throwsA(isA<FormatException>()),
      );

      final manifest = await svc.inspect(out.path, passphrase: 'hunter2');
      expect(manifest.contents, contains('prefs'));
    });

    test('dry-run restore reports planned changes', () async {
      fix.seedPrefs();
      final svc = fix.makeService();
      final out = File(p.join(scratch.path, 'archive.tar'));
      await svc.pack(outputPath: out.path);

      final report = await svc.restore(
        archivePath: out.path,
        dryRun: true,
      );

      expect(report.dryRun, isTrue);
      expect(report.changes, isNotEmpty);
      expect(report.changes.any((c) => c.action == 'add'), isTrue);
    });

    test('restore respects ImportOverrides to skip sections', () async {
      fix.seedPrefs();
      final svc = fix.makeService();
      final out = File(p.join(scratch.path, 'archive.tar'));
      await svc.pack(outputPath: out.path);

      final report = await svc.restore(
        archivePath: out.path,
        dryRun: true,
        overrides: const ImportOverrides(
          prefs: false,
          config: true,
          data: true,
          workspaces: false,
        ),
      );

      expect(
        report.changes.any((c) => c.root == 'prefs'),
        isFalse,
      );
      expect(
        report.changes.any((c) => c.root == 'workspaces'),
        isFalse,
      );
    });

    test('restore apply writes config + data files', () async {
      fix.seedPrefs();
      final svc = fix.makeService();
      final out = File(p.join(scratch.path, 'archive.tar'));
      await svc.pack(outputPath: out.path);

      // Reset the destination by creating a fresh scratch root.
      final destHome = Directory.systemTemp.createTempSync('yoloit_dest_');
      addTearDown(() {
        if (destHome.existsSync()) destHome.deleteSync(recursive: true);
      });
      PlatformDirs.setInstance(
        MacosPlatformDirs(homeOverride: destHome.path),
      );
      // Re-prepare empty dest dirs so writes land somewhere.
      Directory(p.join(destHome.path, '.config', 'yoloit'))
          .createSync(recursive: true);
      Directory(p.join(destHome.path, 'Library', 'Application Support', 'yoloit'))
          .createSync(recursive: true);
      Directory(p.join(destHome.path, '.yoloit')).createSync(recursive: true);
      final destSvc = UserDataArchive.withOverrides(
        roots: ArchiveRoots(
          platformDirs: PlatformDirs.instance,
          yoloitHome: p.join(destHome.path, '.yoloit'),
          sharedPrefsAvailable: false,
        ),
        sourceHome: destHome.path,
        sourceUsername: 'tester',
        sourceHostname: 'dest-host',
      );

      final report = await destSvc.restore(
        archivePath: out.path,
        dryRun: false,
      );
      expect(report.dryRun, isFalse);
      expect(File(p.join(destHome.path, '.config', 'yoloit', 'agent_configs.json'))
          .existsSync(), isTrue);
      expect(
        File(p.join(destHome.path, 'Library', 'Application Support', 'yoloit',
            'boards_history', 'board-1.json')).existsSync(),
        isTrue,
      );
    });

    test('path_rewrite auto replaces source home', () async {
      fix.seedPrefs();
      final srcSvc = fix.makeService();
      final out = File(p.join(scratch.path, 'archive.tar'));
      final manifest = await srcSvc.pack(outputPath: out.path);
      expect(manifest.pathIndex, isNotEmpty);

      // Switch to a different home so auto rewrite has work to do.
      final destHome = Directory.systemTemp.createTempSync('yoloit_dest_');
      addTearDown(() {
        if (destHome.existsSync()) destHome.deleteSync(recursive: true);
      });
      PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: destHome.path));
      // Create the destination directory tree so the rewritten path resolves.
      Directory(p.join(destHome.path, 'code', 'api'))
          .createSync(recursive: true);
      final destSvc = UserDataArchive.withOverrides(
        roots: ArchiveRoots(
          platformDirs: PlatformDirs.instance,
          yoloitHome: p.join(destHome.path, '.yoloit'),
          sharedPrefsAvailable: false,
        ),
        sourceHome: destHome.path,
        sourceUsername: 'tester',
      );

      final report = await destSvc.restore(
        archivePath: out.path,
        dryRun: true,
      );

      // No missing-path warnings because the rewritten dir exists.
      expect(report.missing, isEmpty,
          reason: 'auto-rewrite should land on an existing dir');
    });

    test('board conflict detected when destination has same id', () async {
      fix.seedPrefs();
      final svc = fix.makeService();
      final out = File(p.join(scratch.path, 'archive.tar'));
      await svc.pack(outputPath: out.path);

      // Same fixture, same SharedPreferences state → conflict.
      final report = await svc.restore(
        archivePath: out.path,
        dryRun: true,
      );
      expect(report.conflicts.length, 1);
      expect(report.conflicts.first.boardId, 'board-1');
    });

    test('board conflict resolved via onConflict callback', () async {
      fix.seedPrefs();
      final svc = fix.makeService();
      final out = File(p.join(scratch.path, 'archive.tar'));
      await svc.pack(outputPath: out.path);

      final report = await svc.restore(
        archivePath: out.path,
        dryRun: false,
        onConflict: (c) async => BoardConflictChoice.overwrite,
      );
      expect(report.conflicts.length, 1);
      expect(report.dryRun, isFalse);
    });

    test('missing-path warning when rewritten path absent', () async {
      fix.seedPrefs();
      final svc = fix.makeService();
      final out = File(p.join(scratch.path, 'archive.tar'));
      await svc.pack(outputPath: out.path);

      // Switch to a different home so rewrites point to non-existent dirs.
      final otherHome = Directory.systemTemp.createTempSync('yoloit_other_');
      addTearDown(() {
        if (otherHome.existsSync()) otherHome.deleteSync(recursive: true);
      });
      PlatformDirs.setInstance(
        MacosPlatformDirs(homeOverride: otherHome.path),
      );
      final otherSvc = UserDataArchive.withOverrides(
        roots: ArchiveRoots(
          platformDirs: PlatformDirs.instance,
          yoloitHome: p.join(otherHome.path, '.yoloit'),
          sharedPrefsAvailable: false,
        ),
        sourceHome: otherHome.path,
        sourceUsername: 'tester',
        sourceHostname: 'other-host',
      );
      final report = await otherSvc.restore(
        archivePath: out.path,
        dryRun: true,
      );
      expect(report.missing, isNotEmpty);
      expect(
        report.missing.every((m) => m.rewritten.startsWith(otherHome.path)),
        isTrue,
      );
    });
  });

  group('ArchiveManifest JSON round-trip', () {
    test('preserves all fields', () {
      final original = ArchiveManifest(
        schemaVersion: 1,
        createdAt: DateTime.utc(2026, 8, 20, 18, 10, 24),
        sourceAppVersion: '1.0.56',
        sourceHostname: 'host',
        sourceHome: '/Users/tester',
        sourceUsername: 'tester',
        contents: const ['prefs', 'config'],
        flags: const {'secrets': false},
        pathIndex: const [
          PathIndexEntry(
            kind: 'board.defaultFolder',
            boardId: 'board-1',
            old: '/Users/tester/code/api',
          ),
        ],
      );

      final json = original.toJson();
      final restored = ArchiveManifest.fromJson(json);

      expect(restored.schemaVersion, original.schemaVersion);
      expect(restored.pathIndex.length, 1);
      expect(restored.pathIndex.first.kind, 'board.defaultFolder');
      expect(restored.pathIndex.first.boardId, 'board-1');
    });
  });
}
