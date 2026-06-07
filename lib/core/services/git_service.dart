import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:process_run/process_run.dart';

class GitService {
  const GitService._();
  static const GitService instance = GitService._();

  Future<String?> getBranch(String workspacePath) async {
    try {
      final result = await runExecutableArguments(
        'git',
        ['rev-parse', '--abbrev-ref', 'HEAD'],
        workingDirectory: workspacePath,
      );
      return result.stdout.toString().trim();
    } catch (_) {
      return null;
    }
  }

  Future<({int added, int removed})> getDiffStats(String workspacePath) async {
    try {
      final result = await runExecutableArguments(
        'git',
        ['diff', '--shortstat', 'HEAD'],
        workingDirectory: workspacePath,
      );
      final output = result.stdout.toString().trim();
      return _parseShortstat(output);
    } catch (_) {
      return (added: 0, removed: 0);
    }
  }

  Future<String> getDiff(String workspacePath, String filePath) async {
    try {
      final result = await runExecutableArguments(
        'git',
        ['diff', 'HEAD', '--', filePath],
        workingDirectory: workspacePath,
      );
      final output = result.stdout.toString();
      if (output.isNotEmpty) return output;

      // Try staged diff
      final staged = await runExecutableArguments(
        'git',
        ['diff', '--cached', '--', filePath],
        workingDirectory: workspacePath,
      );
      if (staged.stdout.toString().isNotEmpty) return staged.stdout.toString();

      // Fallback for untracked files (no commits yet): diff against /dev/null
      final untracked = await runExecutableArguments(
        'git',
        ['diff', '--no-index', '--', '/dev/null', filePath],
        workingDirectory: workspacePath,
      );
      return untracked.stdout.toString();
    } catch (_) {
      return '';
    }
  }

  Future<List<GitFileStatus>> getStatus(String workspacePath) async {
    try {
      final result = await runExecutableArguments(
        'git',
        ['status', '--porcelain'],
        workingDirectory: workspacePath,
      );
      return _parseStatus(result.stdout.toString());
    } catch (_) {
      return [];
    }
  }

  Future<bool> stageFile(String workspacePath, String filePath) async {
    try {
      final result = await runExecutableArguments(
        'git',
        ['add', filePath],
        workingDirectory: workspacePath,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unstageFile(String workspacePath, String filePath) async {
    try {
      final result = await runExecutableArguments(
        'git',
        ['restore', '--staged', filePath],
        workingDirectory: workspacePath,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isGitRepo(String path) async {
    try {
      final dir = Directory('$path/.git');
      return dir.existsSync();
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  ({int added, int removed}) parseShortstatForTest(String shortstat) =>
      _parseShortstat(shortstat);

  ({int added, int removed}) _parseShortstat(String shortstat) {
    if (shortstat.isEmpty) return (added: 0, removed: 0);
    int added = 0;
    int removed = 0;
    final addedMatch = RegExp(r'(\d+) insertion').firstMatch(shortstat);
    final removedMatch = RegExp(r'(\d+) deletion').firstMatch(shortstat);
    if (addedMatch != null) added = int.tryParse(addedMatch.group(1)!) ?? 0;
    if (removedMatch != null) removed = int.tryParse(removedMatch.group(1)!) ?? 0;
    return (added: added, removed: removed);
  }

  @visibleForTesting
  List<GitFileStatus> parseStatusForTest(String statusOutput) =>
      _parseStatus(statusOutput);

  List<GitFileStatus> _parseStatus(String statusOutput) {
    if (statusOutput.isEmpty) return [];
    return statusOutput.split('\n').where((l) => l.length >= 3).map((line) {
      final indexStatus = line[0];
      final workingStatus = line[1];
      final path = line.substring(3).trim();
      return GitFileStatus(
        path: path,
        indexStatus: indexStatus,
        workingTreeStatus: workingStatus,
      );
    }).toList();
  }
}

class GitFileStatus {
  const GitFileStatus({
    required this.path,
    required this.indexStatus,
    required this.workingTreeStatus,
  });

  final String path;
  final String indexStatus;
  final String workingTreeStatus;

  bool get isModified =>
      indexStatus == 'M' || workingTreeStatus == 'M';
  bool get isAdded =>
      indexStatus == 'A' || (indexStatus == '?' && workingTreeStatus == '?');
  bool get isDeleted =>
      indexStatus == 'D' || workingTreeStatus == 'D';
  bool get isStaged => indexStatus != ' ' && indexStatus != '?';
}
