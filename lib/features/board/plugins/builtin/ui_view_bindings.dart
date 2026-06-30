import 'package:yoloit/features/board/plugins/builtin/ui_view_field_registry.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_tree_normalizer.dart';

/// Resolves `{{key}}` placeholders in declarative UI trees from panel storage.
class UiViewBindings {
  UiViewBindings._();

  static const Set<String> _textKeys = <String>{
    'data',
    'label',
    'text',
    'hint',
    'tooltip',
    'title',
    'subtitle',
    'value',
    'initialValue',
    'message',
  };

  static Map<String, dynamic> storageFromState(Map<String, dynamic> state) {
    final raw = state['_storage'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw.cast<String, dynamic>());
    }
    return <String, dynamic>{};
  }

  static Map<String, String> scriptsFromState(Map<String, dynamic> state) {
    final raw = state['_scripts'];
    if (raw is! Map) return <String, String>{};
    final out = <String, String>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is String && value.trim().isNotEmpty) {
        out['${entry.key}'] = value;
      }
    }
    return out;
  }

  static Map<String, dynamic> withLiveFields(
    Map<String, dynamic> state,
    UiViewFieldRegistry? registry,
  ) {
    if (registry == null) return state;
    final live = registry.snapshot();
    if (live.isEmpty) return state;
    final storage = storageFromState(state);
    return <String, dynamic>{
      ...state,
      '_storage': <String, dynamic>{...storage, ...live},
    };
  }

  /// Seeds storage keys from `textField` nodes that declare `id` / `storageKey`.
  static Map<String, dynamic> seedFieldsFromTree(
    Map<String, dynamic> tree,
    Map<String, dynamic> storage,
  ) {
    final next = Map<String, dynamic>.from(storage);
    void walk(dynamic node) {
      if (node is! Map) return;
      final map = Map<String, dynamic>.from(node.cast<String, dynamic>());
      final type = map['type'] as String? ?? '';
      if (type == 'textField') {
        final id =
            map['storageKey'] as String? ??
            map['id'] as String? ??
            map['name'] as String?;
        if (id != null && id.isNotEmpty && !next.containsKey(id)) {
          final raw =
              map['initialValue'] as String? ?? map['value'] as String? ?? '';
          final resolved = resolveString(raw, next);
          if (resolved.isNotEmpty) {
            next[id] = resolved;
          }
        }
      }
      for (final child in map['children'] as List? ?? const <dynamic>[]) {
        walk(child);
      }
      final child = map['child'];
      if (child is Map) walk(child);
    }

    walk(UiViewTreeNormalizer.normalize(tree));
    return next;
  }

  static Map<String, dynamic> applyTap({
    required Map<String, dynamic> state,
    required String actionId,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> Function({
      required String script,
      required Map<String, dynamic> storage,
      required String actionId,
      required Map<String, dynamic> payload,
    })
    runScript,
  }) {
    final storage = storageFromState(state);
    final scripts = scriptsFromState(state);
    final script = scripts[actionId];
    final nextStorage =
        script != null
            ? runScript(
              script: script,
              storage: storage,
              actionId: actionId,
              payload: payload,
            )
            : applyEventToStorage(
              storage: storage,
              actionId: actionId,
              payload: payload,
            );
    return <String, dynamic>{
      ...state,
      '_storage': nextStorage,
      '_lastEvent': <String, dynamic>{
        'actionId': actionId,
        'payload': Map<String, dynamic>.from(payload),
        'at': DateTime.now().toIso8601String(),
      },
    };
  }

  static Map<String, dynamic> applyFieldStorage({
    required Map<String, dynamic> state,
    required String key,
    required Object? value,
  }) {
    final storage = storageFromState(state);
    return <String, dynamic>{
      ...state,
      '_storage': <String, dynamic>{...storage, key: value},
    };
  }

  static Map<String, dynamic> applyEventToStorage({
    required Map<String, dynamic> storage,
    required String actionId,
    required Map<String, dynamic> payload,
  }) {
    final next = Map<String, dynamic>.from(storage);
    if (payload.isNotEmpty) {
      next.addAll(payload);
    }
    next['lastAction'] = actionId;
    if (!_isFieldInputAction(actionId)) {
      final taps = next['taps'];
      next['taps'] = (taps is num ? taps.toInt() : 0) + 1;
    }
    return next;
  }

  static bool _isFieldInputAction(String actionId) =>
      actionId == '_field' || actionId.endsWith('_input') || actionId.endsWith('Input');

  static Map<String, dynamic> applyTree(
    Map<String, dynamic> tree,
    Map<String, dynamic> storage,
  ) {
    final normalized = UiViewTreeNormalizer.normalize(tree);
    return _walkMap(normalized, storage);
  }

  static bool shouldShowNode(
    Map<String, dynamic> node,
    Map<String, dynamic> storage,
  ) {
    if (node['visible'] == false) return false;
    final visible = node['visible'];
    if (visible is String) {
      final resolved = resolveString(visible, storage).toLowerCase();
      if (resolved == 'false' || resolved == '0' || resolved.isEmpty) {
        return false;
      }
    }
    final when = node['when'];
    if (when == false) return false;
    if (when is String) {
      final resolved = resolveString(when, storage).toLowerCase();
      if (resolved == 'false' || resolved == '0' || resolved.isEmpty) {
        return false;
      }
    }
    return true;
  }

  static Map<String, dynamic> _walkMap(
    Map<String, dynamic> node,
    Map<String, dynamic> storage,
  ) {
    if (!shouldShowNode(node, storage)) {
      return <String, dynamic>{'type': 'sizedBox', 'height': 0};
    }
    final out = <String, dynamic>{};
    for (final entry in node.entries) {
      final key = entry.key;
      final value = entry.value;
      if (_textKeys.contains(key) && value is String) {
        out[key] = resolveString(value, storage);
      } else if (key == 'children' && value is List) {
        out[key] =
            value
                .map((item) => _resolveValue(item, storage))
                .where((item) {
                  if (item is Map &&
                      item['type'] == 'sizedBox' &&
                      item['height'] == 0 &&
                      item['width'] == null &&
                      item['child'] == null) {
                    return false;
                  }
                  return true;
                })
                .toList();
      } else {
        out[key] = _resolveValue(value, storage);
      }
    }
    return out;
  }

  static dynamic _resolveValue(
    Object? value,
    Map<String, dynamic> storage,
  ) {
    if (value is Map) {
      return _walkMap(Map<String, dynamic>.from(value.cast<String, dynamic>()), storage);
    }
    if (value is List) {
      return value.map((item) => _resolveValue(item, storage)).toList();
    }
    return value;
  }

  static String resolveString(String template, Map<String, dynamic> storage) {
    return template.replaceAllMapped(RegExp(r'\{\{([^}]+)\}\}'), (match) {
      final key = match.group(1)?.trim();
      if (key == null || key.isEmpty) return '';
      final value = storage[key];
      if (value == null) return '';
      return '$value';
    });
  }
}
