import 'package:flutter/material.dart';

/// Web placeholder for [TerminalRendererSettings].
///
/// Terminal renderer backend selection is only relevant on desktop, so this
/// section is hidden on the web.
class TerminalRendererSettings extends StatelessWidget {
  const TerminalRendererSettings({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
