import 'package:flutter/material.dart';

/// Web placeholder for [ChatContextSection].
///
/// The desktop implementation pulls in the CLI guidance service, which
/// transitively depends on `local_models_flutter` / `dart:ffi`. On the web this
/// section is hidden to keep the settings bundle free of native-only code.
class ChatContextSection extends StatelessWidget {
  const ChatContextSection({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
