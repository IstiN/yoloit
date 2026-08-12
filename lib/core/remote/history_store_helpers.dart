import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yoloit/core/remote/yoloitd_models.dart';

abstract final class HistoryStoreHelpers {
  static String safeSegment(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  static String historyDirPath(String root, String boardId, DateTime timestamp) {
    return p.join(
      root,
      safeSegment(boardId),
      'events',
      timestamp.toUtc().year.toString().padLeft(4, '0'),
      timestamp.toUtc().month.toString().padLeft(2, '0'),
    );
  }

  static String historyFileName(String opId, String actorId) {
    return '${safeSegment(opId)}_${safeSegment(actorId)}.json';
  }

  static Future<void> appendEvent({
    required String rootPath,
    required String boardId,
    required DateTime timestamp,
    required String opId,
    required String actorId,
    required Map<String, dynamic> json,
  }) async {
    final dirPath = historyDirPath(rootPath, boardId, timestamp);
    final dir = Directory(dirPath);
    await dir.create(recursive: true);
    final file = File(p.join(dirPath, historyFileName(opId, actorId)));
    await writeJsonAtomic(file, json);
  }

  static final JsonEncoder _prettyEncoder = const JsonEncoder.withIndent('  ');

  static Future<void> writeJsonAtomic(File file, Object? value) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(_prettyEncoder.convert(value), flush: true);
    // POSIX rename atomically replaces the destination — no need for a
    // separate exists()+delete() round-trip.
    try {
      await tmp.rename(file.path);
    } catch (_) {
      // On Windows rename fails if the target exists; fall back to delete+rename.
      try { await file.delete(); } catch (_) {}
      await tmp.rename(file.path);
    }
  }

  static Future<List<T>> loadHistoryEvents<T extends RemoteHistoryEvent>(
    Directory root,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    if (!await root.exists()) return const [];
    final events = <T>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final decoded = jsonDecode(await entity.readAsString());
      if (decoded is Map) {
        events.add(fromJson(Map<String, dynamic>.from(decoded)));
      }
    }
    events.sort((a, b) {
      final byRevision = a.revision.compareTo(b.revision);
      if (byRevision != 0) return byRevision;
      return a.opId.compareTo(b.opId);
    });
    return events;
  }
}
