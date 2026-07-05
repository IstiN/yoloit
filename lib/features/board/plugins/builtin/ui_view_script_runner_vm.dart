import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_bindings.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_script_context.dart';

/// Runs small per-action JavaScript snippets for [board.ui] tap handlers.
class UiViewScriptRunner {
  UiViewScriptRunner._();

  static final UiViewScriptRunner instance = UiViewScriptRunner._();

  JavascriptRuntime? _runtime;

  Map<String, dynamic> runAction({
    required String script,
    required Map<String, dynamic> storage,
    required String actionId,
    required Map<String, dynamic> payload,
  }) {
    final trimmed = script.trim();
    if (trimmed.isEmpty) {
      return UiViewBindings.applyEventToStorage(
        storage: storage,
        actionId: actionId,
        payload: payload,
      );
    }

    try {
      _runtime ??= getJavascriptRuntime();
      final wrapped =
          '(function(){'
          'var storage = ${jsonEncode(storage)};'
          'var payload = ${jsonEncode(payload)};'
          'var actionId = ${jsonEncode(actionId)};'
          '$kUiViewScriptBootstrap'
          'try { $trimmed } catch (e) { storage._scriptError = String(e); }'
          'return JSON.stringify(storage);'
          '})()';
      final result = _runtime!.evaluate(wrapped);
      if (result.isError) {
        return <String, dynamic>{
          ...storage,
          '_scriptError': result.stringResult,
          'lastAction': actionId,
        };
      }
      final decoded = jsonDecode(result.stringResult);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      }
    } catch (error) {
      return <String, dynamic>{
        ...storage,
        '_scriptError': '$error',
        'lastAction': actionId,
      };
    }

    return UiViewBindings.applyEventToStorage(
      storage: storage,
      actionId: actionId,
      payload: payload,
    );
  }
}
