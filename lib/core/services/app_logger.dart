import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';

/// Captures Flutter debug output and unhandled errors to a rotating log file.
///
/// Log file: `~/.config/yoloit/app.log` on desktop, scoped browser storage on
/// web (key derived from `logs/app.log`). Enabled/disabled via SharedPreferences
/// key [_enabledKey].
///
/// Usage:
/// ```dart
/// await AppLogger.instance.init();
/// AppLogger.instance.install(); // hooks debugPrint and FlutterError
/// ```
class AppLogger {
  AppLogger._();
  static final instance = AppLogger._();

  static const _enabledKey = 'app_logging_enabled_v1';
  static const _maxBytes = 5 * 1024 * 1024; // 5 MB
  static const _maxBufferLines = 50;

  bool _enabled = false;
  bool get enabled => _enabled;

  final List<String> _buffer = [];

  // Saved originals so we can restore on disable
  DebugPrintCallback? _originalDebugPrint;

  // ──────────────────────────────────────────────────────────── lifecycle ──

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true; // on by default
  }

  /// Hooks [debugPrint] and [FlutterError.onError]. Call once after [init].
  void install() {
    if (!_enabled) return;
    _hookDebugPrint();
    _hookFlutterError();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (value) {
      _hookDebugPrint();
      _hookFlutterError();
    } else {
      _unhookDebugPrint();
      await _flushBuffer();
    }
  }

  // ──────────────────────────────────────────────────────────── public ──

  /// Path to the current log file (may not exist yet if logging is off).
  Future<String> get logPath async {
    return p.join(PlatformDirs.instance.logsDir, 'app.log');
  }

  Future<String> readLog() async {
    await _flushBuffer();
    final path = await logPath;
    final raw = await FileStorageAdapter.instance.readString(path);
    if (raw == null || raw.isEmpty) return '(no log file)';
    return raw;
  }

  Future<void> clearLog() async {
    _buffer.clear();
    final path = await logPath;
    final storage = FileStorageAdapter.instance;
    if (await storage.exists(path)) await storage.delete(path);
  }

  // ──────────────────────────────────────────────────────── internals ──

  void _writeLine(String line) {
    if (!_enabled) return;
    final ts = DateTime.now().toIso8601String();
    _buffer.add('$ts  $line');
    if (_buffer.length >= _maxBufferLines) {
      unawaited(_flushBuffer());
    }
  }

  Future<void> _flushBuffer() async {
    if (_buffer.isEmpty) return;
    final lines = List<String>.of(_buffer);
    _buffer.clear();
    final path = await logPath;
    final storage = FileStorageAdapter.instance;
    try {
      final existing = await storage.readString(path) ?? '';
      var merged = existing.isEmpty ? lines.join('\n') : '$existing\n${lines.join('\n')}';
      // Approximate rotation: keep the most recent bytes if we exceed the limit.
      final bytes = merged.length;
      if (bytes > _maxBytes) {
        final keep = _maxBytes ~/ 2;
        merged = merged.substring(merged.length - keep);
      }
      await storage.writeString(path, merged);
    } catch (_) {
      // Ignore — file logging unavailable (e.g. permission issue).
    }
  }

  void _hookDebugPrint() {
    _originalDebugPrint ??= debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
      if (message != null) _writeLine(message);
    };
  }

  void _unhookDebugPrint() {
    if (_originalDebugPrint != null) {
      debugPrint = _originalDebugPrint!;
      _originalDebugPrint = null;
    }
  }

  void _hookFlutterError() {
    final original = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      original?.call(details);
      _writeLine('[FlutterError] ${details.exceptionAsString()}');
      _writeLine(details.stack.toString());
    };
  }
}
