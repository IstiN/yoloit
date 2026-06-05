import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Text(
      title,
      style: TextStyle(
        color: colors.primary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }
}
