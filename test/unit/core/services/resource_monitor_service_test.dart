import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';

void main() {
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
}
