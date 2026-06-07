import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';

part 'card_props.g.dart';

// ── Shared sub-types ───────────────────────────────────────────────────────

class RepoBranchInfo {
  const RepoBranchInfo({required this.repo, required this.branch});
  final String repo;
  final String branch;

  factory RepoBranchInfo.fromJson(Map<String, dynamic> j) => RepoBranchInfo(
        repo: j['repo'] as String? ?? '',
        branch: j['branch'] as String? ?? '',
      );
}

class OutputLine {
  const OutputLine({required this.text, this.isError = false});
  final String text;
  final bool isError;

  factory OutputLine.fromJson(Map<String, dynamic> j) => OutputLine(
        text: j['text'] as String? ?? '',
        isError: j['isError'] as bool? ?? false,
      );
}

class FileEntry {
  const FileEntry({
    required this.path,
    required this.status,
    this.addedLines = 0,
    this.removedLines = 0,
  });
  final String path;
  final String status; // 'added','modified','deleted','renamed','untracked'
  final int addedLines;
  final int removedLines;

  factory FileEntry.fromJson(Map<String, dynamic> j) => FileEntry(
        path: j['path'] as String? ?? '',
        status: j['status'] as String? ?? 'modified',
        addedLines: j['addedLines'] as int? ?? 0,
        removedLines: j['removedLines'] as int? ?? 0,
      );
}

class TreeEntry {
  const TreeEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.depth = 0,
    this.isExpanded = false,
  });
  final String name;
  final String path;
  final bool isDir;
  final int depth;
  final bool isExpanded;

  factory TreeEntry.fromJson(Map<String, dynamic> j) => TreeEntry(
        name: j['name'] as String? ?? '',
        path: j['path'] as String? ?? '',
        isDir: j['isDir'] as bool? ?? false,
        depth: j['depth'] as int? ?? 0,
        isExpanded: j['isExpanded'] as bool? ?? false,
      );
}

class DiffHunk {
  const DiffHunk({required this.header, required this.lines});
  final String header;
  final List<DiffLine> lines;

  factory DiffHunk.fromJson(Map<String, dynamic> j) => DiffHunk(
        header: j['header'] as String? ?? '',
        lines: (j['lines'] as List? ?? [])
            .map((l) => DiffLine.fromJson(l as Map<String, dynamic>))
            .toList(),
      );
}

class DiffLine {
  const DiffLine({required this.text, required this.type});
  final String text;
  final String type; // 'add','remove','context'

  factory DiffLine.fromJson(Map<String, dynamic> j) => DiffLine(
        text: j['text'] as String? ?? '',
        type: j['type'] as String? ?? 'context',
      );
}

class TabInfo {
  const TabInfo({required this.path, this.isActive = false});
  final String path;
  final bool isActive;

  factory TabInfo.fromJson(Map<String, dynamic> j) => TabInfo(
        path: j['path'] as String? ?? '',
        isActive: j['isActive'] as bool? ?? false,
      );
}

// ── Card Props ─────────────────────────────────────────────────────────────

class AgentCardProps {
  const AgentCardProps({
    required this.name,
    required this.status,
    required this.isRunning,
    this.typeName = '',
    this.lastLines = const [],
    this.repos = const [],
    this.isIdle = false,
    this.hookPhase,
  });
  final String name;
  final String status; // 'live','idle','error'
  final bool isRunning;
  final String typeName;
  final List<String> lastLines;
  final List<RepoBranchInfo> repos;
  final bool isIdle;

  /// Fine-grained agent phase from hook events. null = idle.
  final AgentPhase? hookPhase;

  factory AgentCardProps.fromJson(Map<String, dynamic> j) {
    final rawLines = j['lastLines'];
    final lines = rawLines is List
        ? rawLines.map((l) => l.toString()).toList()
        : <String>[];
    final rawRepos = j['repos'];
    final repos = rawRepos is List
        ? rawRepos
            .map((r) => RepoBranchInfo.fromJson(r as Map<String, dynamic>))
            .toList()
        : <RepoBranchInfo>[];
    return AgentCardProps(
      name: j['name'] as String? ?? '',
      status: j['status'] as String? ?? 'idle',
      isRunning: j['isRunning'] as bool? ?? false,
      typeName: j['typeName'] as String? ?? '',
      lastLines: lines,
      repos: repos,
      isIdle: j['isIdle'] as bool? ?? false,
      hookPhase: _parsePhase(j['hookPhase'] as String?),
    );
  }

  static AgentPhase? _parsePhase(String? s) {
    if (s == null) return null;
    if (s == 'thinking') return const ThinkingPhase();
    if (s.startsWith('tool:')) return ToolPhase(s.substring(5));
    if (s == 'awaiting_approval') return const AwaitingApprovalPhase();
    if (s == 'done') return const DonePhase();
    if (s == 'error') return const ErrorPhase();
    return null;
  }
}

class WorkspaceCardProps {
  const WorkspaceCardProps({
    required this.name,
    this.color,
    this.paths = const [],
  });
  final String name;
  final Color? color;
  final List<String> paths;

  factory WorkspaceCardProps.fromJson(Map<String, dynamic> j) {
    final rawColor = j['color'];
    return WorkspaceCardProps(
      name: j['name'] as String? ?? '',
      color: rawColor is int ? Color(rawColor) : null,
      paths: (j['paths'] as List?)?.cast<String>() ?? const [],
    );
  }
}

class RepoCardProps {
  const RepoCardProps({required this.repoName, required this.branch});
  final String repoName;
  final String branch;

  factory RepoCardProps.fromJson(Map<String, dynamic> j) => RepoCardProps(
        repoName: j['name'] as String? ?? j['repoName'] as String? ?? '',
        branch: j['branch'] as String? ?? '',
      );
}

class BranchCardProps {
  const BranchCardProps({
    required this.branch,
    required this.repoName,
    this.commitHash = '',
  });
  final String branch;
  final String repoName;
  final String commitHash;

  factory BranchCardProps.fromJson(Map<String, dynamic> j) => BranchCardProps(
        branch: j['name'] as String? ?? j['branch'] as String? ?? '',
        repoName: j['repoName'] as String? ?? '',
        commitHash: j['commitHash'] as String? ?? '',
      );
}

class RunCardProps {
  const RunCardProps({
    required this.name,
    required this.status,
    required this.isRunning,
    this.lines = const [],
  });
  final String name;
  final String status;
  final bool isRunning;
  final List<OutputLine> lines;

  factory RunCardProps.fromJson(Map<String, dynamic> j) {
    final rawLines = j['lines'];
    List<OutputLine> lines;
    if (rawLines is List) {
      lines = rawLines.map((l) {
        if (l is Map<String, dynamic>) return OutputLine.fromJson(l);
        return OutputLine(text: l.toString());
      }).toList();
    } else {
      // fallback: lastLines as plain strings
      final ll = j['lastLines'];
      lines = ll is List
          ? ll.map((l) => OutputLine(text: l.toString())).toList()
          : [];
    }
    return RunCardProps(
      name: j['name'] as String? ?? '',
      status: j['status'] as String? ?? 'idle',
      isRunning: j['isRunning'] as bool? ?? false,
      lines: lines,
    );
  }
}

class EditorCardProps {
  const EditorCardProps({
    required this.filePath,
    this.language = '',
    this.content = '',
    this.tabs = const [],
    this.imageBase64,
  });
  final String filePath;
  final String language;
  final String content;
  final List<TabInfo> tabs;
  /// Non-null when the file is an image. Contains raw base64-encoded bytes.
  final String? imageBase64;

  bool get isImage => imageBase64 != null && imageBase64!.isNotEmpty;

  factory EditorCardProps.fromJson(Map<String, dynamic> j) => EditorCardProps(
        filePath: j['filePath'] as String? ?? '',
        language: j['language'] as String? ?? '',
        content: j['content'] as String? ?? '',
        imageBase64: j['imageBase64'] as String?,
        tabs: (j['tabs'] as List?)
                ?.map((t) => TabInfo.fromJson(t as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class FilesCardProps {
  const FilesCardProps({this.repoPath = '', this.files = const []});
  final String repoPath;
  final List<FileEntry> files;

  factory FilesCardProps.fromJson(Map<String, dynamic> j) => FilesCardProps(
        repoPath: j['repoPath'] as String? ?? '',
        files: (j['files'] as List?)
                ?.map((f) => FileEntry.fromJson(f as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class FileTreeCardProps {
  const FileTreeCardProps({
    this.repoName,
    this.repoPath,
    this.entries = const [],
  });
  final String? repoName;
  final String? repoPath;
  final List<TreeEntry> entries;

  factory FileTreeCardProps.fromJson(Map<String, dynamic> j) =>
      FileTreeCardProps(
        repoName: j['repoName'] as String?,
        repoPath: j['repoPath'] as String?,
        entries: (j['entries'] as List?)
                ?.map((e) => TreeEntry.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

@JsonSerializable()
class ChangedFileEntry {
  const ChangedFileEntry({
    required this.path,
    required this.name,
    required this.status,
    this.addedLines = 0,
    this.removedLines = 0,
  });
  final String path;
  final String name;
  final String status; // 'modified' | 'added' | 'deleted' | 'renamed' | 'untracked'
  final int addedLines;
  final int removedLines;

  factory ChangedFileEntry.fromJson(Map<String, dynamic> j) =>
      _$ChangedFileEntryFromJson(j);

  Map<String, dynamic> toJson() => _$ChangedFileEntryToJson(this);
}

class DiffCardProps {
  const DiffCardProps({
    this.repoName,
    this.repoPath,
    this.hunks = const [],
    this.changedFiles = const [],
    this.selectedFilePath,
  });
  final String? repoName;
  final String? repoPath;
  final List<DiffHunk> hunks;
  final List<ChangedFileEntry> changedFiles;
  final String? selectedFilePath;

  factory DiffCardProps.fromJson(Map<String, dynamic> j) => DiffCardProps(
        repoName: j['repoName'] as String?,
        repoPath: j['repoPath'] as String?,
        hunks: (j['hunks'] as List?)
                ?.map((h) => DiffHunk.fromJson(h as Map<String, dynamic>))
                .toList() ??
            const [],
        changedFiles: (j['changedFiles'] as List?)
                ?.map((f) => ChangedFileEntry.fromJson(f as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class SessionCardProps {
  const SessionCardProps({
    required this.name,
    required this.typeName,
    this.isLive = false,
    this.repoCount = 0,
  });
  final String name;
  final String typeName;
  final bool isLive;
  final int repoCount;

  factory SessionCardProps.fromJson(Map<String, dynamic> j) => SessionCardProps(
        name: j['name'] as String? ?? '',
        typeName: j['typeName'] as String? ?? '',
        isLive: j['isLive'] as bool? ?? j['isRunning'] as bool? ?? false,
        repoCount: j['repoCount'] as int? ?? 0,
      );
}
