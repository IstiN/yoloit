import 'package:flutter/material.dart';

/// Web placeholder for [AboutSection].
///
/// Auto-update checks and native app version information are desktop-only, so
/// this section is hidden on the web.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
