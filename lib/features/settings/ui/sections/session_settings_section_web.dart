import 'package:flutter/material.dart';

/// Web placeholder for [SessionSettings].
///
/// Terminal sessions, tmux, logging, and workspace storage are desktop-only
/// capabilities, so this section is hidden on the web.
class SessionSettings extends StatelessWidget {
  const SessionSettings({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
