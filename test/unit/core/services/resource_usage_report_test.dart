import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/core/services/resource_usage_report.dart';

void main() {
  group('formatResourceUsageReport', () {
    test('includes summary, boards, and sorted sessions', () {
      final report = formatResourceUsageReport(
        snapshot: const ResourceSnapshot(
          appMemoryBytes: 500 * 1024 * 1024,
          appCpuPercent: 25.5,
          sessions: [],
          host: HostMetrics(
            totalBytes: 48 * 1024 * 1024 * 1024,
            freeBytes: 1 * 1024 * 1024 * 1024,
            usedBytes: 47 * 1024 * 1024 * 1024,
            usedPercent: 97.9,
            cpuCoreCount: 10,
            loadAverage1m: 6.18,
          ),
          totalMemoryBytes: 1536 * 1024 * 1024,
          totalCpuPercent: 125.3,
        ),
        scope: ResourceMonitorScope.yoloitOnly,
        registeredSessions: [
          SessionStat(
            pid: 100,
            label: 'low',
            cpuPercent: 1.0,
            memoryBytes: 50 * 1024 * 1024,
            metadata: const ResourceSessionMetadata(
              kind: 'terminal',
              boardName: 'YoLoIT',
              panelTitle: 'TrackState',
              panelId: 'p-1',
            ),
          ),
          SessionStat(
            pid: 200,
            label: 'high',
            cpuPercent: 71.5,
            memoryBytes: 573 * 1024 * 1024,
            metadata: const ResourceSessionMetadata(
              kind: 'terminal',
              boardName: 'YoLoIT',
              panelTitle: 'TrackState',
              panelId: 'p-2',
            ),
            sessionKey: 'board_terminal_200',
          ),
        ],
        agentSessions: const [
          SessionStat(
            pid: 300,
            label: 'copilot',
            cpuPercent: 4.2,
            memoryBytes: 120 * 1024 * 1024,
          ),
        ],
        boards: const ResourceBoardSummary(
          boardCount: 8,
          totalPanels: 44,
          activeBoardPanels: 8,
          activeBoardName: 'YoLoIT',
          panelTypeCounts: {'Checklist': 2, 'Terminal': 1},
        ),
        appVersion: '1.0.234',
        generatedAt: DateTime.utc(2026, 6, 27, 13, 0),
      );

      expect(report, contains('YoLoIT Resource Usage Report'));
      expect(report, contains('App version: 1.0.234'));
      expect(report, contains('Scope: YoLoIT only'));
      expect(report, contains('YoLoIT-only scope lists registered'));
      expect(report, contains('CPU (tracked): 125.3%'));
      expect(report, contains('Load avg (1m): 6.18'));
      expect(report, contains('Active board: YoLoIT (8 / 44 panels'));
      expect(report, contains('Checklist: 2'));

      final highIndex = report.indexOf('pid=200');
      final lowIndex = report.indexOf('pid=100');
      expect(highIndex, greaterThan(0));
      expect(lowIndex, greaterThan(highIndex));

      expect(report, contains('sessionKey=board_terminal_200'));
      expect(report, contains('--- Agents & Tools (1) ---'));
      expect(report, contains('pid=300'));
    });
  });
}
