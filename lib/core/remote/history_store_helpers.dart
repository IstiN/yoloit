import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yoloit/core/remote/yoloitd_models.dart';

abstract final class HistoryStoreHelpers {
  static final RegExp _unsafeSegmentChars = RegExp(r'[^a-zA-Z0-9._-]');

  static String safeSegment(String value) {
    return value.replaceAll(_unsafeSegmentChars, '_');
  }

  static String historyDirPath(String root, String boardId, DateTime timestamp) {
    final utc = timestamp.toUtc();
    return p.join(
      root,
      safeSegment(boardId),
      'events',
      utc.year.toString().padLeft(4, '0'),
      utc.month.toString().padLeft(2, '0'),
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

  static const JsonEncoder _prettyEncoder = JsonEncoder.withIndent('  ');

  static Future<void> writeJsonAtomic(File file, Object? value) async {
    await file.parent.create(recursive: true);
    // Unique tmp name per write: concurrent writers must not fight over the
    // same tmp file (the loser's rename would fail with "file not found").
    final tmp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.$pid.tmp',
    );
    await tmp.writeAsString(_prettyEncoder.convert(value), flush: true);
    const maxAttempts = 6;
    for (var attempt = 0;; attempt++) {
      try {
        // POSIX rename atomically replaces the destination.
        await tmp.rename(file.path);
        return;
      } on FileSystemException {
        // Windows: rename fails when the target exists or is transiently
        // locked (Defender scanning the fresh file, a concurrent reader).
        // Delete the target and retry with a short backoff so transients
        // clear (IstiN/yoloit#17 logs: single retry was not enough).
        if (attempt >= maxAttempts) rethrow;
        try {
          await file.delete();
        } catch (_) {}
        await Future<void>.delayed(Duration(milliseconds: 25 * (attempt + 1)));
      }
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
