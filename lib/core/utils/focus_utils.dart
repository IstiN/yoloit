import 'package:flutter/widgets.dart';

/// Whether the keyboard focus currently sits inside an editable text field.
///
/// Use this guard in panel- or app-level [Focus.onKeyEvent] handlers so
/// text-editing shortcuts (Cmd/Ctrl+C/V/A, arrows, …) reach the focused
/// field instead of being swallowed as higher-level shortcuts. Key events
/// bubble from [FocusManager.instance.primaryFocus] up through ancestor
/// focus nodes, so a panel-level handler runs BEFORE the framework's
/// [DefaultTextEditingShortcuts] (which lives near the top of the widget
/// tree) — without this guard, panel shortcuts like "paste to create a
/// card" fire even while the user is typing in a text field.
bool isFocusInEditableText() {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) return false;
  return focusContext.widget is EditableText ||
      focusContext.findAncestorStateOfType<EditableTextState>() != null;
}
