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
  static const _flushInterval = Duration(seconds: 2);
  // How many bytes may be appended before the next rotation size check.
  // Checking file length on every flush would defeat the purpose of
  // append-only writes; 1 MB of appends between checks keeps I/O negligible.
  static const _rotationCheckIntervalBytes = 1024 * 1024;

  bool _enabled = false;
  bool get enabled => _enabled;

  final List<String> _buffer = [];
  Timer? _flushTimer;
  bool _flushing = false;
  int _bytesSinceRotationCheck = 0;

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
    _flushTimer?.cancel();
    _buffer.clear();
    _bytesSinceRotationCheck = 0;
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
    } else {
      // Debounce: under load (board pan/zoom, terminal output) dozens of
      // lines arrive per second — batch them into one append per interval
      // instead of hitting the disk on every line.
      _flushTimer ??= Timer(_flushInterval, () {
        _flushTimer = null;
        unawaited(_flushBuffer());
      });
    }
  }

  Future<void> _flushBuffer() async {
    // Serialize flushes: a flush already in flight will pick up whatever
    // lands in the buffer afterwards via the timer / line-count trigger.
    if (_buffer.isEmpty || _flushing) return;
    _flushing = true;
    final lines = List<String>.of(_buffer);
    _buffer.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    final path = await logPath;
    final storage = FileStorageAdapter.instance;
    try {
      final chunk = '${lines.join('\n')}\n';
      _bytesSinceRotationCheck += chunk.length;
      if (_bytesSinceRotationCheck >= _rotationCheckIntervalBytes) {
        _bytesSinceRotationCheck = 0;
        await _rotateIfNeeded(storage, path);
      }
      // Append-only: never read the whole log back just to add lines.
      await storage.appendString(path, chunk);
    } catch (_) {
      // Ignore — file logging unavailable (e.g. permission issue).
    } finally {
      _flushing = false;
    }
  }

  /// Trims the log to the most recent half when it exceeds [_maxBytes].
  /// Runs at most once per [_rotationCheckIntervalBytes] appended bytes.
  Future<void> _rotateIfNeeded(
    FileStorageAdapter storage,
    String path,
  ) async {
    final size = await storage.length(path);
    if (size == null || size <= _maxBytes) return;
    final existing = await storage.readString(path) ?? '';
    if (existing.length <= _maxBytes) return;
    const keep = _maxBytes ~/ 2;
    await storage.writeString(path, existing.substring(existing.length - keep));
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
