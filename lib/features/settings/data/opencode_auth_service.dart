import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

// ─────────────────────────────────────────────────────────────────────────────
// OpenCode Auth Service
//
// Reads ~/.local/share/opencode/auth.json (XDG data dir) to discover
// which providers the user has configured in opencode.
//
// auth.json format:
//   { "openrouter": { "type": "api", "key": "sk-or-..." }, ... }
//
// This allows YoLoIT to surface models from configured providers
// when using the OpenCode CLI backend.
// ─────────────────────────────────────────────────────────────────────────────

class OpenCodeAuthService {
  OpenCodeAuthService._();
  static final instance = OpenCodeAuthService._();

  /// Returns a map of providerID → apiKey for all providers configured in opencode.
  Future<Map<String, String>> configuredProviders() async {
    final file = _authFile();
    if (file == null || !file.existsSync()) return const {};

    try {
      final content = await file.readAsString();
      final data = jsonDecode(content);
      if (data is! Map) return const {};

      final result = <String, String>{};
      for (final entry in data.entries) {
        final providerId = entry.key as String? ?? '';
        if (providerId.isEmpty) continue;
        final value = entry.value;
        if (value is Map) {
          final key = value['key'] as String? ?? '';
          if (key.isNotEmpty) result[providerId] = key;
        }
      }
      debugPrint('[OpenCodeAuth] configured providers: ${result.keys.toList()}');
      return result;
    } catch (e) {
      debugPrint('[OpenCodeAuth] failed to read auth.json: $e');
      return const {};
    }
  }

  /// Returns just the list of configured provider IDs.
  Future<List<String>> configuredProviderIds() async {
    final map = await configuredProviders();
    return map.keys.toList();
  }

  File? _authFile() {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return null;

    final xdgDataHome =
        Platform.environment['XDG_DATA_HOME'] ??
        p.join(home, '.local', 'share');

    return File(p.join(xdgDataHome, 'opencode', 'auth.json'));
  }
}
