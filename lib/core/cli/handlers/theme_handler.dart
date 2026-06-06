import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show Brightness, Color;
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';

Future<shelf.Response> handleTheme(
  String method,
  List<String> path,
  shelf.Request request, {
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) notFound,
}) async {
  final tm = ThemeManager.instance;

  // GET /api/theme → current theme info
  if (path.isEmpty && method == 'GET') {
    final activeCustomId = tm.activeCustomThemeId;
    String name;
    if (activeCustomId != null) {
      final custom =
          tm.customThemes.where((t) => t.id == activeCustomId).firstOrNull;
      name = custom?.name ?? 'Custom';
    } else {
      name = tm.current.label;
    }
    return json({
      'preset': tm.current.name,
      'name': name,
      'brightness': tm.isDark ? 'dark' : 'light',
      'customThemeId': activeCustomId,
      'hasOverrides': tm.hasOverrides,
      'overrides': tm.colorOverrides.map(
        (k, v) =>
            MapEntry(k, '#${v.toARGB32().toRadixString(16).padLeft(8, '0')}'),
      ),
    });
  }

  // GET /api/theme/presets → list all presets (built-in + custom)
  if (path.length == 1 && path[0] == 'presets' && method == 'GET') {
    final builtIn =
        AppThemePreset.values
            .map(
              (p) => {
                'id': p.name,
                'name': p.label,
                'type': 'builtin',
                'brightness':
                    (p.defaultBrightness ?? Brightness.dark) ==
                            Brightness.light
                        ? 'light'
                        : 'dark',
              },
            )
            .toList();
    final custom =
        tm.customThemes
            .map(
              (c) => {
                'id': c.id,
                'name': c.name,
                'type': 'custom',
                'brightness':
                    c.brightness == Brightness.light ? 'light' : 'dark',
              },
            )
            .toList();
    return json({'presets': [...builtIn, ...custom]});
  }

  // POST /api/theme/set { preset: "neonPurple" } or { customId: "custom_xxx" }
  if (path.length == 1 && path[0] == 'set' && method == 'POST') {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final presetName = body['preset'] as String?;
    final customId = body['customId'] as String?;
    if (presetName != null) {
      final preset =
          AppThemePreset.values.where((p) => p.name == presetName).firstOrNull;
      if (preset == null) {
        return json(errorJson('Unknown preset: $presetName'));
      }
      await tm.setTheme(preset);
      await tm.clearColorOverrides();
      return json(okJson({'message': 'Theme set to ${preset.label}'}));
    } else if (customId != null) {
      await tm.setCustomTheme(customId);
      await tm.clearColorOverrides();
      return json(okJson({'message': 'Custom theme activated: $customId'}));
    }
    return json(errorJson('Provide "preset" or "customId"'));
  }

  // POST /api/theme/brightness { brightness: "dark"|"light" }
  if (path.length == 1 && path[0] == 'brightness' && method == 'POST') {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final b = body['brightness'] as String?;
    if (b == 'dark') {
      await tm.setBrightness(Brightness.dark);
    } else if (b == 'light') {
      await tm.setBrightness(Brightness.light);
    } else {
      return json(errorJson('Provide brightness: "dark" or "light"'));
    }
    return json(okJson({'brightness': b}));
  }

  // POST /api/theme/color { slot: "primary", color: "#FF548AF7" }
  if (path.length == 1 && path[0] == 'color' && method == 'POST') {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final slot = body['slot'] as String?;
    final hex = body['color'] as String?;
    if (slot == null || hex == null) {
      return json(errorJson('Provide "slot" and "color"'));
    }
    final h = hex.replaceFirst('#', '');
    late Color color;
    if (h.length == 6) {
      color = Color(int.parse('FF$h', radix: 16));
    } else if (h.length == 8) {
      color = Color(int.parse(h, radix: 16));
    } else {
      return json(errorJson('Invalid hex color: $hex'));
    }
    await tm.setColorOverride(slot, color);
    return json(okJson({'message': 'Color override set for $slot'}));
  }

  // DELETE /api/theme/color?slot=primary — remove a color override
  if (path.length == 1 && path[0] == 'color' && method == 'DELETE') {
    final slot = request.url.queryParameters['slot'];
    if (slot == null) {
      return json(errorJson('Provide ?slot= query param'));
    }
    await tm.removeColorOverride(slot);
    return json(okJson({'message': 'Color override removed for $slot'}));
  }

  // POST /api/theme/reset-colors — clear all overrides
  if (path.length == 1 && path[0] == 'reset-colors' && method == 'POST') {
    await tm.clearColorOverrides();
    return json(okJson({'message': 'All color overrides cleared'}));
  }

  // POST /api/theme/save { name: "My Theme" } — save current as custom preset
  if (path.length == 1 && path[0] == 'save' && method == 'POST') {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final name = body['name'] as String?;
    if (name == null || name.trim().isEmpty) {
      return json(errorJson('Provide "name"'));
    }
    final id = await tm.saveCurrentAsPreset(name.trim());
    return json(okJson({'id': id, 'message': 'Preset saved: ${name.trim()}'}));
  }

  // GET /api/theme/export → current theme as JSON
  if (path.length == 1 && path[0] == 'export' && method == 'GET') {
    return shelf.Response.ok(
      tm.exportCurrentAsJson(),
      headers: {'content-type': 'application/json'},
    );
  }

  // POST /api/theme/import { path: "/path/to/file.json" }
  if (path.length == 1 && path[0] == 'import' && method == 'POST') {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final filePath = body['path'] as String?;
    if (filePath == null) {
      return json(errorJson('Provide "path" to theme file'));
    }
    try {
      final id = await tm.importThemeFile(filePath);
      await tm.setCustomTheme(id);
      return json(okJson({'id': id, 'message': 'Theme imported and activated'}));
    } catch (e) {
      return json(errorJson('Import failed: $e'));
    }
  }

  // DELETE /api/theme/custom?id=xxx — delete a custom theme
  if (path.length == 1 && path[0] == 'custom' && method == 'DELETE') {
    final id = request.url.queryParameters['id'];
    if (id == null) {
      return json(errorJson('Provide ?id= query param'));
    }
    await tm.deleteCustomTheme(id);
    return json(okJson({'message': 'Custom theme deleted'}));
  }

  // GET /api/theme/colors → all effective color slots
  if (path.length == 1 && path[0] == 'colors' && method == 'GET') {
    final scheme = tm.effectiveScheme;
    return json({'colors': scheme.toJson()});
  }

  // GET /api/theme/slots → available color slot names grouped by category
  if (path.length == 1 && path[0] == 'slots' && method == 'GET') {
    return json({
      'categories': ThemeManager.colorCategories.map(
        (cat, slots) => MapEntry(cat, slots.map((s) => s.key).toList()),
      ),
    });
  }

  return notFound(unknownRoute('theme'));
}
