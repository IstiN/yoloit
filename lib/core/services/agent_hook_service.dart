import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';

/// A single hook event emitted from a workspace's hook script.
class HookEvent {
  const HookEvent({
    required this.event,
    required this.workspacePath,
    required this.workspaceHash,
    this.tool,
    required this.timestamp,
  });

  /// The hook event name (e.g. "preToolUse", "sessionEnd").
  final String event;

  /// The workspace CWD (from the JSON "cwd" field).
  final String workspacePath;

  /// The short hash derived from [workspacePath] — same as the filename key.
  final String workspaceHash;

  /// Tool name for preToolUse / postToolUse events.
  final String? tool;

  /// Unix epoch milliseconds.
  final int timestamp;

  /// Typed phase for this event — null means "clear / return to idle".
  ///
  /// - [ThinkingPhase]  → userPromptSubmitted
  /// - [ToolPhase]      → preToolUse
  /// - null             → postToolUse (back to running, clear phase)
  /// - [DonePhase]      → sessionEnd
  /// - [ErrorPhase]     → errorOccurred
  /// - null             → sessionStart (already tracked by AgentStatus.live)
  AgentPhase? get phase {
    switch (event) {
      case 'sessionStart':
        return null; // AgentStatus.live handles this; don't override hook phase
      case 'userPromptSubmitted':
        return const ThinkingPhase();
      case 'preToolUse':
        return ToolPhase(tool ?? 'unknown');
      case 'postToolUse':
        return null; // clear phase — agent finished a tool, back to thinking
      case 'sessionEnd':
        return const DonePhase();
      case 'errorOccurred':
        return const ErrorPhase();
      default:
        return null;
    }
  }

  @override
  String toString() =>
      'HookEvent($event, ws=$workspacePath, tool=$tool, ts=$timestamp)';
}

/// Polls `~/.yoloit/hooks/` every [pollInterval] and emits [HookEvent]s.
///
/// Each workspace that has the YoLoIT hook script installed writes a small
/// JSON file keyed by a hash of its CWD path.  This service reads those
/// files and broadcasts events so the UI can update node animations.
class AgentHookService {
  AgentHookService({this.pollInterval = const Duration(seconds: 2)});

  final Duration pollInterval;

  static AgentHookService? _instance;
  static AgentHookService get instance =>
      _instance ??= AgentHookService();

  final _controller = StreamController<HookEvent>.broadcast();

  /// Stream of hook events as they arrive from workspace hook scripts.
  Stream<HookEvent> get events => _controller.stream;

  Timer? _timer;

  static String get _homeDir =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';

  Directory get _hooksDir => Directory('${_homeDir}/.yoloit/hooks');

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => _poll());
    _poll(); // immediate first poll
    debugPrint('[HookService] started polling ${_hooksDir.path}');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    debugPrint('[HookService] stopped');
  }

  Future<void> _poll() async {
    final dir = _hooksDir;
    if (!await dir.exists()) return;

    try {
      // Collect all event files, sort by timestamp embedded in filename.
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.endsWith('.json') || name.contains('.tmp')) continue;
        files.add(entity);
      }

      // Sort by filename so earlier events (lower ts in name) are processed first.
      files.sort((a, b) => a.path.compareTo(b.path));

      for (final file in files) {
        await _processFile(file);
      }
    } catch (e) {
      debugPrint('[HookService] poll error: $e');
    }
  }

  Future<void> _processFile(File file) async {
    try {
      final raw = await file.readAsString();
      // Delete immediately after reading to avoid re-processing on next poll.
      await file.delete();

      final Map<String, dynamic> json =
          jsonDecode(raw) as Map<String, dynamic>;

      final event = json['event'] as String? ?? 'unknown';
      final cwd = json['cwd'] as String? ?? '';
      final tool = json['tool'] as String?;
      final ts = (json['ts'] as num?)?.toInt() ?? 0;
      final cwdHash = json['cwdHash'] as String? ?? '';

      debugPrint('[HookService] NEW EVENT: $event  cwd=$cwd  tool=$tool  ts=$ts');

      _controller.add(HookEvent(
        event: event,
        workspacePath: cwd,
        workspaceHash: cwdHash,
        tool: tool,
        timestamp: ts,
      ));
    } catch (e) {
      debugPrint('[HookService] processFile error for $file: $e');
    }
  }

  /// Installs the YoLoIT hooks into [workspacePath] using symlinks.
  ///
  /// Strategy:
  /// 1. Write the canonical script once to `~/.yoloit/bin/yoloit-hook.sh`.
  /// 2. Create `.github/hooks/` in the workspace.
  /// 3. Symlink `yoloit-hook.sh` and `hooks.json` → canonical files.
  ///
  /// Updating the binary automatically updates ALL workspaces at once — no
  /// need to revisit each workspace on every YoLoIT release.
  static Future<void> installHooks(String workspacePath) async {
    final home = _homeDir;
    final binDir = Directory('$home/.yoloit/bin');
    await binDir.create(recursive: true);

    // Write canonical files (idempotent — only writes when content differs).
    final canonicalScript = File('${binDir.path}/yoloit-hook.sh');
    await _writeIfChanged(canonicalScript, _hookScriptContent);
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['+x', canonicalScript.path]);
      } catch (_) {}
    }

    final canonicalJson = File('${binDir.path}/hooks.json');
    await _writeIfChanged(canonicalJson, _hooksJsonContent);

    // Create .github/hooks/ in the workspace.
    final hooksDir = Directory('$workspacePath/.github/hooks');
    await hooksDir.create(recursive: true);

    // Symlink workspace files → canonical files.
    await _symlinkIfNeeded(
      link: '${hooksDir.path}/yoloit-hook.sh',
      target: canonicalScript.path,
      makeExecutable: true,
    );
    await _symlinkIfNeeded(
      link: '${hooksDir.path}/hooks.json',
      target: canonicalJson.path,
    );
  }

  static Future<void> _symlinkIfNeeded({
    required String link,
    required String target,
    bool makeExecutable = false,
  }) async {
    try {
      if (Platform.isWindows) {
        // Symlinks require Developer Mode on Windows; copy the file instead.
        // Note: copied files are NOT auto-updated when the canonical file changes.
        // To enable true symlinks, turn on Developer Mode in Windows Settings →
        // System → For developers.
        final plain = File(link);
        if (await plain.exists()) {
          final existing = await plain.readAsString();
          final canonical = await File(target).readAsString();
          if (existing == canonical) return; // already up to date
          await plain.delete();
        }
        await File(target).copy(link);
        return;
      }
      final linkFile = Link(link);
      if (await linkFile.exists()) {
        final current = await linkFile.target();
        if (current == target) return; // already correct
        await linkFile.delete();
      } else {
        // Remove any plain file that might be there from the old copy approach.
        final plain = File(link);
        if (await plain.exists()) await plain.delete();
      }
      await linkFile.create(target);
      if (makeExecutable) {
        await Process.run('chmod', ['+x', link]);
      }
    } catch (_) {}
  }

  static Future<void> _writeIfChanged(File file, String content) async {
    try {
      if (await file.exists()) {
        final existing = await file.readAsString();
        if (existing == content) return;
      }
      await file.writeAsString(content);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Embedded hook file contents (written to each workspace on session start).
  // ---------------------------------------------------------------------------

  static const String _hooksJsonContent = r'''{
  "version": 1,
  "hooks": {
    "sessionStart": [
      { "type": "command", "bash": ".github/hooks/yoloit-hook.sh sessionStart", "cwd": ".", "timeoutSec": 5 }
    ],
    "sessionEnd": [
      { "type": "command", "bash": ".github/hooks/yoloit-hook.sh sessionEnd", "cwd": ".", "timeoutSec": 10 }
    ],
    "userPromptSubmitted": [
      { "type": "command", "bash": ".github/hooks/yoloit-hook.sh userPromptSubmitted", "cwd": ".", "timeoutSec": 5 }
    ],
    "preToolUse": [
      { "type": "command", "bash": ".github/hooks/yoloit-hook.sh preToolUse", "cwd": ".", "timeoutSec": 5 }
    ],
    "postToolUse": [
      { "type": "command", "bash": ".github/hooks/yoloit-hook.sh postToolUse", "cwd": ".", "timeoutSec": 5 }
    ],
    "errorOccurred": [
      { "type": "command", "bash": ".github/hooks/yoloit-hook.sh errorOccurred", "cwd": ".", "timeoutSec": 5 }
    ]
  }
}
''';

  static const String _hookScriptContent =
      r'''#!/usr/bin/env bash
# YoLoIT Agent Hook — universal (macOS / Linux).
# Writes a compact JSON status file to ~/.yoloit/hooks/ so the
# YoLoIT desktop app can update node animations / play sounds.
set -euo pipefail

EVENT="${1:-unknown}"

INPUT=""
if [ ! -t 0 ]; then
  INPUT=$(cat 2>/dev/null || echo "{}")
else
  INPUT="{}"
fi

CWD="$(pwd)"

if command -v shasum >/dev/null 2>&1; then
  CWD_HASH=$(printf '%s' "$CWD" | shasum -a 256 | cut -c1-16)
elif command -v sha256sum >/dev/null 2>&1; then
  CWD_HASH=$(printf '%s' "$CWD" | sha256sum | cut -c1-16)
else
  CWD_HASH=$(printf '%s' "$CWD" | tr '/' '_' | tr -dc 'a-zA-Z0-9_-' | tail -c 16)
fi

HOOKS_DIR="${HOME}/.yoloit/hooks"
mkdir -p "$HOOKS_DIR"

extract_field() {
  printf '%s' "$INPUT" | grep -o "\"${1}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | \
    sed 's/.*"[^"]*"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//' | head -1 2>/dev/null || true
}

TOOL_NAME=$(extract_field "toolName")
TIMESTAMP=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || printf '%s000' "$(date +%s)")

# Each event gets its own file: {cwdHash}_{timestamp}_{event}.json
# This ensures rapid back-to-back events (e.g. userPromptSubmitted + sessionStart)
# are never overwritten before Flutter reads them.
STATUS_FILE="${HOOKS_DIR}/${CWD_HASH}_${TIMESTAMP}_${EVENT}.json"

# Debug log
printf '[%s] EVENT=%s CWD=%s\n' "$(date '+%H:%M:%S')" "$EVENT" "$CWD" >> "${HOOKS_DIR}/debug.log" 2>/dev/null || true

STATUS_JSON="{\"event\":\"${EVENT}\",\"cwd\":\"${CWD}\",\"cwdHash\":\"${CWD_HASH}\",\"ts\":${TIMESTAMP}"
[ -n "$TOOL_NAME" ] && STATUS_JSON="${STATUS_JSON},\"tool\":\"${TOOL_NAME}\""
STATUS_JSON="${STATUS_JSON}}"

TMP_FILE="${STATUS_FILE}.tmp.$$"
printf '%s\n' "$STATUS_JSON" > "$TMP_FILE"
mv -f "$TMP_FILE" "$STATUS_FILE"

REASON=$(extract_field "reason")
case "$EVENT" in
  sessionEnd)
    # Play sound only for non-interactive exits (one-shot mode = "complete").
    # In interactive mode, reason is "user_exit" — sound plays via PTY detection.
    if [ "$REASON" = "complete" ]; then
      [ "$(uname)" = "Darwin" ] && afplay "/System/Library/Sounds/Glass.aiff" 2>/dev/null &
    fi
    ;;
  errorOccurred)
    [ "$(uname)" = "Darwin" ] && afplay "/System/Library/Sounds/Basso.aiff" 2>/dev/null &
    ;;
esac

exit 0
''';
}
