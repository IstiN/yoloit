import 'package:flutter/material.dart';

/// Shared wrapper for debug-UI showcase sections.
///
/// Replaces the repeated `SingleChildScrollView` → `Padding` → `Column`
/// boilerplate in [ComponentShowcase], [ColorShowcase], [TypographyShowcase],
/// and similar palette pages.
class ShowcaseScaffold extends StatelessWidget {
  const ShowcaseScaffold({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
