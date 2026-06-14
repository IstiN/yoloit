import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/features/skills/bloc/skills_state.dart';
import 'package:yoloit/features/skills/data/skills_install_service.dart';
import 'package:yoloit/features/skills/data/skills_store_service.dart';
import 'package:yoloit/features/skills/models/skill_entry.dart';
import 'package:yoloit/features/skills/models/skill_store_config.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

class SkillsCubit extends Cubit<SkillsState> {
  SkillsCubit() : super(const SkillsInitial());

  final _storeService = SkillsStoreService.instance;
  final _installService = SkillsInstallService.instance;

  // ── Load ────────────────────────────────────────────────────────────────────

  Future<void> load(List<Workspace> workspaces) async {
    emit(const SkillsLoading());
    try {
      final skills = await _storeService.load();
      emit(SkillsLoaded(
        config: _storeService.config,
        skills: skills,
        workspaces: workspaces,
        loadedFromRemote: _storeService.loadedFromRemote,
      ));
    } catch (e) {
      emit(SkillsError(e.toString()));
    }
  }

  void updateWorkspaces(List<Workspace> workspaces) {
    final s = state;
    if (s is SkillsLoaded) {
      emit(s.copyWith(workspaces: workspaces));
    }
  }

  void selectStore(String? storeId) {
    final s = state;
    if (s is SkillsLoaded) {
      emit(s.copyWith(
        selectedStoreId: storeId,
        clearSelectedStore: storeId == null,
      ));
    }
  }

  // ── Install ─────────────────────────────────────────────────────────────────

  Future<void> installSkill(SkillEntry skill) async {
    final s = state;
    if (s is! SkillsLoaded) return;
    if (s.busySkillIds.contains(skill.id)) return;

    emit(s.copyWith(busySkillIds: {...s.busySkillIds, skill.id}, clearError: true));

    SkillInstallResult result;
    switch (skill.sourceType) {
      case SkillSourceType.github:
        result = await _installService.installGithubSkill(skill);
      case SkillSourceType.installScript:
        result = await _installService.runInstallScript(skill);
      case SkillSourceType.url:
      case SkillSourceType.local:
        result = SkillInstallResult.error(skill.id, 'Manual installation required. Visit: ${skill.installUrl ?? skill.source}');
    }

    await _storeService.refresh();
    final updatedSkills = _storeService.availableSkills;

    final current = state;
    if (current is! SkillsLoaded) return;
    final busy = {...current.busySkillIds}..remove(skill.id);

    if (result.status == SkillInstallStatus.requiresTerminal) {
      emit(current.copyWith(
        skills: updatedSkills,
        busySkillIds: busy,
        errorMessage: 'Run in terminal:\n${result.message}',
      ));
    } else if (!result.isSuccess) {
      emit(current.copyWith(
        skills: updatedSkills,
        busySkillIds: busy,
        errorMessage: result.message,
      ));
    } else {
      emit(current.copyWith(skills: updatedSkills, busySkillIds: busy, clearError: true));
    }
  }

  Future<void> uninstallSkill(String skillId) async {
    final s = state;
    if (s is! SkillsLoaded) return;

    emit(s.copyWith(busySkillIds: {...s.busySkillIds, skillId}));
    await _installService.uninstallGlobalSkill(skillId, s.workspaces);
    await _storeService.refresh();
    final updatedSkills = _storeService.availableSkills;

    final current = state;
    if (current is! SkillsLoaded) return;
    final busy = {...current.busySkillIds}..remove(skillId);
    emit(current.copyWith(skills: updatedSkills, busySkillIds: busy));
  }

  // ── Workspace skill enablement ───────────────────────────────────────────────

  /// Enables or disables a skill for a workspace, updating symlinks and returning
  /// the updated workspace so the caller can persist it.
  Future<Workspace?> setSkillEnabledForWorkspace({
    required String skillId,
    required Workspace workspace,
    required bool enabled,
  }) async {
    final List<String> updated;
    if (enabled) {
      if (workspace.enabledSkills.contains(skillId)) return null;
      updated = [...workspace.enabledSkills, skillId];
    } else {
      updated = workspace.enabledSkills.where((s) => s != skillId).toList();
    }

    final updatedWorkspace = workspace.copyWith(enabledSkills: updated);
    await _installService.syncWorkspaceSkills(updatedWorkspace);
    return updatedWorkspace;
  }

  // ── Install to repo ──────────────────────────────────────────────────────────

  Future<void> installSkillToRepo(SkillEntry skill, String repoPath) async {
    final s = state;
    if (s is! SkillsLoaded) return;

    emit(s.copyWith(busySkillIds: {...s.busySkillIds, skill.id}, clearError: true));
    final result = await _installService.installSkillToRepo(skill, repoPath);

    final current = state;
    if (current is! SkillsLoaded) return;
    final busy = {...current.busySkillIds}..remove(skill.id);

    if (!result.isSuccess) {
      emit(current.copyWith(busySkillIds: busy, errorMessage: result.message));
    } else {
      emit(current.copyWith(busySkillIds: busy, clearError: true));
    }
  }

  // ── Store management ─────────────────────────────────────────────────────────

  Future<void> addCustomStore(SkillStore store) async {
    final s = state;
    if (s is! SkillsLoaded) return;
    final updated = s.config.withStore(store);
    await _storeService.saveConfig(updated);
    emit(s.copyWith(config: updated));
  }

  Future<void> removeStore(String storeId) async {
    final s = state;
    if (s is! SkillsLoaded) return;
    final updated = s.config.withoutStore(storeId);
    await _storeService.saveConfig(updated);
    emit(s.copyWith(config: updated));
  }

  void clearError() {
    final s = state;
    if (s is SkillsLoaded) emit(s.copyWith(clearError: true));
  }

  /// Reads the raw SKILL.md content for an installed skill.
  Future<String?> readSkillContent(String skillId) async {
    return _storeService.readSkillContent(skillId);
  }
}
