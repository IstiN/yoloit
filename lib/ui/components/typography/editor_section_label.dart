import 'package:flutter/material.dart';

/// Small section label used inside editor dialogs.
///
/// Replaces repeated private `_SectionLabel` / `_EditorSectionLabel`
/// widgets scattered across board plugin editors.
class EditorSectionLabel extends StatelessWidget {
  const EditorSectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.only(bottom: 8),
  });

  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}
