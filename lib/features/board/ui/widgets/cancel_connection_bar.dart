import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

class CancelConnectionBar extends StatelessWidget {
  const CancelConnectionBar({super.key, required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onCancel,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surfaceElevated.withAlpha(220),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.statusError.withAlpha(160)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.close,
                    size: 14,
                    color: colors.statusError.withAlpha(200),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Cancel connection  (Esc)',
                    style: TextStyle(
                      color: colors.statusError.withAlpha(200),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
