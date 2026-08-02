import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show Brightness, Color;
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';

/// Shared context passed to every extracted theme route handler.
class _ThemeContext {
  const _ThemeContext({
    required this.tm,
    required this.request,
    required this.json,
  });

  final ThemeManager tm;
  final shelf.Request request;
  final shelf.Response Function(Object) json;
}

typedef _ThemeRouteHandler = Future<shelf.Response> Function(_ThemeContext ctx);

/// A single route entry: exact method + path-segment match → handler.
class _ThemeRoute {
  const _ThemeRoute(this.method, this.segments, this.handler);

  final String method;
  final List<String> segments;
  final _ThemeRouteHandler handler;

  bool matches(String method, List<String> path) {
    if (this.method != method || path.length != segments.length) {
      return false;
    }
    for (var i = 0; i < segments.length; i++) {
      if (path[i] != segments[i]) {
        return false;
      }
    }
    return true;
  }
}

// Route order must match the original if-chain exactly.
final List<_ThemeRoute> _themeRoutes = [
  const _ThemeRoute('GET', [], _getTheme),
  const _ThemeRoute('GET', ['presets'], _getThemePresets),
  const _ThemeRoute('POST', ['set'], _setTheme),
  const _ThemeRoute('POST', ['brightness'], _setThemeBrightness),
  const _ThemeRoute('POST', ['color'], _setThemeColor),
  const _ThemeRoute('DELETE', ['color'], _deleteThemeColor),
  const _ThemeRoute('POST', ['reset-colors'], _resetThemeColors),
  const _ThemeRoute('POST', ['save'], _saveTheme),
  const _ThemeRoute('GET', ['export'], _exportTheme),
  const _ThemeRoute('POST', ['import'], _importTheme),
  const _ThemeRoute('DELETE', ['custom'], _deleteCustomTheme),
  const _ThemeRoute('GET', ['colors'], _getThemeColors),
  const _ThemeRoute('GET', ['slots'], _getThemeSlots),
];

Future<shelf.Response> handleTheme(
  String method,
  List<String> path,
  shelf.Request request, {
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) notFound,
  ThemeManager? themeManager,
}) async {
  final ctx = _ThemeContext(
    tm: themeManager ?? ThemeManager.instance,
    request: request,
    json: json,
  );
  for (final route in _themeRoutes) {
    if (route.matches(method, path)) {
      return route.handler(ctx);
    }
  }
  return notFound(unknownRoute('theme'));
}

// GET /api/theme → current theme info
Future<shelf.Response> _getTheme(_ThemeContext ctx) async {
  final tm = ctx.tm;
  final json = ctx.json;
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
      (k, v) => MapEntry(k, '#${v.toARGB32().toRadixString(16).padLeft(8, '0')}'),
    ),
  });
}

// GET /api/theme/presets → list all presets (built-in + custom)
Future<shelf.Response> _getThemePresets(_ThemeContext ctx) async {
  final tm = ctx.tm;
  final builtIn =
      AppThemePreset.values
          .map(
            (p) => {
              'id': p.name,
              'name': p.label,
              'type': 'builtin',
              'brightness':
                  (p.defaultBrightness ?? Brightness.dark) == Brightness.light
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
              'brightness': c.brightness == Brightness.light ? 'light' : 'dark',
            },
          )
          .toList();
  return ctx.json({'presets': [...builtIn, ...custom]});
}

// POST /api/theme/set { preset: "neonPurple" } or { customId: "custom_xxx" }
Future<shelf.Response> _setTheme(_ThemeContext ctx) async {
  final tm = ctx.tm;
  final json = ctx.json;
  final body =
      jsonDecode(await ctx.request.readAsString()) as Map<String, dynamic>;
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
Future<shelf.Response> _setThemeBrightness(_ThemeContext ctx) async {
  final tm = ctx.tm;
  final json = ctx.json;
  final body =
      jsonDecode(await ctx.request.readAsString()) as Map<String, dynamic>;
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
Future<shelf.Response> _setThemeColor(_ThemeContext ctx) async {
  final tm = ctx.tm;
  final json = ctx.json;
  final body =
      jsonDecode(await ctx.request.readAsString()) as Map<String, dynamic>;
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
Future<shelf.Response> _deleteThemeColor(_ThemeContext ctx) async {
  final tm = ctx.tm;
  final json = ctx.json;
  final slot = ctx.request.url.queryParameters['slot'];
  if (slot == null) {
    return json(errorJson('Provide ?slot= query param'));
  }
  await tm.removeColorOverride(slot);
  return json(okJson({'message': 'Color override removed for $slot'}));
}

// POST /api/theme/reset-colors — clear all overrides
Future<shelf.Response> _resetThemeColors(_ThemeContext ctx) async {
  await ctx.tm.clearColorOverrides();
  return ctx.json(okJson({'message': 'All color overrides cleared'}));
}

// POST /api/theme/save { name: "My Theme" } — save current as custom preset
Future<shelf.Response> _saveTheme(_ThemeContext ctx) async {
  final tm = ctx.tm;
  final json = ctx.json;
  final body =
      jsonDecode(await ctx.request.readAsString()) as Map<String, dynamic>;
  final name = body['name'] as String?;
  if (name == null || name.trim().isEmpty) {
    return json(errorJson('Provide "name"'));
  }
  final id = await tm.saveCurrentAsPreset(name.trim());
  return json(okJson({'id': id, 'message': 'Preset saved: ${name.trim()}'}));
}

// GET /api/theme/export → current theme as JSON
Future<shelf.Response> _exportTheme(_ThemeContext ctx) async {
  return shelf.Response.ok(
    ctx.tm.exportCurrentAsJson(),
    headers: {'content-type': 'application/json'},
  );
}

// POST /api/theme/import { path: "/path/to/file.json" }
Future<shelf.Response> _importTheme(_ThemeContext ctx) async {
  final tm = ctx.tm;
  final json = ctx.json;
  final body =
      jsonDecode(await ctx.request.readAsString()) as Map<String, dynamic>;
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
Future<shelf.Response> _deleteCustomTheme(_ThemeContext ctx) async {
  final tm = ctx.tm;
  final json = ctx.json;
  final id = ctx.request.url.queryParameters['id'];
  if (id == null) {
    return json(errorJson('Provide ?id= query param'));
  }
  await tm.deleteCustomTheme(id);
  return json(okJson({'message': 'Custom theme deleted'}));
}

// GET /api/theme/colors → all effective color slots
Future<shelf.Response> _getThemeColors(_ThemeContext ctx) async {
  final scheme = ctx.tm.effectiveScheme;
  return ctx.json({'colors': scheme.toJson()});
}

// GET /api/theme/slots → available color slot names grouped by category
Future<shelf.Response> _getThemeSlots(_ThemeContext ctx) async {
  return ctx.json({
    'categories': ThemeManager.colorCategories.map(
      (cat, slots) => MapEntry(cat, slots.map((s) => s.key).toList()),
    ),
  });
}
