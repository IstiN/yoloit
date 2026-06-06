import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/widgets/chat_provider_badge.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

class ModelSearchDialog extends StatefulWidget {
  const ModelSearchDialog({
    required this.models,
    required this.selectedId,
    required this.inputFill,
  });

  final List<ChatModelInfo> models;
  final String selectedId;
  final Color inputFill;

  @override
  State<ModelSearchDialog> createState() => ModelSearchDialogState();
}

class ModelSearchDialogState extends State<ModelSearchDialog> {
  final _searchCtrl = TextEditingController();
  late List<ChatModelInfo> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.models;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) {
        _filtered = widget.models;
      } else {
        _filtered =
            widget.models.where((m) {
              return m.displayName.toLowerCase().contains(q) ||
                  m.id.toLowerCase().contains(q) ||
                  (m.providerGroup?.toLowerCase().contains(q) ?? false);
            }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = Theme.of(context).dialogBackgroundColor;

    return Dialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _onSearch,
                style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search models…',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withAlpha(102),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: colorScheme.onSurface.withAlpha(102),
                  ),
                  filled: true,
                  fillColor: widget.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Results
            Flexible(
              child:
                  _filtered.isEmpty
                      ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No models found',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface.withAlpha(128),
                            ),
                          ),
                        ),
                      )
                      : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        itemCount: _filtered.length,
                        itemExtent: 34,
                        itemBuilder: (ctx, i) {
                          final m = _filtered[i];
                          final isSelected = m.id == widget.selectedId;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => Navigator.of(context).pop(m.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              child: Row(
                                children: [
                                  if (isSelected)
                                    Icon(
                                      Icons.check,
                                      size: 14,
                                      color: colors.statusActive,
                                    )
                                  else
                                    const SizedBox(width: 14),
                                  const SizedBox(width: 6),
                                  if (m.providerGroup != null) ...[
                                    buildProviderBadge(
                                      context,
                                      m.providerGroup!,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(
                                      m.displayName,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            isSelected
                                                ? colors.statusActive
                                                : colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  if (m.isFree)
                                    Text(
                                      'FREE',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: colors.statusActive,
                                      ),
                                    )
                                  else if (m.inputCostPerMillion != null)
                                    Text(
                                      '\$${m.inputCostPerMillion!.toStringAsFixed(m.inputCostPerMillion! < 1 ? 2 : 1)}',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color:
                                            m.inputCostPerMillion! > 10
                                                ? colors.statusError
                                                : colorScheme.onSurface
                                                    .withAlpha(153),
                                      ),
                                    )
                                  else if (m.costMultiplier != null)
                                    Text(
                                      '${m.costMultiplier}x',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color:
                                            m.costMultiplier == 0
                                                ? colors.statusActive
                                                : m.costMultiplier! > 3
                                                ? colors.statusError
                                                : colorScheme.onSurface
                                                    .withAlpha(153),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
