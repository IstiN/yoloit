import 'package:flutter/material.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';

/// Presentation session card — identical visuals to macOS SessionNode.
class SessionCard extends StatelessWidget {
  const SessionCard({super.key, required this.props});
  final SessionCardProps props;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLive = props.isLive;
    final dotColor = isLive ? colors.accentGreen : colors.textSecondary;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: colors.primaryLight.withAlpha(102),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: colors.background.withAlpha(112),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.5),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: colors.primaryLight),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(
                          colors.surfaceElevated,
                          colors.primary,
                          0.08,
                        )!,
                        Color.lerp(colors.surface, colors.primaryDark, 0.06)!,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dotColor,
                              boxShadow:
                                  isLive
                                      ? [
                                        BoxShadow(
                                          color: dotColor.withAlpha(160),
                                          blurRadius: 6,
                                        ),
                                      ]
                                      : [],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              props.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isLive)
                            Text(
                              '▶',
                              style: TextStyle(
                                fontSize: 9,
                                color: colors.accentGreen,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        props.typeName,
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.textSecondary,
                        ),
                      ),
                      if (props.repoCount > 0) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${props.repoCount} ${props.repoCount == 1 ? 'repo' : 'repos'}',
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
