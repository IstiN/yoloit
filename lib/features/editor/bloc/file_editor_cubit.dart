import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/features/board/events/board_event_bus.dart';
import 'package:yoloit/features/editor/bloc/file_editor_state.dart';
import 'package:yoloit/features/review/data/diff_service.dart';

class FileEditorCubit extends Cubit<FileEditorState> {
  FileEditorCubit() : super(const FileEditorState());

  String? _workspaceId;

  // Debounce timer per file path — auto-saves 800 ms after the last keystroke.
  final Map<String, Timer> _saveTimers = {};

  @override
  Future<void> close() {
    for (final t in _saveTimers.values) {
      t.cancel();
    }
    return super.close();
  }

  /// Called when the active workspace changes — clears current tabs and
  /// restores the previously open files for [workspaceId].
  Future<void> setWorkspace(String workspaceId) async {
    await setSession(workspaceId);
  }

  /// Called when the active session changes — saves current tabs then
  /// restores the tabs previously open in [sessionId].
  Future<void> setSession(String sessionId) async {
    _workspaceId = sessionId;
    for (final t in _saveTimers.values) {
      t.cancel();
    }
    _saveTimers.clear();

    final saved = await SessionPrefs.loadEditorTabs(sessionId);
    final paths = saved.paths.where((path) => File(path).existsSync()).toList();
    if (paths.isEmpty) {
      emit(const FileEditorState(tabs: [], activeIndex: 0, isVisible: false));
      return;
    }

    // Show placeholders while loading.
    final placeholders = paths
        .map((path) => EditorTab(filePath: path, isLoading: true))
        .toList();
    final activeIndex = saved.activeIndex.clamp(0, placeholders.length - 1);
    emit(
      FileEditorState(
        tabs: placeholders,
        activeIndex: activeIndex,
        isVisible: true,
      ),
    );

    // Load all files in parallel.
    final loadedTabs = await Future.wait(
      paths.map((path) async {
        if (_isImagePath(path)) return EditorTab(filePath: path);
        try {
          final content = await File(path).readAsString();
          return EditorTab(
            filePath: path,
            content: content,
            originalContent: content,
          );
        } catch (e) {
          return EditorTab(filePath: path, error: 'Cannot read file: $e');
        }
      }),
    );

    if (!isClosed) {
      emit(
        FileEditorState(
          tabs: loadedTabs,
          activeIndex: activeIndex,
          isVisible: true,
        ),
      );
    }
  }

  /// Opens [absolutePath] in a new tab; switches to it if already open.
  Future<void> openFile(String absolutePath) async {
    final existingIndex = state.tabs.indexWhere(
      (t) => t.filePath == absolutePath,
    );
    if (existingIndex != -1) {
      emit(state.copyWith(activeIndex: existingIndex, isVisible: true));
      _saveTabsToPrefs();
      return;
    }

    // Image files don't need content loaded — handled as visual preview.
    if (_isImagePath(absolutePath)) {
      final newTabs = [...state.tabs, EditorTab(filePath: absolutePath)];
      emit(
        state.copyWith(
          tabs: newTabs,
          activeIndex: newTabs.length - 1,
          isVisible: true,
        ),
      );
      _saveTabsToPrefs();
      return;
    }

    final placeholder = EditorTab(filePath: absolutePath, isLoading: true);
    final newTabs = [...state.tabs, placeholder];
    final newIndex = newTabs.length - 1;
    emit(state.copyWith(tabs: newTabs, activeIndex: newIndex, isVisible: true));

    try {
      final content = await File(absolutePath).readAsString();
      _updateTab(
        absolutePath,
        (t) => EditorTab(
          filePath: absolutePath,
          content: content,
          originalContent: content,
        ),
      );
      _saveTabsToPrefs();
    } catch (e) {
      _updateTab(
        absolutePath,
        (t) => t.copyWith(isLoading: false, error: 'Cannot read file: $e'),
      );
    }
  }

  /// Called by CodeController on every keystroke — updates state and
  /// schedules a debounced auto-save (800 ms after last change).
  void updateContent(String content) {
    final tab = state.activeTab;
    if (tab == null || tab.isLoading || tab.error != null) return;
    _updateTab(tab.filePath, (t) => t.copyWith(content: content));
    _scheduleAutoSave(tab.filePath, content);
  }

  /// Immediately saves [filePath] to disk and marks it clean.
  Future<void> saveFile() async {
    final tab = state.activeTab;
    if (tab == null || tab.content == null) return;
    await _writeToDisk(tab.filePath, tab.content!);
  }

  /// Closes the tab at [index].
  void closeTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    final path = state.tabs[index].filePath;
    _saveTimers.remove(path)?.cancel();
    final newTabs = List<EditorTab>.from(state.tabs)..removeAt(index);
    if (newTabs.isEmpty) {
      emit(state.copyWith(tabs: newTabs, activeIndex: 0, isVisible: false));
      _saveTabsToPrefs();
      return;
    }
    final newActive = (state.activeIndex >= newTabs.length)
        ? newTabs.length - 1
        : state.activeIndex;
    emit(state.copyWith(tabs: newTabs, activeIndex: newActive));
    _saveTabsToPrefs();
  }

  void switchTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    emit(state.copyWith(activeIndex: index));
    _saveTabsToPrefs();
  }

  void closeFile() => closeTab(state.activeIndex);

  /// Closes all tabs except the one at [keepIndex].
  void closeOthers(int keepIndex) {
    if (keepIndex < 0 || keepIndex >= state.tabs.length) return;
    final keep = state.tabs[keepIndex];
    emit(state.copyWith(tabs: [keep], activeIndex: 0));
    _saveTabsToPrefs();
  }

  void togglePanel() => emit(state.copyWith(isVisible: !state.isVisible));
  void showPanel() => emit(state.copyWith(isVisible: true));
  void hidePanel() => emit(state.copyWith(isVisible: false));

  /// Re-reads the active file from disk if it has no unsaved changes.
  /// Called when the app regains focus (external editor may have changed the file).
  Future<void> reloadActiveIfUnchanged() async {
    final tab = state.activeTab;
    if (tab == null || tab.isDiff || tab.isLoading || tab.error != null) return;
    if (_isImagePath(tab.filePath)) return;
    if (tab.isDirty) return; // user has unsaved changes — don't overwrite

    try {
      final onDisk = await File(tab.filePath).readAsString();
      if (onDisk != tab.content) {
        _updateTab(
          tab.filePath,
          (t) => t.copyWith(content: onDisk, originalContent: onDisk),
        );
      }
    } catch (_) {
      // File deleted or unreadable — ignore silently.
    }
  }

  /// Opens a diff view for [filePath] (relative to [workspacePath]) in a new tab.
  Future<void> openDiff(String filePath, String workspacePath) async {
    final tabPath = 'diff:$filePath';
    final existing = state.tabs.indexWhere((t) => t.filePath == tabPath);
    if (existing != -1) {
      emit(state.copyWith(activeIndex: existing, isVisible: true));
      return;
    }

    final placeholder = EditorTab(
      filePath: tabPath,
      isLoading: true,
      workspacePath: workspacePath,
    );
    final newTabs = [...state.tabs, placeholder];
    emit(
      state.copyWith(
        tabs: newTabs,
        activeIndex: newTabs.length - 1,
        isVisible: true,
      ),
    );

    try {
      final hunks = await DiffService.instance.getDiff(workspacePath, filePath);
      if (hunks.isNotEmpty) {
        _updateTab(
          tabPath,
          (_) => EditorTab(
            filePath: tabPath,
            workspacePath: workspacePath,
            diffHunks: hunks,
          ),
        );
      } else {
        // No git diff (untracked or binary) — try showing file content.
        final absolutePath = p.join(workspacePath, filePath);
        String? content;
        try {
          content = await File(absolutePath).readAsString();
        } catch (_) {
          // Binary or missing file — leave content null.
        }
        _updateTab(
          tabPath,
          (_) => EditorTab(
            filePath: tabPath,
            workspacePath: workspacePath,
            diffHunks: content == null ? const [] : null,
            content: content,
            originalContent: content,
          ),
        );
      }
    } catch (e) {
      _updateTab(
        tabPath,
        (t) => t.copyWith(isLoading: false, error: 'Cannot load diff: $e'),
      );
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  void _scheduleAutoSave(String filePath, String content) {
    _saveTimers[filePath]?.cancel();
    _saveTimers[filePath] = Timer(
      const Duration(milliseconds: 800),
      () => _writeToDisk(filePath, content),
    );
  }

  Future<void> _writeToDisk(String filePath, String content) async {
    try {
      final tabIndex = state.tabs.indexWhere((t) => t.filePath == filePath);
      if (tabIndex == -1) return;
      final tab = state.tabs[tabIndex];
      // Never write before the initial on-disk content has been hydrated into
      // state. This blocks phantom "" writes during restore/open while still
      // allowing users to intentionally clear a loaded file to empty content.
      if (tab.isLoading || tab.error != null || tab.originalContent == null) {
        return;
      }
      await File(filePath).writeAsString(content);
      _updateTab(filePath, (t) => t.copyWith(originalContent: content));
      BoardEventBus.instance.emit(BoardFileModifiedEvent(filePath));
    } catch (_) {
      // Silently ignore write errors for auto-save.
    }
  }

  void _updateTab(String filePath, EditorTab Function(EditorTab) updater) {
    final idx = state.tabs.indexWhere((t) => t.filePath == filePath);
    if (idx == -1) return;
    final newTabs = List<EditorTab>.from(state.tabs);
    newTabs[idx] = updater(newTabs[idx]);
    emit(state.copyWith(tabs: newTabs));
  }

  static bool _isImagePath(String path) {
    final ext = path.split('.').last.toLowerCase();
    return const {
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'bmp',
      'ico',
    }.contains(ext);
  }

  void _saveTabsToPrefs() {
    final id = _workspaceId;
    if (id == null) return;
    final paths = state.tabs
        .where((t) => !t.isDiff)
        .map((t) => t.filePath)
        .toList();
    final active = state.activeIndex.clamp(
      0,
      paths.isEmpty ? 0 : paths.length - 1,
    );
    SessionPrefs.saveEditorTabs(id, paths, active);
  }
}
