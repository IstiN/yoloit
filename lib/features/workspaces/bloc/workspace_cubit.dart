import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/config/app_config.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/services/git_service.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/data/workspace_dir_service.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

class WorkspaceCubit extends Cubit<WorkspaceState> {
  /// [testWorkspacesFilePath] is for testing only — overrides the shared file path
  /// so tests can use a temporary, isolated file instead of the real user data.
  WorkspaceCubit({this.testWorkspacesFilePath}) : super(const WorkspaceInitial());

  /// If set, overrides the shared file path (for tests only).
  final String? testWorkspacesFilePath;

  static const _storageKey = 'workspaces';
  // Production bundle ID — used for cross-build migration only.
  static const _kProductionBundleId = 'com.yoloit.yoloit';

  // Debug and release builds use separate files so that running a debug build
  // never overwrites the production workspace list.
  static Future<File> get _sharedFile async {
    await AppConfig.instance.load();
    final basePath = AppConfig.instance.workspacesFilePath;
    final path = kDebugMode
        ? basePath.replaceFirst('.json', '.debug.json')
        : basePath;
    final dir = Directory(p.dirname(path));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(path);
  }

  Future<File> get _file async {
    if (testWorkspacesFilePath != null) {
      final dir = Directory(p.dirname(testWorkspacesFilePath!));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File(testWorkspacesFilePath!);
    }
    return _sharedFile;
  }

  Future<List<Workspace>> _loadShared() async {
    try {
      final f = await _file;
      if (!f.existsSync()) return [];
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is List) {
        return raw
            .map((e) => Workspace.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Try reading workspaces from the production app's plist (macOS only).
  /// Used as a one-time migration source when the shared file is empty.
  static Future<List<Workspace>> _loadFromProductionPrefs() async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null) return [];
      final plist = File(
        '$home/Library/Preferences/$_kProductionBundleId.plist',
      );
      if (!plist.existsSync()) return [];
      final result = await Process.run(
        'defaults',
        ['read', _kProductionBundleId, 'flutter.workspaces'],
      );
      if (result.exitCode != 0) return [];
      // `defaults read` returns macOS plist array as plain text — parse with plutil
      final jsonResult = await Process.run(
        'plutil',
        ['-convert', 'json', '-o', '-', plist.path],
      );
      if (jsonResult.exitCode != 0) return [];
      final decoded = jsonDecode(jsonResult.stdout as String) as Map<String, dynamic>;
      final rawList = decoded['flutter.workspaces'];
      if (rawList is! List) return [];
      return rawList
          .map((e) => Workspace.fromJson(jsonDecode(e as String) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveShared(List<Workspace> workspaces) async {
    final f = await _file;
    f.writeAsStringSync(
      jsonEncode(workspaces.map((w) => w.toJson()).toList()),
    );
  }

  final _dirService = WorkspaceDirService.instance;

  /// Default palette for auto-assigning workspace accent colours.
  static const _kWorkspacePalette = [
    Color(0xFF7C3AED), // violet
    Color(0xFF2563EB), // blue
    Color(0xFF059669), // emerald
    Color(0xFFD97706), // amber
    Color(0xFFDC2626), // red
    Color(0xFF0891B2), // cyan
    Color(0xFFDB2777), // pink
    Color(0xFF65A30D), // lime
    Color(0xFF9333EA), // purple
    Color(0xFFEA580C), // orange
  ];

  Future<void> load() async {
    emit(const WorkspaceLoading());
    try {
      // Primary: shared file at ~/.yoloit/workspaces.json (all builds share this)
      var workspaces = await _loadShared();

      // Migration priority:
      // 1. Shared file at configured path (all builds share this)
      // 2. Current build's SharedPreferences → migrate to shared file
      // 3. Production app's plist → migrate to shared file (cross-bundle migration)
      if (workspaces.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final json = prefs.getStringList(_storageKey) ?? [];
        if (json.isNotEmpty) {
          workspaces = json
              .map((s) => Workspace.fromJson(jsonDecode(s) as Map<String, dynamic>))
              .toList();
        }
      }
      if (workspaces.isEmpty) {
        workspaces = await _loadFromProductionPrefs();
      }
      if (workspaces.isNotEmpty) {
        await _saveShared(workspaces); // write to shared file for future loads
      }
      // Sync symlinks for all workspaces on startup.
      for (final ws in workspaces) {
        _dirService.syncSymlinks(ws);
      }
      final snap = await SessionPrefs.load();
      final savedId = snap.activeWorkspaceId;
      final activeId = savedId != null && workspaces.any((w) => w.id == savedId)
          ? savedId
          : (workspaces.isNotEmpty ? workspaces.first.id : null);
      emit(WorkspaceLoaded(workspaces: workspaces, activeWorkspaceId: activeId));
      // Refresh git info for all workspaces
      for (final ws in workspaces) {
        _refreshGitInfo(ws.id);
      }
    } catch (e) {
      emit(WorkspaceError(e.toString()));
    }
  }

  /// Creates a new workspace with a user-defined [name] and initial [folderPath].
  Future<void> addWorkspace(String folderPath, {String? customName}) async {
    final name = customName ?? p.basename(folderPath);
    final id = '${name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}_${DateTime.now().millisecondsSinceEpoch}';
    final current = _currentLoaded;
    if (current == null) return;
    final defaultColor = _kWorkspacePalette[current.workspaces.length % _kWorkspacePalette.length];
    final workspace = Workspace(
      id: id,
      name: name,
      paths: [folderPath],
      color: defaultColor,
    );
    await _dirService.syncSymlinks(workspace);
    final updated = [...current.workspaces, workspace];
    emit(current.copyWith(workspaces: updated));
    await _save(updated);
    await _refreshGitInfo(id);
  }

  /// Adds an additional folder path to an existing workspace.
  Future<void> addPathToWorkspace(String workspaceId, String folderPath) async {
    final current = _currentLoaded;
    if (current == null) return;
    final updated = current.workspaces.map((w) {
      if (w.id != workspaceId) return w;
      if (w.paths.contains(folderPath)) return w;
      return w.copyWith(paths: [...w.paths, folderPath]);
    }).toList();
    emit(current.copyWith(workspaces: updated));
    await _save(updated);
    final ws = updated.firstWhere((w) => w.id == workspaceId);
    await _dirService.syncSymlinks(ws);
  }

  /// Removes a folder path from a workspace. Removes the workspace entirely if
  /// it becomes empty.
  Future<void> removePathFromWorkspace(String workspaceId, String folderPath) async {
    final current = _currentLoaded;
    if (current == null) return;
    final List<Workspace> updated = [];
    String? removedActiveId;
    for (final w in current.workspaces) {
      if (w.id != workspaceId) {
        updated.add(w);
        continue;
      }
      final newPaths = w.paths.where((p) => p != folderPath).toList();
      if (newPaths.isEmpty) {
        // Workspace has no more folders — remove it.
        await _dirService.deleteDir(w.id);
        if (current.activeWorkspaceId == w.id) removedActiveId = w.id;
      } else {
        final updated2 = w.copyWith(paths: newPaths);
        await _dirService.syncSymlinks(updated2);
        updated.add(updated2);
      }
    }
    final newActiveId = removedActiveId != null ? null : current.activeWorkspaceId;
    emit(WorkspaceLoaded(workspaces: updated, activeWorkspaceId: newActiveId));
    await _save(updated);
  }

  Future<void> removeWorkspace(String id) async {
    final current = _currentLoaded;
    if (current == null) return;
    await _dirService.deleteDir(id);
    final updated = current.workspaces.where((w) => w.id != id).toList();
    final newActiveId = current.activeWorkspaceId == id ? null : current.activeWorkspaceId;
    emit(WorkspaceLoaded(workspaces: updated, activeWorkspaceId: newActiveId));
    await _save(updated);
  }

  void setActive(String id) {
    final current = _currentLoaded;
    if (current == null) return;
    emit(current.copyWith(activeWorkspaceId: id));
    SessionPrefs.saveActiveWorkspaceId(id);
  }

  Future<void> setWorkspaceColor(String id, Color? color) async {
    final current = _currentLoaded;
    if (current == null) return;
    final updated = current.workspaces.map((w) {
      if (w.id != id) return w;
      return color == null ? w.copyWith(clearColor: true) : w.copyWith(color: color);
    }).toList();
    emit(current.copyWith(workspaces: updated));
    await _save(updated);
  }

  /// Renames a workspace.
  Future<void> renameWorkspace(String id, String newName) async {
    final current = _currentLoaded;
    if (current == null) return;
    final updated = current.workspaces.map((w) {
      if (w.id != id) return w;
      return w.copyWith(name: newName);
    }).toList();
    emit(current.copyWith(workspaces: updated));
    await _save(updated);
  }

  Future<void> refreshAll() async {
    final current = _currentLoaded;
    if (current == null) return;
    for (final ws in current.workspaces) {
      await _refreshGitInfo(ws.id);
    }
  }

  /// Updates a single workspace (e.g. after skill enablement changes) and persists.
  Future<void> updateWorkspace(Workspace workspace) async {
    final current = _currentLoaded;
    if (current == null) return;
    final updated = current.workspaces.map((w) => w.id == workspace.id ? workspace : w).toList();
    emit(current.copyWith(workspaces: updated));
    await _save(updated);
  }

  Future<void> _refreshGitInfo(String id) async {
    final current = _currentLoaded;
    if (current == null) return;
    final ws = current.workspaces.firstWhere((w) => w.id == id, orElse: () => throw StateError(''));
    if (ws.paths.isEmpty) return;
    try {
      // Use primary path for git info.
      final branch = await GitService.instance.getBranch(ws.path);
      final stats = await GitService.instance.getDiffStats(ws.path);
      final updated = current.workspaces.map((w) {
        if (w.id == id) {
          return w.copyWith(
            gitBranch: branch,
            addedLines: stats.added,
            removedLines: stats.removed,
          );
        }
        return w;
      }).toList();
      if (state is WorkspaceLoaded) {
        emit((state as WorkspaceLoaded).copyWith(workspaces: updated));
      }
    } catch (_) {}
  }

  Future<void> _save(List<Workspace> workspaces) async {
    // Write to shared file (all builds) and keep SharedPreferences in sync.
    await _saveShared(workspaces);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      workspaces.map((w) => jsonEncode(w.toJson())).toList(),
    );
  }

  WorkspaceLoaded? get _currentLoaded {
    final s = state;
    if (s is WorkspaceLoaded) return s;
    if (s is WorkspaceInitial || s is WorkspaceLoading) {
      return const WorkspaceLoaded(workspaces: []);
    }
    return null;
  }
}
