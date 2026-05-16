import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_models_sdk/local_models_sdk.dart' as sdk;
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';
import 'package:yoloit/features/settings/ui/setup_guide_page.dart';

class AiModelsSection extends StatefulWidget {
  const AiModelsSection({super.key});

  @override
  State<AiModelsSection> createState() => _AiModelsSectionState();
}

class _AiModelsSectionState extends State<AiModelsSection> {
  final _service = LocalAiModelsService.instance;
  StreamSubscription<void>? _changesSub;

  @override
  void initState() {
    super.initState();
    _changesSub = _service.changes.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_service.initialize());
    unawaited(_service.refreshPrerequisites());
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Model action failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_service.isInitializing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_service.initError != null) {
      return _ErrorCard(message: _service.initError!);
    }
    final pre = _service.prerequisites;
    final modelsEnabled = pre.isReady;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PrerequisitesCard(
          status: pre,
          checking: _service.isCheckingPrerequisites,
          onRecheck: () => _runAction(_service.refreshPrerequisites),
          onInstall:
              pre.installHint == null
                  ? null
                  : () => _runAction(_service.installMissingPrerequisites),
          onOpenSetupGuide: () => SetupGuidePage.show(context),
        ),
        const SizedBox(height: 16),
        _ModelCard(
          icon: Icons.auto_awesome_rounded,
          title: 'Local Chat Model (YoLo Chat)',
          enabled: modelsEnabled,
          options: _service.chatModels,
          selectedModelId: _service.selectedChatModelId,
          onModelChanged:
              (id) => _runAction(() => _service.setSelectedChatModel(id)),
          stateForModel: _service.stateForModel,
          onDownloadOrUpdate:
              (id) => _runAction(() => _service.downloadOrUpdateModel(id)),
          onDelete: (id) => _runAction(() => _service.deleteInstalledModel(id)),
          onResume: (id) => _runAction(() => _service.resumeModelDownload(id)),
          onPause: (id) => _runAction(() => _service.pauseModelDownload(id)),
          onCancel: (id) => _runAction(() => _service.cancelModelDownload(id)),
        ),
        const SizedBox(height: 16),
        _ModelCard(
          icon: Icons.graphic_eq_rounded,
          title: 'ASR Model (Microphone)',
          enabled: modelsEnabled,
          options: _service.asrModels,
          selectedModelId: _service.selectedAsrModelId,
          onModelChanged:
              (id) => _runAction(() => _service.setSelectedAsrModel(id)),
          stateForModel: _service.stateForModel,
          onDownloadOrUpdate:
              (id) => _runAction(() => _service.downloadOrUpdateModel(id)),
          onDelete: (id) => _runAction(() => _service.deleteInstalledModel(id)),
          onResume: (id) => _runAction(() => _service.resumeModelDownload(id)),
          onPause: (id) => _runAction(() => _service.pauseModelDownload(id)),
          onCancel: (id) => _runAction(() => _service.cancelModelDownload(id)),
        ),
      ],
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.icon,
    required this.title,
    required this.enabled,
    required this.options,
    required this.selectedModelId,
    required this.onModelChanged,
    required this.stateForModel,
    required this.onDownloadOrUpdate,
    required this.onDelete,
    required this.onResume,
    required this.onPause,
    required this.onCancel,
  });

  final IconData icon;
  final String title;
  final bool enabled;
  final List<LocalAiModelDefinition> options;
  final String selectedModelId;
  final ValueChanged<String> onModelChanged;
  final LocalAiModelState Function(String modelId) stateForModel;
  final ValueChanged<String> onDownloadOrUpdate;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onResume;
  final ValueChanged<String> onPause;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selected = options.firstWhere(
      (m) => m.id == selectedModelId,
      orElse: () => options.first,
    );
    final state = stateForModel(selected.id);
    final action = _actionFor(state.status, state.canResume);

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selected.id,
                  items:
                      options
                          .map(
                            (o) => DropdownMenuItem(
                              value: o.id,
                              child: Text(o.displayName),
                            ),
                          )
                          .toList(),
                  onChanged: (v) {
                    if (enabled && v != null) onModelChanged(v);
                  },
                  dropdownColor: colors.surfaceElevated,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _StatusChip(status: state.status),
            ],
          ),
          if (state.hasTransferProgress) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              minHeight: 8,
              borderRadius: BorderRadius.circular(6),
              value: state.progress,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 6),
            Text(
              _downloadLabel(state),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(180),
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed:
                      action.$2 || !enabled
                          ? null
                          : () {
                            switch (action.$1) {
                              case 'download':
                              case 'update':
                                onDownloadOrUpdate(selected.id);
                              case 'resume':
                                onResume(selected.id);
                              default:
                                break;
                            }
                          },
                  child: Text(action.$3),
                ),
              ),
              if (state.status == LocalAiModelStatus.downloading) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: enabled ? () => onPause(selected.id) : null,
                    child: const Text('Pause'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: enabled ? () => onCancel(selected.id) : null,
                    child: const Text('Cancel'),
                  ),
                ),
              ] else if (state.status == LocalAiModelStatus.paused) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: enabled ? () => onCancel(selected.id) : null,
                    child: const Text('Cancel'),
                  ),
                ),
              ] else if (action.$4) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: enabled ? () => onDelete(selected.id) : null,
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ],
          ),
          if (state.error != null && state.error!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              state.error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// (action, disabled, label, showDelete)
  (String, bool, String, bool) _actionFor(
    LocalAiModelStatus status,
    bool canResume,
  ) {
    return switch (status) {
      LocalAiModelStatus.notDownloaded => (
        'download',
        false,
        'Download',
        false,
      ),
      LocalAiModelStatus.downloading => (
        'downloading',
        true,
        'Downloading…',
        false,
      ),
      LocalAiModelStatus.paused => ('resume', false, 'Resume', false),
      LocalAiModelStatus.ready => ('update', false, 'Update', true),
      LocalAiModelStatus.failed => (
        canResume ? 'resume' : 'download',
        false,
        canResume ? 'Resume' : 'Download',
        false,
      ),
    };
  }

  String _downloadLabel(LocalAiModelState state) {
    final progress = state.progress;
    final percent =
        progress == null ? '...' : '${(progress * 100).toStringAsFixed(1)}%';
    final downloaded = _formatBytes(state.downloadedBytes);
    final total = state.totalBytes > 0 ? _formatBytes(state.totalBytes) : '?';
    final speed =
        state.speedBytesPerSecond > 0
            ? ' • ${_formatBytes(state.speedBytesPerSecond)}/s'
            : '';
    return '$percent • $downloaded / $total$speed';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var i = 0;
    while (value >= 1024 && i < suffixes.length - 1) {
      value /= 1024;
      i++;
    }
    final fixed =
        value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '$fixed ${suffixes[i]}';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final LocalAiModelStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      LocalAiModelStatus.notDownloaded => (
        'Not Downloaded',
        AppColors.textMuted,
      ),
      LocalAiModelStatus.downloading => ('Downloading...', AppColors.neonBlue),
      LocalAiModelStatus.paused => ('Paused', Colors.amber),
      LocalAiModelStatus.ready => ('Ready', AppColors.neonGreen),
      LocalAiModelStatus.failed => (
        'Failed',
        Theme.of(context).colorScheme.error,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _PrerequisitesCard extends StatelessWidget {
  const _PrerequisitesCard({
    required this.status,
    required this.checking,
    required this.onRecheck,
    required this.onOpenSetupGuide,
    this.onInstall,
  });

  final sdk.LocalModelsPrerequisitesStatus status;
  final bool checking;
  final VoidCallback onRecheck;
  final VoidCallback onOpenSetupGuide;
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final ready = status.isReady;
    final color = ready ? AppColors.neonGreen : AppColors.neonOrange;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final message =
        status.message ??
        'Local AI model runtime prerequisites are available on this machine.';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(170)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                'Runtime prerequisites',
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: textColor, fontSize: 12)),
          if (status.installHint != null && status.installHint!.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(
              status.installHint!,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: checking ? null : onRecheck,
                child: const Text('Re-check'),
              ),
              OutlinedButton(
                onPressed: onOpenSetupGuide,
                child: const Text('Open Setup Guide'),
              ),
              if (!ready && onInstall != null)
                FilledButton(
                  onPressed: checking ? null : onInstall,
                  child: const Text('Install Prerequisite'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.error),
      ),
      padding: const EdgeInsets.all(14),
      child: Text(
        message,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 12,
        ),
      ),
    );
  }
}
