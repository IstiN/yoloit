import 'dart:async';

/// Base class for all board-wide events.
abstract class BoardEvent {
  const BoardEvent();
}

/// Emitted when a file on disk has been modified (e.g., by a chat agent tool).
/// Panels that display [path] should re-read the file and refresh.
class BoardFileModifiedEvent extends BoardEvent {
  const BoardFileModifiedEvent(this.path);

  /// Absolute path of the file that was modified.
  final String path;
}

/// Central event bus for board-wide notifications.
///
/// **Emitting events** (from chat/agent code):
/// ```dart
/// BoardEventBus.instance.emit(BoardFileModifiedEvent('/abs/path/file.md'));
/// ```
///
/// **Subscribing in a widget** (e.g., a file preview panel):
/// ```dart
/// StreamSubscription<BoardEvent>? _sub;
///
/// @override
/// void initState() {
///   super.initState();
///   _sub = BoardEventBus.instance.on<BoardFileModifiedEvent>().listen((e) {
///     if (e.path == myFilePath) setState(() { _refreshKey++; });
///   });
/// }
///
/// @override
/// void dispose() {
///   _sub?.cancel();
///   super.dispose();
/// }
/// ```
///
/// The bus is provider-agnostic — any chat provider (Copilot, OpenCode, Cursor)
/// can emit [BoardFileModifiedEvent] after detecting a file mutation tool call.
class BoardEventBus {
  BoardEventBus._();

  static final BoardEventBus instance = BoardEventBus._();

  final StreamController<BoardEvent> _controller =
      StreamController<BoardEvent>.broadcast();

  /// Raw stream of all board events.
  Stream<BoardEvent> get stream => _controller.stream;

  /// Filtered stream of events of type [T].
  Stream<T> on<T extends BoardEvent>() =>
      _controller.stream.where((e) => e is T).cast<T>();

  /// Emit an event to all current listeners.
  void emit(BoardEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  /// Convenience: emit a [BoardFileModifiedEvent] for [path].
  void fileModified(String path) => emit(BoardFileModifiedEvent(path));
}
