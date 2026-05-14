import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';

class AiModelsSection extends StatefulWidget {
  const AiModelsSection({super.key});

  @override
  State<AiModelsSection> createState() => _AiModelsSectionState();
}

class _AiModelsSectionState extends State<AiModelsSection> {
  final _service = LocalAiModelsService.instance;
  StreamSubscription<void>? _changesSub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _changesSub = _service.changes.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_service.initialize());
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Model action failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModelCard(
          icon: Icons.psychology,
          title: 'Local Chat Model (YoLo Chat)',
          options: _service.chatModels,
          selectedModelId: _service.selectedChatModelId,
          onModelChanged:
              (id) => _runAction(() => _service.setSelectedChatModel(id)),
          stateForModel: _service.stateForModel,
          onDownloadOrUpdate:
              (id) => _runAction(() => _service.downloadOrUpdateModel(id)),
          onDelete: (id) => _runAction(() => _service.deleteInstalledModel(id)),
          onResume: (id) => _runAction(() => _service.resumeModelDownload(id)),
          disabled: _busy,
        ),
        const SizedBox(height: 16),
        _ModelCard(
          icon: Icons.mic,
          title: 'ASR Model (Microphone)',
          options: _service.asrModels,
          selectedModelId: _service.selectedAsrModelId,
          onModelChanged:
              (id) => _runAction(() => _service.setSelectedAsrModel(id)),
          stateForModel: _service.stateForModel,
          onDownloadOrUpdate:
              (id) => _runAction(() => _service.downloadOrUpdateModel(id)),
          onDelete: (id) => _runAction(() => _service.deleteInstalledModel(id)),
          onResume: (id) => _runAction(() => _service.resumeModelDownload(id)),
          disabled: _busy,
        ),
      ],
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.icon,
    required this.title,
    required this.options,
    required this.selectedModelId,
    required this.onModelChanged,
    required this.stateForModel,
    required this.onDownloadOrUpdate,
    required this.onDelete,
    required this.onResume,
    required this.disabled,
  });

  final IconData icon;
  final String title;
  final List<LocalAiModelDefinition> options;
  final String selectedModelId;
  final ValueChanged<String> onModelChanged;
  final LocalAiModelState Function(String modelId) stateForModel;
  final ValueChanged<String> onDownloadOrUpdate;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onResume;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selected = options.firstWhere(
      (m) => m.id == selectedModelId,
      orElse: () => options.first,
    );
    final state = stateForModel(selected.id);
    final status = _statusFor(state.status);

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
                  onChanged:
                      disabled
                          ? null
                          : (v) {
                            if (v != null) onModelChanged(v);
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed:
                      disabled || status.$3
                          ? null
                          : () {
                            if (state.canResume) {
                              onResume(selected.id);
                            } else {
                              onDownloadOrUpdate(selected.id);
                            }
                          },
                  child: Text(status.$1),
                ),
              ),
              if (status.$2) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: disabled ? null : () => onDelete(selected.id),
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

  /// (primaryLabel, showDelete, primaryDisabled)
  (String, bool, bool) _statusFor(LocalAiModelStatus status) {
    return switch (status) {
      LocalAiModelStatus.notDownloaded => ('Download', false, false),
      LocalAiModelStatus.downloading => ('Downloading…', false, true),
      LocalAiModelStatus.ready => ('Update', true, false),
      LocalAiModelStatus.failed => ('Resume', false, false),
    };
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
