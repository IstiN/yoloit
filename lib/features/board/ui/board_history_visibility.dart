import 'package:flutter/foundation.dart';

/// App-scoped visibility signal for the board history panel.
///
/// The toggle lives in the shared title bar (see `BoardTitleBar`) while the
/// panel itself is rendered inside `BoardView`; this notifier lets the two
/// coordinate without threading callbacks through the shell.
final ValueNotifier<bool> boardHistoryVisibility = ValueNotifier<bool>(false);

/// Bridge that lets the app-level title bar trigger undo/redo on the active
/// board. `BoardView` refreshes these closures on every build and clears them
/// on dispose, so the title bar never calls into a dead state.
class BoardUndoRedo {
  BoardUndoRedo._();

  static VoidCallback? undo;
  static VoidCallback? redo;
}
