import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yoloit/core/services/user_data_archive.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/settings/data/backup_migration_service.dart';
import 'package:yoloit/ui/components/cards/settings_card.dart';

/// Settings section for backing up and restoring YoLoIT user state.
///
/// Talks to the local CLI server (CliServer is running inside the desktop
/// process) via [BackupMigrationService]. All UI actions ultimately map
/// to the `settings:export` / `settings:import` commands documented in
/// `tools/yoloit`.
/// Callback that returns the destination path chosen by the user, or
/// `null` if they cancelled. Defaults to [FilePicker.saveFile] when null.
typedef SavePathPicker = Future<String?> Function(String suggestedName);

/// Callback that returns the path to the archive the user picked, or
/// `null` if they cancelled. Defaults to [FilePicker.pickFiles] when null.
typedef ArchivePathPicker = Future<String?> Function();

class BackupMigrationSection extends StatefulWidget {
  const BackupMigrationSection({
    super.key,
    this.service,
    this.pickSavePath,
    this.pickArchivePath,
  });

  /// Optional override for tests / future DI.
  final BackupMigrationService? service;

  /// Optional override for the save-file dialog. Default uses FilePicker.
  final SavePathPicker? pickSavePath;

  /// Optional override for the open-file dialog. Default uses FilePicker.
  final ArchivePathPicker? pickArchivePath;

  @override
  State<BackupMigrationSection> createState() => _BackupMigrationSectionState();
}

class _BackupMigrationSectionState extends State<BackupMigrationSection> {
  late final BackupMigrationService _service =
      widget.service ?? BackupMigrationService();

  // Export options.
  bool _includeSecrets = false;
  bool _includeHistory = true;
  bool _includeChat = true;
  bool _includeCalendar = true;
  bool _includeStateJson = true;

  // Export flow.
  bool _exportBusy = false;
  String? _lastExportPath;
  String? _exportError;

  // Import flow.
  bool _importBusy = false;
  ImportReport? _lastImportReport;
  String? _importError;

  // Passphrase (used for both export encryption and import decryption).
  final _passphraseCtrl = TextEditingController();
  bool _showPassphrase = false;

  @override
  void dispose() {
    _service.close();
    _passphraseCtrl.dispose();
    super.dispose();
  }

  Future<void> _onExport() async {
    final picker = widget.pickSavePath ??
        (name) async => FilePicker.saveFile(
              dialogTitle: 'Save YoLoIT archive',
              fileName: name,
            );
    final suggested =
        'yoloit-${Platform.environment['HOSTNAME'] ?? 'archive'}-${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}.tar';
    final dest = await picker(suggested);
    if (dest == null || !mounted) return;
    setState(() {
      _exportBusy = true;
      _exportError = null;
    });
    try {
      final result = await _service.export(
        destinationPath: dest,
        passphrase: _passphraseCtrl.text,
        includeSecrets: _includeSecrets,
        includeHistory: _includeHistory,
        includeChatSessions: _includeChat,
        includeCalendar: _includeCalendar,
        includeStateJson: _includeStateJson,
      );
      if (!mounted) return;
      setState(() {
        _lastExportPath = result.path;
      });
      _snack(
        'Exported ${result.manifest.contents.length} sections → ${result.path}',
      );
    } on BackupMigrationUnavailableError catch (e) {
      setState(() => _exportError = e.message);
    } on Object catch (e) {
      setState(() => _exportError = '$e');
    } finally {
      if (mounted) setState(() => _exportBusy = false);
    }
  }

  Future<void> _onImport() async {
    final picker = widget.pickArchivePath ??
        () async {
          final picked = await FilePicker.pickFiles(
            dialogTitle: 'Pick YoLoIT archive',
            type: FileType.any,
          );
          return picked?.files.single.path;
        };
    final src = await picker();
    if (src == null || !mounted) return;

    setState(() {
      _importBusy = true;
      _importError = null;
    });
    try {
      // Always preview first.
      final preview = await _service.restore(
        archivePath: src,
        passphrase: _passphraseCtrl.text.isEmpty ? null : _passphraseCtrl.text,
        dryRun: true,
      );
      if (!mounted) return;

      final shouldApply = await _showImportPreview(preview.report);
      if (shouldApply != true || !mounted) {
        setState(() => _importBusy = false);
        return;
      }

      final applied = await _service.restore(
        archivePath: src,
        passphrase: _passphraseCtrl.text.isEmpty ? null : _passphraseCtrl.text,
        dryRun: false,
        onConflict: BoardConflictChoice.keepBoth,
      );
      if (!mounted) return;
      setState(() => _lastImportReport = applied.report);
      _snack(
        'Restored ${applied.report.totalChanges} files (${applied.report.totalConflicts} board conflicts resolved).',
      );
    } on BackupMigrationUnavailableError catch (e) {
      setState(() => _importError = e.message);
    } on Object catch (e) {
      setState(() => _importError = '$e');
    } finally {
      if (mounted) setState(() => _importBusy = false);
    }
  }

  Future<bool?> _showImportPreview(ImportReport report) {
    final colors = context.appColors;
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colors.surface,
          title: const Text('Restore preview'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _kv('Source', report.manifest.sourceHostname),
                  _kv('Created', report.manifest.createdAt.toLocal().toString()),
                  _kv(
                    'Sections',
                    report.manifest.contents.join(', '),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Files: ${report.changes.length} '
                    '(${report.changes.where((c) => c.action == 'overwrite').length} overwrite, '
                    '${report.changes.where((c) => c.action == 'add').length} add)',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (report.conflicts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Board conflicts: ${report.conflicts.length} '
                      '(will be kept as "Both")',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.accentOrange,
                      ),
                    ),
                  ],
                  if (report.missing.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Missing paths: ${report.missing.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.accentRed,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      report.missing
                          .take(5)
                          .map((m) => '  ${m.rewritten}')
                          .join('\n'),
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: RichText(
      text: TextSpan(
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 12,
        ),
        children: [
          TextSpan(
            text: '$k: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: v),
        ],
      ),
    ),
  );

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Move YoLoIT boards, settings and skills to another machine '
                'via a single encrypted archive.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              _buildPassphraseRow(colors),
              const SizedBox(height: 10),
              _buildIncludeFlags(colors),
              const SizedBox(height: 14),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _exportBusy ? null : _onExport,
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    label: Text(_exportBusy ? 'Exporting…' : 'Export…'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _importBusy ? null : _onImport,
                    icon: const Icon(Icons.unarchive_outlined, size: 16),
                    label: Text(_importBusy ? 'Importing…' : 'Import…'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (_exportError != null) _buildError(_exportError!),
              if (_importError != null) _buildError(_importError!),
              if (_lastExportPath != null)
                _buildInfo(
                  'Last export: $_lastExportPath',
                ),
              if (_lastImportReport != null)
                _buildInfo(
                  'Last import: ${_lastImportReport!.totalChanges} files '
                  '(${_lastImportReport!.totalConflicts} conflicts kept both)',
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPassphraseRow(AppColorScheme colors) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _passphraseCtrl,
            obscureText: !_showPassphrase,
            decoration: InputDecoration(
              labelText: 'Archive passphrase',
              hintText: 'Used for AES-GCM encryption',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassphrase ? Icons.visibility_off : Icons.visibility,
                  size: 16,
                ),
                onPressed: () =>
                    setState(() => _showPassphrase = !_showPassphrase),
              ),
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        IconButton(
          tooltip: 'Copy to clipboard',
          icon: const Icon(Icons.copy, size: 14),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _passphraseCtrl.text));
            _snack('Passphrase copied to clipboard');
          },
        ),
      ],
    );
  }

  Widget _buildIncludeFlags(AppColorScheme colors) {
    Widget toggle(String label, bool value, ValueChanged<bool> onChanged) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: colors.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 12),
        ],
      );
    }

    return Wrap(
      children: [
        toggle(
          'History',
          _includeHistory,
          (v) => setState(() => _includeHistory = v),
        ),
        toggle(
          'Chat sessions',
          _includeChat,
          (v) => setState(() => _includeChat = v),
        ),
        toggle(
          'Calendar',
          _includeCalendar,
          (v) => setState(() => _includeCalendar = v),
        ),
        toggle(
          'CLI bookmarks (state.json)',
          _includeStateJson,
          (v) => setState(() => _includeStateJson = v),
        ),
        toggle(
          'Secrets',
          _includeSecrets,
          (v) => setState(() => _includeSecrets = v),
        ),
      ],
    );
  }

  Widget _buildError(String message) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      message,
      style: const TextStyle(color: Colors.redAccent, fontSize: 11),
    ),
  );

  Widget _buildInfo(String message) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      message,
      style: const TextStyle(fontSize: 11),
    ),
  );
}
