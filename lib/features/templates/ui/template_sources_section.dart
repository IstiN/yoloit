import 'package:flutter/material.dart';
import 'package:yoloit/features/templates/data/template_sources_service.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

/// Settings section for managing board template sources.
class TemplateSourcesSection extends StatefulWidget {
  const TemplateSourcesSection({super.key});

  @override
  State<TemplateSourcesSection> createState() => _TemplateSourcesSectionState();
}

class _TemplateSourcesSectionState extends State<TemplateSourcesSection> {
  List<TemplateSource> _sources = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sources = await TemplateSourcesService.instance.loadAll();
    if (mounted) {
      setState(() {
        _sources = sources;
        _isLoading = false;
      });
    }
  }

  Future<void> _save(List<TemplateSource> sources) async {
    await TemplateSourcesService.instance.saveAll(sources);
    if (mounted) setState(() => _sources = sources);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Template Sources',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Templates are loaded from local folders or GitHub repositories. '
          'The default source points to the IstiN/yoloit repository at yoloit/templates.',
          style: TextStyle(
            fontSize: 12,
            color: colors.onSurface.withAlpha(160),
          ),
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else
          ..._sources.map((source) => _SourceCard(
            source: source,
            onToggle: (enabled) => _toggle(source, enabled),
            onDelete: source.id == TemplateSourcesService.instance.defaultSource.id
                ? null
                : () => _delete(source),
          )),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _showAddDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('Add source'),
        ),
      ],
    );
  }

  Future<void> _toggle(TemplateSource source, bool enabled) async {
    final updated = _sources.map((s) {
      if (s.id == source.id) return s.copyWith(enabled: enabled);
      return s;
    }).toList();
    await _save(updated);
  }

  Future<void> _delete(TemplateSource source) async {
    final updated = _sources.where((s) => s.id != source.id).toList();
    await _save(updated);
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final result = await showDialog<TemplateSource>(
      context: context,
      builder: (_) => const _AddSourceDialog(),
    );
    if (result != null) {
      await TemplateSourcesService.instance.addOrUpdate(result);
      await _load();
    }
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.onToggle,
    required this.onDelete,
  });

  final TemplateSource source;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: ${source.id}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurface.withAlpha(140),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: source.enabled,
              onChanged: onToggle,
            ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog();

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  var _type = TemplateSourceType.local;
  final _idController = TextEditingController();
  final _pathController = TextEditingController();
  final _ownerController = TextEditingController();
  final _repoController = TextEditingController();
  final _branchController = TextEditingController(text: 'main');

  @override
  void dispose() {
    _idController.dispose();
    _pathController.dispose();
    _ownerController.dispose();
    _repoController.dispose();
    _branchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add template source'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<TemplateSourceType>(
              segments: const [
                ButtonSegment(
                  value: TemplateSourceType.local,
                  label: Text('Local'),
                ),
                ButtonSegment(
                  value: TemplateSourceType.github,
                  label: Text('GitHub'),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selected) {
                if (selected.isNotEmpty) {
                  setState(() => _type = selected.first);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _idController,
              decoration: const InputDecoration(
                labelText: 'Source ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_type == TemplateSourceType.local)
              TextField(
                controller: _pathController,
                decoration: const InputDecoration(
                  labelText: 'Local folder path',
                  border: OutlineInputBorder(),
                ),
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _ownerController,
                    decoration: const InputDecoration(
                      labelText: 'GitHub owner',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _repoController,
                    decoration: const InputDecoration(
                      labelText: 'Repository',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _branchController,
                    decoration: const InputDecoration(
                      labelText: 'Branch',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _save(context),
          child: const Text('Add'),
        ),
      ],
    );
  }

  void _save(BuildContext context) {
    final id = _idController.text.trim();
    if (id.isEmpty) return;
    final source = switch (_type) {
      TemplateSourceType.local => TemplateSource(
        id: id,
        type: TemplateSourceType.local,
        localPath: _pathController.text.trim(),
      ),
      TemplateSourceType.github => TemplateSource(
        id: id,
        type: TemplateSourceType.github,
        githubOwner: _ownerController.text.trim(),
        githubRepo: _repoController.text.trim(),
        githubBranch: _branchController.text.trim(),
      ),
    };
    Navigator.of(context).pop(source);
  }
}
