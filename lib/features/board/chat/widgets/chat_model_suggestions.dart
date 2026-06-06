import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/widgets/chat_provider_badge.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// Model picker dropdown shown below the chat input when a /model slash
/// command is active.
class ChatModelSuggestions extends StatelessWidget {
  const ChatModelSuggestions({
    required this.models,
    required this.selectedIndex,
    required this.currentModelId,
    required this.scrollController,
    required this.onSelect,
    super.key,
  });

  final List<ChatModelInfo> models;
  final int selectedIndex;
  final String currentModelId;
  final ScrollController scrollController;
  final ValueChanged<String> onSelect;

  static double _suggestionHeight(int count) {
    if (count == 0) return 40;
    return (count * 32.0 + 8).clamp(0, 280);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final effectiveIndex =
        models.isNotEmpty && selectedIndex >= models.length
            ? models.length - 1
            : selectedIndex;

    return Container(
      height: _suggestionHeight(models.length),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          if (models.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No models found',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            )
          else
            ...models.asMap().entries.map((entry) {
              final i = entry.key;
              final m = entry.value;
              final isActive = m.id == currentModelId;
              final isHighlighted = i == effectiveIndex;
              return InkWell(
                onTap: () => onSelect(m.id),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  color:
                      isHighlighted
                          ? colors.surfaceHighlight
                          : Colors.transparent,
                  child: Row(
                    children: [
                      if (isActive)
                        Icon(Icons.check, size: 14, color: colors.statusActive)
                      else
                        const SizedBox(width: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Row(
                          children: [
                            if (m.providerGroup != null) ...[
                              buildProviderBadge(context, m.providerGroup!),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                m.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      isActive
                                          ? colors.statusActive
                                          : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      buildModelPriceTag(
                        context,
                        m,
                        mutedColor: context.appColors.textMuted,
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
