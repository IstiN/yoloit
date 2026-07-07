import 'package:flutter/material.dart';

/// Web placeholder for [PromptsSection].
///
/// The desktop implementation depends on the CLI guidance service, which
/// transitively pulls in native-only code. On the web this section is hidden.
class PromptsSection extends StatelessWidget {
  const PromptsSection({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
