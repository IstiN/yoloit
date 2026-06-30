import 'dart:io';

import 'package:yoloit/core/services/resource_monitor_service.dart';

/// Board/panel counts shown in the resource monitor panel.
class ResourceBoardSummary {
  const ResourceBoardSummary({
    required this.boardCount,
    required this.totalPanels,
    required this.activeBoardPanels,
    this.activeBoardName,
    this.panelTypeCounts = const {},
  });

  final int boardCount;
  final int totalPanels;
  final int activeBoardPanels;
  final String? activeBoardName;
  final Map<String, int> panelTypeCounts;
}

/// Plain-text diagnostic report for sharing with developers.
String formatResourceUsageReport({
  required ResourceSnapshot snapshot,
  required ResourceMonitorScope scope,
  required List<SessionStat> registeredSessions,
  required List<SessionStat> agentSessions,
  ResourceBoardSummary? boards,
  String? appVersion,
  DateTime? generatedAt,
}) {
  final buffer = StringBuffer();
  final when = (generatedAt ?? DateTime.now()).toUtc();
  final host = snapshot.host;
  final ramSharePercent =
      host.totalBytes > 0
          ? (snapshot.totalMemoryBytes / host.totalBytes * 100).clamp(0.0, 100.0)
          : 0.0;

  buffer.writeln('YoLoIT Resource Usage Report');
  buffer.writeln(
    'Generated: ${when.toIso8601String()} (${when.timeZoneName})',
  );
  if (appVersion != null && appVersion.isNotEmpty) {
    buffer.writeln('App version: $appVersion');
  }
  buffer.writeln('Platform: ${Platform.operatingSystem} ${Platform.version}');
  buffer.writeln('Scope: ${scope.label}');
  if (scope == ResourceMonitorScope.yoloitOnly) {
    buffer.writeln(
      'Note: YoLoIT-only scope lists registered board terminals/chat '
      'sessions — not every OS process.',
    );
  }
  buffer.writeln();

  buffer.writeln('--- Summary ---');
  buffer.writeln(
    'CPU (tracked): ${snapshot.totalCpuPercent.toStringAsFixed(1)}%',
  );
  buffer.writeln(
    'Memory (tracked): ${formatBytes(snapshot.totalMemoryBytes)} '
    '(${ramSharePercent.toStringAsFixed(1)}% of system RAM)',
  );
  buffer.writeln(
    'App RSS: ${formatBytes(snapshot.appMemoryBytes)} '
    '(${snapshot.appCpuPercent.toStringAsFixed(1)}% CPU)',
  );
  buffer.writeln(
    'System RAM: ${formatBytes(host.usedBytes)} used / '
    '${formatBytes(host.totalBytes)} total '
    '(${host.usedPercent.toStringAsFixed(1)}%)',
  );
  buffer.writeln('Load avg (1m): ${host.loadAverage1m.toStringAsFixed(2)}');
  if (host.cpuCoreCount > 0) {
    buffer.writeln('CPU cores: ${host.cpuCoreCount}');
  }
  buffer.writeln();

  if (boards != null) {
    buffer.writeln('--- Boards & Panels ---');
    buffer.writeln('Boards: ${boards.boardCount}');
    buffer.writeln(
      'Active board: ${boards.activeBoardName ?? '(none)'} '
      '(${boards.activeBoardPanels} / ${boards.totalPanels} panels on active board)',
    );
    if (boards.panelTypeCounts.isNotEmpty) {
      buffer.writeln('Panel types on active board:');
      for (final entry in boards.panelTypeCounts.entries) {
        buffer.writeln('  ${entry.key}: ${entry.value}');
      }
    }
    buffer.writeln();
  }

  _writeSessionSection(
    buffer,
    title:
        scope == ResourceMonitorScope.yoloitOnly
            ? 'YoLoIT Processes'
            : 'Sessions',
    sessions: registeredSessions,
  );
  _writeSessionSection(
    buffer,
    title: 'Agents & Tools',
    sessions: agentSessions,
  );

  buffer.writeln('--- Notes ---');
  buffer.writeln(
    'Paste this report in a GitHub issue or send to yoloit developer support.',
  );
  buffer.writeln(
    'CPU% is per-core on macOS/Linux; values above 100% mean multi-core use.',
  );

  return buffer.toString().trimRight();
}

void _writeSessionSection(
  StringBuffer buffer, {
  required String title,
  required List<SessionStat> sessions,
}) {
  if (sessions.isEmpty) return;
  final sorted = List<SessionStat>.from(sessions)
    ..sort((a, b) {
      final byCpu = b.cpuPercent.compareTo(a.cpuPercent);
      if (byCpu != 0) return byCpu;
      return b.memoryBytes.compareTo(a.memoryBytes);
    });

  buffer.writeln('--- $title (${sorted.length}) ---');
  for (final session in sorted) {
    final meta = session.metadata;
    final label = meta?.displayLabel ?? session.label;
    buffer.writeln(
      'pid=${session.pid} '
      'cpu=${session.cpuPercent.toStringAsFixed(1)}% '
      'mem=${formatBytes(session.memoryBytes)} '
      'label="$label"',
    );
    if (meta != null) {
      final details = <String>[
        'kind=${meta.kind}',
        if (meta.boardName != null) 'board="${meta.boardName}"',
        if (meta.panelTitle != null) 'panel="${meta.panelTitle}"',
        if (meta.panelId != null) 'panelId=${meta.panelId}',
        if (meta.boardId != null) 'boardId=${meta.boardId}',
        if (meta.panelType != null) 'panelType=${meta.panelType}',
        if (meta.provider != null) 'provider=${meta.provider}',
        if (meta.workspacePath != null) 'workspace=${meta.workspacePath}',
      ];
      buffer.writeln('  ${details.join(' ')}');
    }
    if (session.sessionKey != null && session.sessionKey!.isNotEmpty) {
      buffer.writeln('  sessionKey=${session.sessionKey}');
    }
  }
  buffer.writeln();
}
