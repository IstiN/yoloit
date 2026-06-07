import 'package:flutter/material.dart';
import 'package:yoloit/core/services/app_logger.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/settings/ui/dialogs/log_viewer_dialog.dart';
import 'package:yoloit/features/settings/ui/sections/toggle_row.dart';
import 'package:yoloit/features/settings/ui/sections/workspace_storage_row.dart';
import 'package:yoloit/features/terminal/data/logging_service.dart';
import 'package:yoloit/features/terminal/data/tmux_service.dart';

class SessionSettings extends StatefulWidget {
  const SessionSettings({super.key});

  @override
  State<SessionSettings> createState() => SessionSettingsState();
}

class SessionSettingsState extends State<SessionSettings> {
  final _tmux = TmuxService.instance;
  final _logging = LoggingService.instance;

  bool _loggingOn = false;
  bool _tmuxOn = false;
  bool _showLogs = false;
  List<LogFile> _logs = [];
  bool _logsLoading = false;

  bool _appLoggingOn = false;
  bool _showAppLog = false;
  String _appLogContent = '';
  bool _appLogLoading = false;

  @override
  void initState() {
    super.initState();
    _loggingOn = _logging.enabled;
    _tmuxOn = _tmux.enabled;
    _appLoggingOn = AppLogger.instance.enabled;
  }

  Future<void> _loadLogs() async {
    setState(() => _logsLoading = true);
    final logs = await _logging.listLogs();
    if (mounted) {
      setState(() {
        _logs = logs;
        _logsLoading = false;
      });
    }
  }

  Future<void> _deleteLog(String path) async {
    await _logging.deleteLog(path);
    await _loadLogs();
  }

  Future<void> _clearAll() async {
    await _logging.clearAll();
    await _loadLogs();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tmux toggle
          ToggleRow(
            icon: Icons.terminal,
            title: 'Keep sessions alive after closing app',
            subtitle:
                _tmux.available
                    ? 'Uses tmux — sessions survive app restart'
                    : 'Requires tmux — install with: brew install tmux',
            value: _tmuxOn && _tmux.available,
            enabled: _tmux.available,
            onChanged: (v) async {
              await _tmux.setEnabled(v);
              if (mounted) setState(() => _tmuxOn = v);
            },
          ),
          Divider(height: 1, color: colors.border),
          // Terminal logging toggle
          ToggleRow(
            icon: Icons.description_outlined,
            title: 'Log terminal output to files',
            subtitle: 'Saved to ~/.yoloit/logs/',
            value: _loggingOn,
            onChanged: (v) async {
              await _logging.setEnabled(v);
              if (mounted) {
                setState(() {
                  _loggingOn = v;
                  if (!v) _showLogs = false;
                });
              }
            },
          ),
          // Terminal logs viewer
          if (_loggingOn) ...[
            Divider(height: 1, color: colors.border),
            InkWell(
              onTap: () {
                setState(() => _showLogs = !_showLogs);
                if (!_showLogs) return;
                _loadLogs();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      _showLogs ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: context.appColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'View log files',
                      style: TextStyle(color: colors.primary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            if (_showLogs) _buildLogsSection(context),
          ],
          // App diagnostics logging
          Divider(height: 1, color: colors.border),
          ToggleRow(
            icon: Icons.bug_report_outlined,
            title: 'Log app diagnostics to file',
            subtitle:
                'Saved to ~/Library/Logs/yoloit/app.log (max 5 MB, rotates)',
            value: _appLoggingOn,
            onChanged: (v) async {
              await AppLogger.instance.setEnabled(v);
              if (mounted) {
                setState(() {
                  _appLoggingOn = v;
                  if (!v) _showAppLog = false;
                });
              }
            },
          ),
          if (_appLoggingOn) ...[
            Divider(height: 1, color: colors.border),
            InkWell(
              onTap: () {
                setState(() => _showAppLog = !_showAppLog);
                if (_showAppLog) _loadAppLog();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      _showAppLog ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: context.appColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'View app log',
                      style: TextStyle(color: colors.primary, fontSize: 13),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        await AppLogger.instance.clearLog();
                        if (_showAppLog) _loadAppLog();
                      },
                      child: const Text(
                        'Clear',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showAppLog) _buildAppLogSection(context),
          ],
          Divider(height: 1, color: colors.border),
          const WorkspaceStorageRow(),
        ],
      ),
    );
  }

  Future<void> _loadAppLog() async {
    setState(() => _appLogLoading = true);
    final content = await AppLogger.instance.readLog();
    if (mounted) {
      setState(() {
        _appLogContent = content;
        _appLogLoading = false;
      });
    }
  }

  Widget _borderedSection(BuildContext context, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.appColors.border)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildAppLogSection(BuildContext context) {
    return _borderedSection(
      context,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '~/.config/yoloit/app.log',
                style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                await AppLogger.instance.clearLog();
                _loadAppLog();
              },
              child: const Text('Clear', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
          if (_appLogLoading)
            const Center(child: CircularProgressIndicator())
          else
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.border),
              ),
              child: SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  _appLogContent,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: context.appColors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogsSection(BuildContext context) {
    return _borderedSection(
      context,
      children: [
        Row(
          children: [
            Text(
              '${_logs.length} file(s)',
              style: TextStyle(
                color: context.appColors.textMuted,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            if (_logs.isNotEmpty)
              TextButton(
                onPressed: _clearAll,
                child: const Text(
                  'Clear all',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: _loadLogs,
                tooltip: 'Refresh',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: context.appColors.textMuted,
              ),
            ],
          ),
          if (_logsLoading)
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No logs yet.',
                style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 12,
                ),
              ),
            )
          else
            ...(_logs
                .take(10)
                .map(
                  (log) => LogRow(
                    log: log,
                    onDelete: () => _deleteLog(log.path),
                    onView: () => _showLogContent(context, log),
                  ),
                )),
        ],
      ),
    );
  }

  void _showLogContent(BuildContext context, LogFile log) {
    final colors = context.appColors;
    showDialog<void>(
      context: context,
      builder:
          (_) => Dialog(
            backgroundColor: colors.surface,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 40,
              vertical: 40,
            ),
            child: LogViewerDialog(log: log),
          ),
    );
  }
}
