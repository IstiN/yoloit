import 'dart:convert';

/// Plugin-owned history contract for panel state.
///
/// Every panel plugin gets a history adapter through [BoardPanelPlugin]. Most
/// plugins can use [JsonBoardPanelHistoryAdapter]; complex plugins can override
/// it when they need entity-level restore or want to omit volatile fields.
abstract class BoardPanelHistoryAdapter {
  const BoardPanelHistoryAdapter();

  Map<String, dynamic> snapshotState(Map<String, dynamic> state);

  Map<String, dynamic> restoreState(Map<String, dynamic> snapshot);

  Map<String, dynamic> diffState({
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
  });

  Map<String, dynamic> applyPatch({
    required Map<String, dynamic> state,
    required Map<String, dynamic> patch,
  });

  Map<String, dynamic> invertPatch(Map<String, dynamic> patch);
}

class JsonBoardPanelHistoryAdapter extends BoardPanelHistoryAdapter {
  const JsonBoardPanelHistoryAdapter();

  @override
  Map<String, dynamic> snapshotState(Map<String, dynamic> state) {
    return _cloneMap(state);
  }

  @override
  Map<String, dynamic> restoreState(Map<String, dynamic> snapshot) {
    return _cloneMap(snapshot);
  }

  @override
  Map<String, dynamic> diffState({
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
  }) {
    return {'before': snapshotState(before), 'after': snapshotState(after)};
  }

  @override
  Map<String, dynamic> applyPatch({
    required Map<String, dynamic> state,
    required Map<String, dynamic> patch,
  }) {
    final after = patch['after'];
    if (after is Map) {
      return restoreState(Map<String, dynamic>.from(after));
    }
    return snapshotState(state);
  }

  @override
  Map<String, dynamic> invertPatch(Map<String, dynamic> patch) {
    return {'before': patch['after'], 'after': patch['before']};
  }

  static Map<String, dynamic> _cloneMap(Map<String, dynamic> value) {
    return jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }
}
