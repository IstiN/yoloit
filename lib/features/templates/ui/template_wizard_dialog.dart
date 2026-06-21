import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/services/board_offscreen_renderer.dart';
import 'package:yoloit/features/templates/bloc/templates_cubit.dart';
import 'package:yoloit/features/templates/data/template_preview_generator.dart';
import 'package:yoloit/features/templates/data/template_service.dart';
import 'package:yoloit/features/templates/model/template_models.dart';
import 'package:yoloit/features/templates/ui/template_parameter_field.dart';

/// Wizard for creating a new board from a template.
class TemplateWizardDialog extends StatefulWidget {
  const TemplateWizardDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder:
          (_) => BlocProvider(
            create: (_) => TemplatesCubit()..load(),
            child: const TemplateWizardDialog(),
          ),
    );
  }

  @override
  State<TemplateWizardDialog> createState() => _TemplateWizardDialogState();
}

class _TemplateWizardDialogState extends State<TemplateWizardDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  final _values = <String, dynamic>{};
  final _errors = <String, String>{};
  var _step = _WizardStep.select;
  var _isCreating = false;
  var _searchQuery = '';

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: colors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: BlocConsumer<TemplatesCubit, TemplatesState>(
            listener: (context, state) {
              if (state.error != null && state.error!.isNotEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(state.error!)));
              }
            },
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context, state),
                  const SizedBox(height: 16),
                  Expanded(
                    child:
                        state.isLoading && state.templates.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : _buildBody(context, state),
                  ),
                  const SizedBox(height: 16),
                  _buildActions(context, state),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, TemplatesState state) {
    final title = switch (_step) {
      _WizardStep.select => 'Choose a template',
      _WizardStep.configure => state.selectedTemplate?.name ?? 'Configure',
    };
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Close',
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, TemplatesState state) {
    return switch (_step) {
      _WizardStep.select => _buildTemplateList(context, state),
      _WizardStep.configure => _buildConfigureForm(context, state),
    };
  }

  List<BoardTemplate> _filteredTemplates(List<BoardTemplate> templates) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return templates;
    return templates.where((template) {
      final nameMatch = template.name.toLowerCase().contains(query);
      final descMatch =
          template.description?.toLowerCase().contains(query) ?? false;
      return nameMatch || descMatch;
    }).toList();
  }

  Widget _buildTemplateList(BuildContext context, TemplatesState state) {
    final templates = state.templates;
    final filtered = _filteredTemplates(templates);
    if (templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              'No templates found.\nAdd a source in Settings → Templates.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(180),
              ),
            ),
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search templates...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon:
                      _searchQuery.isNotEmpty
                          ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                          : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child:
                    filtered.isEmpty
                        ? Center(
                          child: Text(
                            'No templates match "$_searchQuery"',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withAlpha(160),
                            ),
                          ),
                        )
                        : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder:
                              (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final template = filtered[index];
                            final isSelected =
                                state.selectedTemplate?.id == template.id;
                            return InkWell(
                              onTap: () {
                                context
                                    .read<TemplatesCubit>()
                                    .selectTemplate(template);
                                _initValues(template);
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color:
                                      isSelected
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.primary.withAlpha(30)
                                          : Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withAlpha(60),
                                  border: Border.all(
                                    color:
                                        isSelected
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                            : Theme.of(
                                              context,
                                            ).colorScheme.outline.withAlpha(80),
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _iconForTemplate(template),
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            template.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (template.description != null &&
                                              template.description!.isNotEmpty)
                                            Text(
                                              template.description!,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurface.withAlpha(160),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(Icons.check_circle, size: 20),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 360,
          child: _TemplatePreviewCard(template: state.selectedTemplate),
        ),
      ],
    );
  }

  Widget _buildConfigureForm(BuildContext context, TemplatesState state) {
    final template = state.selectedTemplate;
    if (template == null) return const SizedBox.shrink();
    return Form(
      key: _formKey,
      child: ListView(
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Board name',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Board name is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          ...template.parameters.map((param) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TemplateParameterField(
                parameter: param,
                value: _values[param.name],
                error: _errors[param.name],
                onChanged: (value) {
                  setState(() {
                    _values[param.name] = value;
                    _errors.remove(param.name);
                  });
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, TemplatesState state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_step == _WizardStep.configure)
          TextButton(
            onPressed: () {
              setState(() => _step = _WizardStep.select);
              context.read<TemplatesCubit>().selectTemplate(null);
            },
            child: const Text('Back'),
          ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed:
              _isCreating
                  ? null
                  : () => _onPrimaryAction(context, state),
          child:
              _isCreating
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : Text(_primaryLabel),
        ),
      ],
    );
  }

  String get _primaryLabel => _step == _WizardStep.select ? 'Next' : 'Create';

  void _onPrimaryAction(BuildContext context, TemplatesState state) {
    switch (_step) {
      case _WizardStep.select:
        if (state.selectedTemplate == null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Select a template')));
          return;
        }
        setState(() => _step = _WizardStep.configure);
      case _WizardStep.configure:
        _createBoard(context, state);
    }
  }

  Future<void> _createBoard(BuildContext context, TemplatesState state) async {
    if (!_formKey.currentState!.validate()) return;
    final template = state.selectedTemplate;
    if (template == null) return;

    final cubit = context.read<TemplatesCubit>();
    final errors = cubit.validateParameters(template, _values);
    if (errors.isNotEmpty) {
      setState(() => _errors.addAll(errors));
      return;
    }

    setState(() => _isCreating = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boardCubit = context.read<BoardCubit>();
      final operations = BoardTemplateService.instance.buildOperations(
        template,
        _values,
      );
      final board = await boardCubit.createBoardFromOperations(
        name: _nameController.text.trim(),
        operations: operations,
      );
      if (mounted) {
        if (board != null) {
          navigator.pop();
        } else {
          messenger.showSnackBar(
            const SnackBar(content: Text('Could not create board')),
          );
        }
      }
    } on Exception catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to create board: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _initValues(BoardTemplate template) {
    _values.clear();
    _errors.clear();
    _nameController.text = template.name;
    for (final param in template.parameters) {
      final defaultValue = param.defaultValue;
      if (defaultValue != null) {
        _values[param.name] = defaultValue;
      }
    }
  }

  IconData _iconForTemplate(BoardTemplate template) =>
      templateIcon(template);
}

IconData templateIcon(BoardTemplate template) {
  final iconName = template.icon?.toLowerCase() ?? '';
  return switch (iconName) {
    'flutter' => Icons.flutter_dash,
    'home' => Icons.home_outlined,
    'note' || 'notes' => Icons.notes_outlined,
    'kanban' => Icons.view_kanban_outlined,
    'trip' || 'travel' => Icons.flight_takeoff_outlined,
    'habit' || 'okr' => Icons.track_changes_outlined,
    'weekly' || 'review' => Icons.calendar_view_week_outlined,
    'lightbulb' => Icons.lightbulb_outline,
    'roadmap' => Icons.map_outlined,
    'story' || 'mindmap' => Icons.account_tree_outlined,
    'retrospective' => Icons.psychology_outlined,
    'journey' => Icons.directions_outlined,
    'matrix' => Icons.grid_on_outlined,
    'sprint' => Icons.run_circle_outlined,
    _ => Icons.dashboard_outlined,
  };
}

class _TemplatePreviewCard extends StatefulWidget {
  const _TemplatePreviewCard({this.template});

  final BoardTemplate? template;

  @override
  State<_TemplatePreviewCard> createState() => _TemplatePreviewCardState();
}

class _TemplatePreviewCardState extends State<_TemplatePreviewCard> {
  final _generator = TemplatePreviewGenerator();
  var _cancelToken = CancelToken();
  Future<Uint8List?>? _previewFuture;

  @override
  void initState() {
    super.initState();
    _startGeneration();
  }

  @override
  void didUpdateWidget(covariant _TemplatePreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template?.id != widget.template?.id) {
      _cancelToken.cancel();
      _cancelToken = CancelToken();
      _startGeneration();
    }
  }

  @override
  void dispose() {
    _cancelToken.cancel();
    super.dispose();
  }

  void _startGeneration() {
    final template = widget.template;
    _previewFuture =
        template == null
            ? Future<Uint8List?>.value(null)
            : _generator.generate(template, cancelToken: _cancelToken);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final template = widget.template;
    if (template == null) {
      return _PreviewCard(
        child: Center(
          child: Text(
            'Select a template to see a preview',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurface.withAlpha(160)),
          ),
        ),
      );
    }

    final panelCounts = <String, int>{};
    for (final op in template.operations) {
      final opName = (op.payload['op'] ?? '').toString();
      if (opName == 'panel.create') {
        final type = (op.payload['type'] ?? 'panel').toString();
        panelCounts[type] = (panelCounts[type] ?? 0) + 1;
      }
    }

    return _PreviewCard(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PreviewImage(future: _previewFuture),
            Row(
              children: [
                Icon(templateIcon(template), color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    template.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            if (template.description case final desc? when desc.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurface.withAlpha(180),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Panels',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurface.withAlpha(200),
              ),
            ),
            const SizedBox(height: 8),
            if (panelCounts.isEmpty)
              Text(
                'No panels',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurface.withAlpha(160),
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    panelCounts.entries
                        .map(
                          (entry) => _PreviewChip(
                            '${entry.value}× ${_shortTypeName(entry.key)}',
                          ),
                        )
                        .toList(),
              ),
            const SizedBox(height: 16),
            Text(
              'Parameters',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurface.withAlpha(200),
              ),
            ),
            const SizedBox(height: 8),
            if (template.parameters.isEmpty)
              Text(
                'None',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurface.withAlpha(160),
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    template.parameters
                        .map(
                          (param) => _PreviewChip(
                            param.required ? '${param.label} *' : param.label,
                          ),
                        )
                        .toList(),
              ),
          ],
        ),
      ),
    );
  }

  String _shortTypeName(String typeId) {
    final parts = typeId.split('.');
    if (parts.length > 1) return parts.last;
    return typeId;
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({this.future});

  final Future<Uint8List?>? future;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 160,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return Container(
            height: 80,
            alignment: Alignment.center,
            child: Text(
              'Preview unavailable',
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurface.withAlpha(160),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        );
      },
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withAlpha(60),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outline.withAlpha(60)),
      ),
      child: child,
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      label: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}

enum _WizardStep { select, configure }
