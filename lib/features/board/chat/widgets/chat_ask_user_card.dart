import 'package:flutter/material.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Card that presents a question with selectable choices from an agent.
class ChatAskUserCard extends StatelessWidget {
  const ChatAskUserCard({
    super.key,
    required this.question,
    required this.choices,
    required this.onChoice,
  });

  final String question;
  final List<String> choices;
  final ValueChanged<String> onChoice;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.primaryLight.withAlpha(21),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.primaryLight.withAlpha(64)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, size: 16, color: colors.primaryLight),
                const SizedBox(width: 6),
                Text(
                  'Agent asks:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryLight,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              question,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            if (choices.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    choices
                        .map(
                          (choice) => OutlinedButton(
                            onPressed: () => onChoice(choice),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.primaryLight,
                              side: BorderSide(color: colors.primaryLight),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            child: Text(choice),
                          ),
                        )
                        .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
