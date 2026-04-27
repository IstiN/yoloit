import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

// ── Data models ─────────────────────────────────────────────────────────────

/// Raw per-process data from a single `ps` call.
class ProcessInfo {
  const ProcessInfo({
    required this.pid,
    required this.ppid,
    required this.cpu,
    required this.memoryBytes,
  });

  final int pid;
  final int ppid;
  final double cpu;       // percent
  final int memoryBytes;  // RSS bytes
}

/// Stats for a single process — kept for backward-compatibility with UI widgets.
class ProcessStat {
  const ProcessStat({
    required this.pid,
    required this.name,
    required this.cpuPercent,
    required this.memoryBytes,
  });

  final int pid;
  final String name;
  final double cpuPercent;
  final int memoryBytes; // RSS in bytes
}

/// Aggregated stats for a registered PTY / run session.
class SessionStat {
  const SessionStat({
    required this.pid,
    required this.label,
    required this.cpuPercent,
    required this.memoryBytes,
  });

  final int pid;
  final String label;    // e.g. "copilot_session_1" or agent type
  final double cpuPercent;
  final int memoryBytes; // subtree RSS bytes
}

/// Host-level metrics collected alongside process data.
class HostMetrics {
  const HostMetrics({
    required this.totalBytes,
    required this.freeBytes,
    required this.usedBytes,
    required this.usedPercent,
    required this.cpuCoreCount,
    required this.loadAverage1m,
  });

  final int totalBytes;
  final int freeBytes;
  final int usedBytes;
  final double usedPercent;
  final int cpuCoreCount;
  final double loadAverage1m;

  static const empty = HostMetrics(
    totalBytes: 0,
    freeBytes: 0,
    usedBytes: 0,
    usedPercent: 0,
    cpuCoreCount: 0,
    loadAverage1m: 0,
  );
}

/// Aggregated snapshot emitted every poll interval.
class ResourceSnapshot {
  const ResourceSnapshot({
    required this.appMemoryBytes,
    required this.appCpuPercent,
    required this.sessions,
    required this.host,
    required this.totalMemoryBytes,
    required this.totalCpuPercent,
  });

  final int appMemoryBytes;
  final double appCpuPercent;
  final List<SessionStat> sessions;
  final HostMetrics host;
  final int totalMemoryBytes;    // app + all sessions subtrees
  final double totalCpuPercent;  // app + all sessions

  // Backward compatibility ──────────────────────────────────────────────────

  /// Unregistered agent processes discovered by name scanning.
  List<ProcessStat> get agents => sessions
      .map((s) => ProcessStat(
            pid: s.pid,
            name: s.label,
            cpuPercent: s.cpuPercent,
            memoryBytes: s.memoryBytes,
          ))
      .toList();

  int get totalSystemMemoryBytes => host.totalBytes;

  int get totalBytes => totalMemoryBytes;

  static const empty = ResourceSnapshot(
    appMemoryBytes: 0,
    appCpuPercent: 0,
    sessions: [],
    host: HostMetrics.empty,
    totalMemoryBytes: 0,
    totalCpuPercent: 0,
  );
}

// ── Service ──────────────────────────────────────────────────────────────────

/// Polls OS process information periodically to get CPU/RAM for this app,
/// registered PTY sessions, and well-known agent processes.
/// Uses `ps` on macOS/Linux and `wmic` on Windows.
class ResourceMonitorService {
  ResourceMonitorService._();
  static final instance = ResourceMonitorService._();

  static const _interactiveInterval = Duration(seconds: 2);
  static const _backgroundInterval = Duration(seconds: 15);

  static const _agentNames = [
    'copilot',
    'claude',
    'cursor-agent',
    'gemini',
    'node',
    'python',
  ];

  final _controller = StreamController<ResourceSnapshot>.broadcast();
  Timer? _timer;
  ResourceSnapshot _last = ResourceSnapshot.empty;
  bool _interactive = true;

  /// Registered PTY / run sessions: pid → label.
  final Map<int, String> _sessions = {};

  // Process-tree maps rebuilt each poll.
  Map<int, ProcessInfo> _byPid = {};
  Map<int, List<int>> _childrenOf = {};

  /// In-flight dedup: if a collection is already running, skip.
  Future<ResourceSnapshot>? _inFlight;

  Stream<ResourceSnapshot> get stream => _controller.stream;
  ResourceSnapshot get current => _last;

  /// Exposes the set of currently registered pids for UI differentiation.
  Set<int> get registeredPids => _sessions.keys.toSet();

  // ── Session registration ────────────────────────────────────────────────

  void registerSession(int pid, String label) => _sessions[pid] = label;

  void unregisterSession(int pid) => _sessions.remove(pid);

  // ── Lifecycle ───────────────────────────────────────────────────────────

  void start() {
    _timer?.cancel();
    _scheduleTimer();
    _poll();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void setInteractive(bool interactive) {
    if (_interactive == interactive) return;
    _interactive = interactive;
    _timer?.cancel();
    _scheduleTimer();
  }

  /// Manually trigger an immediate poll (e.g. from a refresh button).
  void pollNow() => _poll();

  void _scheduleTimer() {
    final interval = _interactive ? _interactiveInterval : _backgroundInterval;
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  Future<void> _poll() async {
    if (_inFlight != null) return;
    _inFlight = _collect();
    try {
      final snapshot = await _inFlight!;
      _last = snapshot;
      _controller.add(snapshot);
    } catch (_) {
      // swallow errors — stale data is fine
    } finally {
      _inFlight = null;
    }
  }

  // ── Process-tree helpers ────────────────────────────────────────────────

  /// Returns all pids in the subtree rooted at [rootPid] (inclusive).
  List<int> _getSubtreePids(int rootPid) {
    final result = <int>[];
    final queue = [rootPid];
    while (queue.isNotEmpty) {
      final p = queue.removeLast();
      result.add(p);
      final children = _childrenOf[p];
      if (children != null) queue.addAll(children);
    }
    return result;
  }

  /// Aggregates CPU and memory for the subtree rooted at [rootPid].
  ({double cpu, int mem}) _getSubtreeResources(int rootPid) {
    double cpu = 0;
    int mem = 0;
    for (final p in _getSubtreePids(rootPid)) {
      final info = _byPid[p];
      if (info != null) {
        cpu += info.cpu;
        mem += info.memoryBytes;
      }
    }
    return (cpu: math.max(0.0, cpu), mem: math.max(0, mem));
  }

  // ── Data collection ─────────────────────────────────────────────────────

  Future<ResourceSnapshot> _collect() async {
    _byPid = {};
    _childrenOf = {};

    if (Platform.isWindows) {
      await _collectProcessesWindows();
    } else {
      await _collectProcessesPosix();
    }

    // App's own subtree.
    final appPid = pid; // dart:io top-level
    final appTree = _getSubtreeResources(appPid);
    final appCpu = appTree.cpu;
    final appMem = appTree.mem;

    // Registered sessions.
    final registeredSessions = <SessionStat>[];
    final registeredPids = <int>{};
    for (final entry in _sessions.entries) {
      final sessionPid = entry.key;
      final label = entry.value;
      final res = _getSubtreeResources(sessionPid);
      registeredSessions.add(SessionStat(
        pid: sessionPid,
        label: label,
        cpuPercent: res.cpu,
        memoryBytes: res.mem,
      ));
      registeredPids.addAll(_getSubtreePids(sessionPid));
    }

    // Scan for unregistered well-known agent names.
    final agentSessions = <SessionStat>[];
    final seenPids = <int>{appPid, ...registeredPids};
    for (final entry in _byPid.entries) {
      final p = entry.key;
      if (seenPids.contains(p)) continue;
      // Name stored in a side map populated during collection.
      final name = _processNames[p] ?? '';
      if (_agentNames.any((a) => name.toLowerCase().contains(a))) {
        seenPids.add(p);
        final res = _getSubtreeResources(p);
        agentSessions.add(SessionStat(
          pid: p,
          label: name.split('/').last,
          cpuPercent: res.cpu,
          memoryBytes: res.mem,
        ));
      }
    }

    final allSessions = [...registeredSessions, ...agentSessions];
    final totalMem = allSessions.fold(appMem, (s, e) => s + e.memoryBytes);
    final totalCpu = allSessions.fold(appCpu, (s, e) => s + e.cpuPercent);
    final host = await _collectHost();

    return ResourceSnapshot(
      appMemoryBytes: appMem,
      appCpuPercent: appCpu,
      sessions: allSessions,
      host: host,
      totalMemoryBytes: math.max(0, totalMem),
      totalCpuPercent: math.max(0.0, totalCpu),
    );
  }

  /// pid → process name, populated alongside _byPid each poll cycle.
  final Map<int, String> _processNames = {};

  Future<void> _collectProcessesPosix() async {
    // Single ps call: pid ppid cpu rss.
    final psResult = await Process.run('ps', ['-eo', 'pid=,ppid=,pcpu=,rss=']);
    if (psResult.exitCode == 0) {
      for (final line in (psResult.stdout as String).split('\n')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 4) continue;
        final p = int.tryParse(parts[0]);
        final pp = int.tryParse(parts[1]);
        if (p == null || pp == null) continue;
        final cpu = math.max(0.0, double.tryParse(parts[2]) ?? 0.0);
        final rssKb = math.max(0, int.tryParse(parts[3]) ?? 0);
        _byPid[p] = ProcessInfo(pid: p, ppid: pp, cpu: cpu, memoryBytes: rssKb * 1024);
        _childrenOf.putIfAbsent(pp, () => []).add(p);
      }
    }
    // Second ps call to get process names for agent detection.
    final commResult = await Process.run('ps', ['-eo', 'pid=,comm=']);
    if (commResult.exitCode == 0) {
      for (final line in (commResult.stdout as String).split('\n')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        final p = int.tryParse(parts[0]);
        if (p == null) continue;
        _processNames[p] = parts.sublist(1).join(' ');
      }
    }
  }

  /// Populates [_byPid], [_childrenOf], and [_processNames] using wmic on Windows.
  /// CPU% is not available from wmic without sampling; reported as 0.0.
  Future<void> _collectProcessesWindows() async {
    _processNames.clear();
    try {
      // wmic process get ProcessId,ParentProcessId,Name,WorkingSetSize /format:csv
      // Output: Node,Name,ParentProcessId,ProcessId,WorkingSetSize
      final result = await Process.run(
        'wmic',
        ['process', 'get', 'ProcessId,ParentProcessId,Name,WorkingSetSize', '/format:csv'],
        runInShell: true,
      );
      if (result.exitCode != 0) return;
      final lines = (result.stdout as String).split('\n');
      // First non-empty line is the header: Node,Name,ParentProcessId,ProcessId,WorkingSetSize
      int? pidIdx, ppidIdx, nameIdx, memIdx;
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        final cols = line.split(',');
        if (pidIdx == null) {
          // Parse header
          pidIdx = cols.indexOf('ProcessId');
          ppidIdx = cols.indexOf('ParentProcessId');
          nameIdx = cols.indexOf('Name');
          memIdx = cols.indexOf('WorkingSetSize');
          continue;
        }
        if (cols.length <= math.max(pidIdx, math.max(ppidIdx ?? 0, math.max(nameIdx ?? 0, memIdx ?? 0)))) continue;
        final p = int.tryParse(cols[pidIdx].trim());
        final pp = int.tryParse(cols[ppidIdx ?? 0].trim());
        final name = nameIdx != null ? cols[nameIdx].trim() : '';
        final memBytes = math.max(0, int.tryParse(cols[memIdx ?? 0].trim()) ?? 0);
        if (p == null || pp == null) continue;
        _byPid[p] = ProcessInfo(pid: p, ppid: pp, cpu: 0.0, memoryBytes: memBytes);
        _childrenOf.putIfAbsent(pp, () => []).add(p);
        _processNames[p] = name;
      }
    } catch (_) {}
  }

  Future<HostMetrics> _collectHost() async {
    if (Platform.isWindows) {
      return _collectHostWindows();
    }
    return _collectHostPosix();
  }

  Future<HostMetrics> _collectHostPosix() async {
    try {
      final results = await Future.wait([
        Process.run('vm_stat', []),
        Process.run('sysctl', ['-n', 'hw.memsize']),
        Process.run('sysctl', ['-n', 'vm.loadavg']),
        Process.run('sysctl', ['-n', 'hw.logicalcpu']),
      ]);

      final vmOut = results[0].stdout as String;
      final freeMatch = RegExp(r'Pages free:\s+(\d+)').firstMatch(vmOut);
      final freePages = int.tryParse(freeMatch?.group(1) ?? '0') ?? 0;
      final freeBytes = math.max(0, freePages * 4096);

      final totalBytes = math.max(
        0,
        int.tryParse((results[1].stdout as String).trim()) ?? 0,
      );

      final loadOut = results[2].stdout as String;
      final loadMatch = RegExp(r'\{?\s*([\d.]+)').firstMatch(loadOut);
      final load1m = math.max(
        0.0,
        double.tryParse(loadMatch?.group(1) ?? '0') ?? 0.0,
      );

      final coreCount = math.max(
        0,
        int.tryParse((results[3].stdout as String).trim()) ?? 0,
      );

      final usedBytes = math.max(0, totalBytes - freeBytes);
      final usedPercent =
          totalBytes > 0 ? (usedBytes / totalBytes * 100).clamp(0.0, 100.0) : 0.0;

      return HostMetrics(
        totalBytes: totalBytes,
        freeBytes: freeBytes,
        usedBytes: usedBytes,
        usedPercent: usedPercent,
        cpuCoreCount: coreCount,
        loadAverage1m: load1m,
      );
    } catch (_) {
      return HostMetrics.empty;
    }
  }

  Future<HostMetrics> _collectHostWindows() async {
    try {
      // Memory: wmic OS get FreePhysicalMemory,TotalVisibleMemorySize /value  (KB)
      final memResult = await Process.run(
        'wmic',
        ['OS', 'get', 'FreePhysicalMemory,TotalVisibleMemorySize', '/value'],
        runInShell: true,
      );
      int freeKb = 0, totalKb = 0;
      if (memResult.exitCode == 0) {
        for (final line in (memResult.stdout as String).split('\n')) {
          final kv = line.trim().split('=');
          if (kv.length != 2) continue;
          final key = kv[0].trim();
          final val = int.tryParse(kv[1].trim()) ?? 0;
          if (key == 'FreePhysicalMemory') freeKb = val;
          if (key == 'TotalVisibleMemorySize') totalKb = val;
        }
      }
      final freeBytes = math.max(0, freeKb * 1024);
      final totalBytes = math.max(0, totalKb * 1024);
      final usedBytes = math.max(0, totalBytes - freeBytes);
      final usedPercent =
          totalBytes > 0 ? (usedBytes / totalBytes * 100).clamp(0.0, 100.0) : 0.0;

      // CPU load: wmic cpu get LoadPercentage /value
      final cpuResult = await Process.run(
        'wmic',
        ['cpu', 'get', 'LoadPercentage', '/value'],
        runInShell: true,
      );
      double cpuLoad = 0.0;
      if (cpuResult.exitCode == 0) {
        for (final line in (cpuResult.stdout as String).split('\n')) {
          final kv = line.trim().split('=');
          if (kv.length == 2 && kv[0].trim() == 'LoadPercentage') {
            cpuLoad = math.max(0.0, double.tryParse(kv[1].trim()) ?? 0.0);
          }
        }
      }

      // Core count: wmic cpu get NumberOfLogicalProcessors /value
      final coreResult = await Process.run(
        'wmic',
        ['cpu', 'get', 'NumberOfLogicalProcessors', '/value'],
        runInShell: true,
      );
      int coreCount = 0;
      if (coreResult.exitCode == 0) {
        for (final line in (coreResult.stdout as String).split('\n')) {
          final kv = line.trim().split('=');
          if (kv.length == 2 && kv[0].trim() == 'NumberOfLogicalProcessors') {
            coreCount = math.max(0, int.tryParse(kv[1].trim()) ?? 0);
          }
        }
      }

      return HostMetrics(
        totalBytes: totalBytes,
        freeBytes: freeBytes,
        usedBytes: usedBytes,
        usedPercent: usedPercent,
        cpuCoreCount: coreCount,
        loadAverage1m: cpuLoad, // load average not a concept on Windows; repurpose for overall CPU %
      );
    } catch (_) {
      return HostMetrics.empty;
    }
  }
}

// ── Utilities ─────────────────────────────────────────────────────────────────

/// Format bytes to human-readable string (MB / GB).
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
}

/// Clean up a session label for display.
/// Strips trailing timestamp suffixes (e.g. "copilot_1775852898220" → "Copilot").
String formatSessionLabel(String label) {
  // Remove trailing numeric timestamp suffix (13+ digits)
  final cleaned = label.replaceAll(RegExp(r'_\d{10,}$'), '');
  return cleaned
      .split(RegExp(r'[_\-]'))
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ')
      .trim();
}
