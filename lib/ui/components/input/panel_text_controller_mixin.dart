import 'package:flutter/material.dart';

/// Mixin for [State] classes that need a [TextEditingController] synced to
/// a panel's `text` state key.
///
/// Implement [panelText] to provide the source string.  The mixin handles
/// initialise-on-[initState], sync-on-[didUpdateWidget], and dispose.
mixin PanelTextControllerMixin<T extends StatefulWidget> on State<T> {
  late final TextEditingController controller;

  /// Current text value derived from the widget / panel state.
  String get panelText;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: panelText);
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = panelText;
    if (next != controller.text) {
      controller.value = controller.value.copyWith(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
