import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

/// Web stub for [WorkspaceCubit].
///
/// Workspaces are a desktop concept (folders on the local file system), so the
/// web implementation always reports an empty workspace list. This lets UI code
/// that expects a [WorkspaceCubit] compile and run in the browser without
/// pulling in `dart:io` or native process APIs.
class WorkspaceCubit extends Cubit<WorkspaceState> {
  WorkspaceCubit({this.testWorkspacesFilePath}) : super(const WorkspaceLoaded(workspaces: []));

  final String? testWorkspacesFilePath;

  Future<void> load() async {}
  Future<void> addWorkspace(String folderPath, {String? customName}) async {}
  Future<void> addPathToWorkspace(String workspaceId, String folderPath) async {}
  Future<void> removePathFromWorkspace(String workspaceId, String folderPath) async {}
  Future<void> removeWorkspace(String id) async {}
  void setActive(String id) {}
  Future<void> setWorkspaceColor(String id, Color? color) async {}
  Future<void> renameWorkspace(String id, String newName) async {}
  Future<void> refreshAll() async {}
  Future<void> updateWorkspace(Workspace workspace) async {}
}
