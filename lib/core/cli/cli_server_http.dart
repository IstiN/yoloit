import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:shelf/shelf.dart' as shelf;

/// Schedule a UI frame so Flutter repaints after a cubit mutation.
void cliScheduleRebuild() {
  try {
    SchedulerBinding.instance.scheduleFrame();
  } catch (_) {}
}

Future<Map<String, dynamic>> cliReadJsonBody(shelf.Request request) async {
  try {
    final raw = await request.readAsString();
    if (raw.isEmpty) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

shelf.Response cliJson(Object data) => shelf.Response.ok(
  jsonEncode(data),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

shelf.Response cliError(String msg) => shelf.Response(
  400,
  body: jsonEncode({'ok': false, 'error': msg}),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

shelf.Response cliNotFound(String msg) => shelf.Response.notFound(
  jsonEncode({'ok': false, 'error': msg}),
  headers: {'content-type': 'application/json; charset=utf-8'},
);
