/// Interactive nodes discovered in a declarative UI tree.
class UiViewActionRef {
  const UiViewActionRef({
    required this.actionId,
    required this.nodeType,
    this.label = '',
    this.payload,
  });

  final String actionId;
  final String nodeType;
  final String label;
  final Object? payload;
}

class UiViewActions {
  UiViewActions._();

  static const Set<String> _interactiveTypes = <String>{
    'button',
    'textButton',
    'outlinedButton',
    'iconButton',
    'gestureDetector',
    'chart',
    'listTile',
    'chip',
    'inkWell',
    'switch',
    'checkbox',
    'slider',
    'dropdown',
    'textField',
  };

  static List<UiViewActionRef> collectFromTree(Map<String, dynamic> tree) {
    final refs = <UiViewActionRef>[];
    void walk(dynamic node) {
      if (node is! Map) return;
      final map = Map<String, dynamic>.from(node.cast<String, dynamic>());
      final type = map['type'] as String? ?? '';
      if (_shouldCollect(map, type)) {
        refs.add(
          UiViewActionRef(
            actionId: _actionId(map, type),
            nodeType: type,
            label: _label(map),
            payload: map['payload'],
          ),
        );
      }
      for (final child in map['children'] as List? ?? const <dynamic>[]) {
        walk(child);
      }
      final child = map['child'];
      if (child is Map) walk(child);
    }

    walk(tree);
    return refs;
  }

  static bool _shouldCollect(Map<String, dynamic> map, String type) {
    if (!_interactiveTypes.contains(type)) return false;
    if (type == 'button' ||
        type == 'textButton' ||
        type == 'outlinedButton' ||
        type == 'iconButton' ||
        type == 'chip') {
      return true;
    }
    return map['onTap'] != null ||
        map['onChange'] != null ||
        map['onChanged'] != null ||
        map['onSubmit'] != null ||
        map['onPress'] != null;
  }

  static List<String> uniqueActionIds(List<UiViewActionRef> refs) {
    final seen = <String>{};
    final out = <String>[];
    for (final ref in refs) {
      if (seen.add(ref.actionId)) out.add(ref.actionId);
    }
    return out;
  }

  static String defaultScript(String actionId) =>
      '''// onTap / onChange: $actionId
// yoloit.set('key', value)  yoloit.get('key')  yoloit.inc('taps')
// yoloit.toggle('flag')  yoloit.merge({a:1})  yoloit.toast('Saved')
yoloit.inc('taps');
yoloit.set('lastAction', actionId);
''';

  static String _actionId(Map<String, dynamic> map, String type) {
    final raw =
        map['onTap'] ??
        map['onChange'] ??
        map['onChanged'] ??
        map['onSubmit'] ??
        map['onPress'] ??
        map['action'] ??
        map['actionId'];
    if (raw == null &&
        (type == 'button' ||
            type == 'textButton' ||
            type == 'outlinedButton' ||
            type == 'iconButton' ||
            type == 'chip')) {
      return '_tap';
    }
    final text = '$raw'.trim();
    return text.isEmpty ? '_tap' : text;
  }

  static String _label(Map<String, dynamic> map) {
    return map['data'] as String? ??
        map['label'] as String? ??
        map['text'] as String? ??
        map['icon'] as String? ??
        '';
  }
}
