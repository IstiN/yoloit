import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/services/app_logger.dart';

class SupportLogService {
  SupportLogService._();

  static final instance = SupportLogService._();
  static const _maxEntries = 600;

  final Queue<String> _entries = Queue<String>();

  void add(String category, String message) {
    final line = '${DateTime.now().toIso8601String()} [$category] $message';
    _entries.addLast(line);
    while (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }
    debugPrint('[SupportLog] [$category] $message');
  }

  String get memoryLog {
    if (_entries.isEmpty) return '(no support events captured)';
    return _entries.join('\n');
  }

  void clearMemoryLog() {
    _entries.clear();
  }

  Future<String> buildCopyPayload() async {
    final appLog = await AppLogger.instance.readLog();
    final path = await AppLogger.instance.logPath;
    return [
      'YoLoIT Support Logs',
      'Generated: ${DateTime.now().toIso8601String()}',
      'App log path: $path',
      '',
      '== Recent support events ==',
      memoryLog,
      '',
      '== App log ==',
      appLog,
    ].join('\n');
  }
}
