import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';

class ProviderModelsSection extends StatefulWidget {
  const ProviderModelsSection({super.key});

  @override
  State<ProviderModelsSection> createState() => _ProviderModelsSectionState();
}

class _ProviderModelsSectionState extends State<ProviderModelsSection> {
  final _service = ProviderModelCatalogService.instance;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    await _service.load(force: true);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _addCustomModel(String providerId) async {
    final model = await showDialog<ChatModelInfo>(
      context: context,
      builder: (_) => const _AddCustomModelDialog(),
    );
    if (model == null) return;
    await _service.addCustomModel(providerId, model);
    if (mounted) setState(() {});
  }

  Future<void> _removeCustomModel(String providerId, String modelId) async {
    await _service.removeCustomModel(providerId, modelId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final catalogs = _service.allCatalogs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CatalogStatusCard(
          loading: _loading,
          loadedFromRemote: _service.loadedFromRemote,
          error: _service.loadError,
          onRefresh: _reload,
        ),
        const SizedBox(height: 16),
        if (_loading && catalogs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (catalogs.isEmpty)
          Text(
            'No provider catalogs available.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12,
            ),
          )
        else
          ...catalogs.map(
            (catalog) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ProviderCatalogCard(
                catalog: catalog,
                customModels: _service.customModelsForProvider(catalog.id),
                onAddCustomModel: () => _addCustomModel(catalog.id),
                onRemoveCustomModel: (modelId) =>
                    _removeCustomModel(catalog.id, modelId),
              ),
            ),
          ),
      ],
    );
  }
}

class _CatalogStatusCard extends StatelessWidget {
  const _CatalogStatusCard({
    required this.loading,
    required this.loadedFromRemote,
    required this.error,
    required this.onRefresh,
  });

  final bool loading;
  final bool loadedFromRemote;
  final String? error;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final (icon, label, color) = loading
        ? (Icons.sync, 'Refreshing provider catalog...', colors.primary)
        : error != null
        ? (Icons.error_outline, error!, Theme.of(context).colorScheme.error)
        : loadedFromRemote
        ? (
            Icons.check_circle_outline,
            'Loaded from GitHub',
            AppColors.neonGreen,
          )
        : (
            Icons.warning_amber_rounded,
            'Loaded from cache/asset',
            AppColors.neonOrange,
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(170)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: error != null ? color : onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: loading ? null : onRefresh,
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class _ProviderCatalogCard extends StatelessWidget {
  const _ProviderCatalogCard({
    required this.catalog,
    required this.customModels,
    required this.onAddCustomModel,
    required this.onRemoveCustomModel,
  });

  final ProviderCatalog catalog;
  final List<ChatModelInfo> customModels;
  final VoidCallback onAddCustomModel;
  final ValueChanged<String> onRemoveCustomModel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            title: Text(
              catalog.displayName,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            children: [
              _ModelGroup(
                title: 'Built-in models',
                models: catalog.models,
              ),
              const SizedBox(height: 12),
              _ModelGroup(
                title: 'Custom models',
                models: customModels,
                emptyLabel: 'No custom models yet.',
                onDelete: onRemoveCustomModel,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onAddCustomModel,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add custom model'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelGroup extends StatelessWidget {
  const _ModelGroup({
    required this.title,
    required this.models,
    this.emptyLabel = 'No models.',
    this.onDelete,
  });

  final String title;
  final List<ChatModelInfo> models;
  final String emptyLabel;
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (models.isEmpty)
          Text(emptyLabel, style: TextStyle(color: muted, fontSize: 11))
        else
          ...models.asMap().entries.map(
            (entry) => Padding(
              padding: EdgeInsets.only(bottom: entry.key == models.length - 1 ? 0 : 8),
              child: _ModelRow(
                model: entry.value,
                onDelete: onDelete,
              ),
            ),
          ),
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.model, this.onDelete});

  final ChatModelInfo model;
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.displayName,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(model.id, style: TextStyle(color: muted, fontSize: 11)),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              onPressed: () => onDelete!(model.id),
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              tooltip: 'Delete custom model',
            ),
        ],
      ),
    );
  }
}

class _AddCustomModelDialog extends StatefulWidget {
  const _AddCustomModelDialog();

  @override
  State<_AddCustomModelDialog> createState() => _AddCustomModelDialogState();
}

class _AddCustomModelDialogState extends State<_AddCustomModelDialog> {
  final _idController = TextEditingController();
  final _displayNameController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _idController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _submit() {
    final id = _idController.text.trim();
    final displayName = _displayNameController.text.trim();
    if (id.isEmpty || displayName.isEmpty) {
      setState(() => _error = 'Model ID and Display Name are required.');
      return;
    }
    Navigator.of(context).pop(
      ChatModelInfo(id: id, displayName: displayName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return AlertDialog(
      backgroundColor: colors.surfaceElevated,
      title: Text(
        'Add custom model',
        style: TextStyle(color: onSurface, fontSize: 16),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _idController,
              autofocus: true,
              style: TextStyle(color: onSurface),
              decoration: InputDecoration(
                labelText: 'Model ID',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _displayNameController,
              style: TextStyle(color: onSurface),
              decoration: InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}
