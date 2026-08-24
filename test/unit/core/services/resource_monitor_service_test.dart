import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/features/terminal/data/runtime_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('formatBytes', () {
    test('returns 0 MB for zero or negative', () {
      expect(formatBytes(0), '0 MB');
      expect(formatBytes(-1), '0 MB');
    });

    test('returns MB for values under 1 GB', () {
      expect(formatBytes(1024 * 1024), '1 MB');
      expect(formatBytes(512 * 1024 * 1024), '512 MB');
      expect(formatBytes(1023 * 1024 * 1024), '1023 MB');
    });

    test('returns GB for values >= 1 GB', () {
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
      expect(formatBytes(1536 * 1024 * 1024), '1.5 GB');
    });
  });

  group('formatSessionLabel', () {
    test('strips trailing numeric timestamp', () {
      expect(formatSessionLabel('copilot_1775852898220'), 'Copilot');
      expect(formatSessionLabel('claude_1234567890123'), 'Claude');
    });

    test('capitalizes and joins words', () {
      expect(formatSessionLabel('copilot_session'), 'Copilot Session');
      expect(formatSessionLabel('my-agent-name'), 'My Agent Name');
    });

    test('returns original if no separators', () {
      expect(formatSessionLabel('copilot'), 'Copilot');
    });

    test('handles empty string', () {
      expect(formatSessionLabel(''), '');
    });
  });

  group('formatResourceKindLabel', () {
    test('formats ai chat specially', () {
      expect(formatResourceKindLabel('ai chat'), 'AI Chat');
      expect(formatResourceKindLabel('AI CHAT'), 'AI Chat');
    });

    test('delegates to formatSessionLabel for others', () {
      expect(formatResourceKindLabel('copilot'), 'Copilot');
      expect(formatResourceKindLabel('terminal_session'), 'Terminal Session');
    });
  });

  group('ProcessInfo', () {
    test('holds pid, ppid, cpu, memoryBytes', () {
      const info = ProcessInfo(pid: 1, ppid: 0, cpu: 5.5, memoryBytes: 1024);
      expect(info.pid, 1);
      expect(info.ppid, 0);
      expect(info.cpu, 5.5);
      expect(info.memoryBytes, 1024);
    });
  });

  group('ProcessStat', () {
    test('holds pid, name, cpuPercent, memoryBytes', () {
      const stat = ProcessStat(
        pid: 1,
        name: 'test',
        cpuPercent: 10.0,
        memoryBytes: 2048,
      );
      expect(stat.pid, 1);
      expect(stat.name, 'test');
      expect(stat.cpuPercent, 10.0);
      expect(stat.memoryBytes, 2048);
    });
  });

  group('SessionStat', () {
    test('holds all fields', () {
      const meta = ResourceSessionMetadata(kind: 'test');
      const stat = SessionStat(
        pid: 1,
        label: 'l',
        cpuPercent: 1.0,
        memoryBytes: 100,
        metadata: meta,
      );
      expect(stat.pid, 1);
      expect(stat.label, 'l');
      expect(stat.cpuPercent, 1.0);
      expect(stat.memoryBytes, 100);
      expect(stat.metadata, meta);
    });
  });

  group('ResourceSessionMetadata', () {
    test('displayLabel uses panelTitle when available', () {
      const meta = ResourceSessionMetadata(
        kind: 'agent',
        panelTitle: 'My Panel',
      );
      expect(meta.displayLabel, 'Agent · My Panel');
    });

    test('displayLabel uses provider when no panelTitle', () {
      const meta = ResourceSessionMetadata(
        kind: 'ai chat',
        provider: 'copilot',
      );
      expect(meta.displayLabel, 'AI Chat · Copilot');
    });

    test('displayLabel falls back to kind', () {
      const meta = ResourceSessionMetadata(kind: 'terminal');
      expect(meta.displayLabel, 'Terminal');
    });

    test('formats ai chat kind', () {
      const meta = ResourceSessionMetadata(kind: 'ai chat');
      expect(meta.displayLabel, 'AI Chat');
    });
  });

  group('HostMetrics', () {
    test('empty has all zeros', () {
      expect(HostMetrics.empty.totalBytes, 0);
      expect(HostMetrics.empty.freeBytes, 0);
      expect(HostMetrics.empty.usedBytes, 0);
      expect(HostMetrics.empty.usedPercent, 0.0);
      expect(HostMetrics.empty.cpuCoreCount, 0);
      expect(HostMetrics.empty.loadAverage1m, 0.0);
    });
  });

  group('parseMacVmStatMemory', () {
    // Real `vm_stat` shape from Apple Silicon (16 KB pages).
    const vmStat = '''
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                                12345.
Pages active:                             500000.
Pages inactive:                           400000.
Pages speculative:                         60000.
Pages wired down:                         352228.
Pages purgeable:                           30714.
Anonymous pages:                          930714.
Pages occupied by compressor:            1379441.
File-backed pages:                        900000.
''';

    test('uses Activity Monitor formula, not total-minus-free', () {
      const total = 48 * 1024 * 1024 * 1024;
      final result = parseMacVmStatMemory(vmStat, total);
      // (930714 - 30714 + 352228 + 1379441) pages * 16384
      const expectedPages = 930714 - 30714 + 352228 + 1379441;
      expect(result.usedBytes, expectedPages * 16384);
      // ~40 GB used of 48 GB — NOT the ~100% the old formula produced.
      expect(result.usedBytes / total, closeTo(0.837, 0.01));
      expect(result.freeBytes, total - result.usedBytes);
    });

    test('honours the page size from the header', () {
      final intel = vmStat.replaceAll('16384', '4096');
      const total = 16 * 1024 * 1024 * 1024;
      final result = parseMacVmStatMemory(intel, total);
      const expectedPages = 930714 - 30714 + 352228 + 1379441;
      expect(result.usedBytes, expectedPages * 4096);
    });

    test('clamps purgeable larger than anonymous to zero', () {
      final weird = vmStat.replaceAll(
        'Anonymous pages:                          930714.',
        'Anonymous pages:                           10000.',
      );
      final result = parseMacVmStatMemory(weird, 48 * 1024 * 1024 * 1024);
      const expectedPages = 352228 + 1379441;
      expect(result.usedBytes, expectedPages * 16384);
    });

    test('missing fields fall back to zero', () {
      final result = parseMacVmStatMemory(
        'Mach Virtual Memory Statistics: (page size of 4096 bytes)\n',
        1024,
      );
      expect(result.usedBytes, 0);
      expect(result.freeBytes, 1024);
    });
  });

  group('parseLinuxMeminfo', () {
    test('uses MemAvailable, not MemFree', () {
      const meminfo = '''
MemTotal:       49152000 kB
MemFree:          500000 kB
MemAvailable:   20000000 kB
Buffers:          100000 kB
''';
      final result = parseLinuxMeminfo(meminfo);
      expect(result.totalBytes, 49152000 * 1024);
      expect(result.availableBytes, 20000000 * 1024);
    });

    test('missing keys yield zero', () {
      final result = parseLinuxMeminfo('Foo: 1 kB\n');
      expect(result.totalBytes, 0);
      expect(result.availableBytes, 0);
    });
  });

  group('ResourceSnapshot', () {
    test('empty has zero values and empty sessions', () {
      expect(ResourceSnapshot.empty.appMemoryBytes, 0);
      expect(ResourceSnapshot.empty.appCpuPercent, 0.0);
      expect(ResourceSnapshot.empty.sessions, isEmpty);
      expect(ResourceSnapshot.empty.totalMemoryBytes, 0);
      expect(ResourceSnapshot.empty.totalCpuPercent, 0.0);
    });

    test('agents maps sessions to ProcessStat', () {
      const snapshot = ResourceSnapshot(
        appMemoryBytes: 100,
        appCpuPercent: 1.0,
        sessions: [
          SessionStat(pid: 1, label: 'a', cpuPercent: 5.0, memoryBytes: 1000),
        ],
        host: HostMetrics.empty,
        totalMemoryBytes: 100,
        totalCpuPercent: 1.0,
      );
      expect(snapshot.agents.length, 1);
      expect(snapshot.agents.first.name, 'a');
      expect(snapshot.agents.first.pid, 1);
    });

    test('totalSystemMemoryBytes delegates to host', () {
      const snapshot = ResourceSnapshot(
        appMemoryBytes: 0,
        appCpuPercent: 0,
        sessions: [],
        host: HostMetrics(totalBytes: 16, freeBytes: 0, usedBytes: 0, usedPercent: 0, cpuCoreCount: 0, loadAverage1m: 0),
        totalMemoryBytes: 0,
        totalCpuPercent: 0,
      );
      expect(snapshot.totalSystemMemoryBytes, 16);
    });
  });

  group('isProcessOwnedByYoloit', () {
    test('returns true when ancestor is a yoloit root pid', () {
      final byPid = {
        100: const ProcessInfo(pid: 100, ppid: 0, cpu: 0, memoryBytes: 0),
        200: const ProcessInfo(pid: 200, ppid: 100, cpu: 0, memoryBytes: 0),
        300: const ProcessInfo(pid: 300, ppid: 200, cpu: 0, memoryBytes: 0),
      };
      expect(
        isProcessOwnedByYoloit(
          processPid: 300,
          byPid: byPid,
          rootPids: {100},
        ),
        isTrue,
      );
    });

    test('returns false for unrelated processes', () {
      final byPid = {
        500: const ProcessInfo(pid: 500, ppid: 0, cpu: 0, memoryBytes: 0),
      };
      expect(
        isProcessOwnedByYoloit(
          processPid: 500,
          byPid: byPid,
          rootPids: {100},
        ),
        isFalse,
      );
    });
  });

  group('ResourceMonitorScopeX', () {
    test('defaults to yoloit only', () {
      expect(
        ResourceMonitorScopeX.fromId(null),
        ResourceMonitorScope.yoloitOnly,
      );
    });

    test('parses all agents', () {
      expect(
        ResourceMonitorScopeX.fromId('all_agents'),
        ResourceMonitorScope.allAgents,
      );
    });
  });

  group('parseWmicKeyValues', () {
    test('parses key=value lines', () {
      final values = parseWmicKeyValues(
        '\r\nFreePhysicalMemory=1024\r\nTotalVisibleMemorySize=2048\r\n',
      );
      expect(values['FreePhysicalMemory'], '1024');
      expect(values['TotalVisibleMemorySize'], '2048');
    });

    test('skips malformed lines', () {
      final values = parseWmicKeyValues('noequals\na=b=c\nKey=1');
      expect(values, hasLength(1));
      expect(values['Key'], '1');
    });
  });

  group('parseWmicProcessCsv', () {
    test('parses header and data rows', () {
      const csv =
          'Node,Name,ParentProcessId,ProcessId,WorkingSetSize\n'
          'HOST,explorer.exe,100,200,4096\n'
          'HOST,cmd.exe,200,300,8192\n';
      final rows = parseWmicProcessCsv(csv);
      expect(rows, hasLength(2));
      expect(rows[0].pid, 200);
      expect(rows[0].ppid, 100);
      expect(rows[0].name, 'explorer.exe');
      expect(rows[0].memoryBytes, 4096);
      expect(rows[1].pid, 300);
      expect(rows[1].ppid, 200);
      expect(rows[1].name, 'cmd.exe');
    });

    test('skips empty lines, short rows, and non-numeric ids', () {
      const csv =
          'Node,Name,ParentProcessId,ProcessId,WorkingSetSize\n'
          '\n'
          'short,row\n'
          'HOST,notepad.exe,notapid,abc,1024\n';
      expect(parseWmicProcessCsv(csv), isEmpty);
    });

    test('returns empty list for empty output', () {
      expect(parseWmicProcessCsv(''), isEmpty);
    });
  });

  group('ResourceMonitorService.stopProcess', () {
    test('rejects invalid pids and the app own pid', () {
      final service = ResourceMonitorService.instance;
      expect(service.stopProcess(0), isFalse);
      expect(service.stopProcess(-5), isFalse);
      expect(service.stopProcess(pid), isFalse);
    });
  });

  group('ResourceMonitorService persisted runtime sessions', () {
    tearDown(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });

    test('returns null metadata when nothing persisted', () async {
      SharedPreferences.setMockInitialValues({});
      await ResourceMonitorService.instance.loadScopePreference();
      expect(
        ResourceMonitorService.instance.metadataForRuntimeSession('missing'),
        isNull,
      );
    });

    test('loads valid entries and skips malformed ones', () async {
      SharedPreferences.setMockInitialValues({
        'resource_runtime_sessions_v1': jsonEncode({
          'sess-ok': {
            'label': 'Copilot',
            'metadata': {'kind': 'terminal', 'boardName': 'Board A'},
          },
          'sess-no-meta': {'label': 'NoMeta'},
          'sess-bad': 'not-a-map',
        }),
      });
      await ResourceMonitorService.instance.loadScopePreference();

      final meta = ResourceMonitorService.instance.metadataForRuntimeSession(
        'sess-ok',
      );
      expect(meta, isNotNull);
      expect(meta!.kind, 'terminal');
      expect(meta.boardName, 'Board A');
      expect(
        ResourceMonitorService.instance.metadataForRuntimeSession(
          'sess-no-meta',
        ),
        isNull,
      );
      expect(
        ResourceMonitorService.instance.metadataForRuntimeSession('sess-bad'),
        isNull,
      );
      ResourceMonitorService.instance.unregisterRuntimeSession('sess-ok');
    });

    test('ignores empty, non-map, and corrupt payloads', () async {
      SharedPreferences.setMockInitialValues({
        'resource_runtime_sessions_v1': '',
      });
      await ResourceMonitorService.instance.loadScopePreference();

      SharedPreferences.setMockInitialValues({
        'resource_runtime_sessions_v1': jsonEncode(['a', 'b']),
      });
      await ResourceMonitorService.instance.loadScopePreference();

      SharedPreferences.setMockInitialValues({
        'resource_runtime_sessions_v1': '{corrupt',
      });
      await ResourceMonitorService.instance.loadScopePreference();

      expect(
        ResourceMonitorService.instance.metadataForRuntimeSession('a'),
        isNull,
      );
    });
  });

  group('ResourceMonitorService polling', () {
    setUp(() {
      // TestWidgetsFlutterBinding stubs every HttpClient request with a 400;
      // these tests need real loopback HTTP against a local server.
      HttpOverrides.global = null;
    });

    test('syncs runtime sessions over http and collects host metrics', () async {
      SharedPreferences.setMockInitialValues({});
      final service = ResourceMonitorService.instance;
      final portFile = File(RuntimePaths.portFile);
      final hadPortFile = await portFile.exists();
      final backup = hadPortFile ? await portFile.readAsString() : null;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var statusCode = 200;
      Object sessionsPayload = <dynamic>[
        {'id': 'rt-1', 'pid': pid},
        {'id': '', 'pid': 5},
        {'id': 'rt-bad-pid', 'pid': 'nope'},
        'junk',
      ];
      server.listen((request) {
        request.response
          ..statusCode = statusCode
          ..write(jsonEncode({'sessions': sessionsPayload}));
        request.response.close();
      });

      Future<ResourceSnapshot> nextSnapshot() {
        final future = service.stream.first;
        service.pollNow();
        return future.timeout(const Duration(seconds: 30));
      }

      try {
        await portFile.create(recursive: true);
        await portFile.writeAsString('${server.port}');

        service.registerRuntimeSession(
          'rt-1',
          'Runtime One',
          metadata: const ResourceSessionMetadata(kind: 'terminal'),
        );
        service.registerRuntimeShellSession(
          sessionId: 'rt-stale',
          shellPid: 999999,
          label: 'Stale',
          metadata: const ResourceSessionMetadata(kind: 'terminal'),
        );

        // Full sync: registers the live session, drops the stale one, and
        // skips malformed payload entries.
        var snapshot = await nextSnapshot();
        final rt1 = snapshot.sessions.where((s) => s.sessionKey == 'rt-1');
        expect(rt1, hasLength(1));
        expect(rt1.single.label, 'Runtime One');
        expect(rt1.single.metadata, isNotNull);
        expect(snapshot.sessions.any((s) => s.pid == 999999), isFalse);
        expect(snapshot.host.cpuCoreCount, greaterThan(0));
        expect(snapshot.host.totalBytes, greaterThan(0));
        expect(
          snapshot.totalMemoryBytes,
          greaterThanOrEqualTo(snapshot.appMemoryBytes),
        );

        // Non-200 response: fetch fails, registered session stays untouched.
        statusCode = 500;
        snapshot = await nextSnapshot();
        expect(service.registeredPids.contains(pid), isTrue);

        // Payload without a session list: treated as empty, so the previously
        // synced runtime session is unregistered as stale.
        statusCode = 200;
        sessionsPayload = <String, dynamic>{'unexpected': true};
        snapshot = await nextSnapshot();
        expect(service.registeredPids.contains(pid), isFalse);

        // Unparseable port file: treated as empty session list.
        await portFile.writeAsString('not-a-port');
        snapshot = await nextSnapshot();
        expect(snapshot.sessions.any((s) => s.sessionKey == 'rt-1'), isFalse);

        // Missing port file: treated as empty session list.
        await portFile.delete();
        snapshot = await nextSnapshot();
        expect(snapshot.appMemoryBytes, greaterThanOrEqualTo(0));

        // Unreachable daemon: fetch returns null, sync is skipped.
        final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final closedPort = closed.port;
        await closed.close();
        await portFile.writeAsString('$closedPort');
        snapshot = await nextSnapshot();
        expect(snapshot.sessions.any((s) => s.sessionKey == 'rt-1'), isFalse);
      } finally {
        await server.close(force: true);
        if (backup != null) {
          await portFile.writeAsString(backup);
        } else if (await portFile.exists()) {
          await portFile.delete();
        }
        service.unregisterRuntimeSession('rt-1');
        service.unregisterRuntimeSession('rt-stale');
        service.unregisterSession(pid);
      }
    });

    test('collects a snapshot in all-agents scope', () async {
      SharedPreferences.setMockInitialValues({});
      final service = ResourceMonitorService.instance;

      final future = service.stream.first;
      await service.setScope(ResourceMonitorScope.allAgents);
      final snapshot = await future.timeout(const Duration(seconds: 30));
      expect(snapshot.totalMemoryBytes, greaterThan(0));
      expect(snapshot.host.totalBytes, greaterThan(0));

      final back = service.stream.first;
      await service.setScope(ResourceMonitorScope.yoloitOnly);
      await back.timeout(const Duration(seconds: 30));
      expect(service.scope, ResourceMonitorScope.yoloitOnly);
    });
  });
}
