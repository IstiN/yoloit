/// Normalizes declarative UI trees from LLMs (React/HTML habits, wrong types).
class UiViewTreeNormalizer {
  UiViewTreeNormalizer._();

  static Map<String, dynamic> normalize(Map<String, dynamic> tree) {
    return _normalizeNode(tree);
  }

  static Map<String, dynamic> _normalizeNode(Map<String, dynamic> node) {
    final out = Map<String, dynamic>.from(node);

    final rawType = out['type'];
    if (rawType is String) {
      out['type'] = _aliasType(rawType);
    }

    _aliasFields(out);

    final type = out['type'] as String? ?? '';
    if ((type == 'column' || type == 'row' || type == 'wrap') &&
        out['children'] == null &&
        out['child'] is Map) {
      out['children'] = <dynamic>[out.remove('child')];
    }

    if (out['children'] is List) {
      out['children'] =
          (out['children'] as List)
              .map((child) {
                if (child is Map) {
                  return _normalizeNode(
                    Map<String, dynamic>.from(child.cast<String, dynamic>()),
                  );
                }
                if (child is String) {
                  return <String, dynamic>{'type': 'text', 'data': child};
                }
                return child;
              })
              .toList();
    }

    if (out['child'] is Map) {
      out['child'] = _normalizeNode(
        Map<String, dynamic>.from(
          (out['child'] as Map).cast<String, dynamic>(),
        ),
      );
    }

    if (out['items'] is List && out['children'] == null) {
      out['children'] = out.remove('items');
    }

    return out;
  }

  static void _aliasFields(Map<String, dynamic> out) {
    if (out['content'] != null && out['data'] == null) {
      out['data'] = out.remove('content');
    }
    if (out['label'] != null &&
        out['data'] == null &&
        out['type'] == 'text') {
      out['data'] = out['label'];
    }

    final type = out['type'] as String? ?? '';
    if (type == 'container' || type == 'card' || type == 'animatedContainer') {
      if (out['backgroundColor'] != null && out['decoration'] == null) {
        out['decoration'] = <String, dynamic>{
          'color': out.remove('backgroundColor'),
        };
      }
      if (out['color'] != null &&
          out['decoration'] == null &&
          type == 'container') {
        out['decoration'] = <String, dynamic>{'color': out.remove('color')};
      }
    }

    if (type == 'button' ||
        type == 'textButton' ||
        type == 'outlinedButton') {
      if (out['title'] != null && out['data'] == null) {
        out['data'] = out.remove('title');
      }
      if (out['text'] != null && out['data'] == null) {
        out['data'] = out.remove('text');
      }
    }

    if (type == 'textField' || type == 'input') {
      out['type'] = 'textField';
      if (out['placeholder'] != null && out['hint'] == null) {
        out['hint'] = out.remove('placeholder');
      }
      if (out['value'] != null && out['initialValue'] == null) {
        out['initialValue'] = out.remove('value');
      }
      if (out['onChanged'] != null && out['onChange'] == null) {
        out['onChange'] = out.remove('onChanged');
      }
    }

    if (type == 'image' || type == 'networkImage' || type == 'img') {
      out['type'] = 'image';
      if (out['uri'] != null && out['url'] == null) {
        out['url'] = out.remove('uri');
      }
      if (out['source'] != null && out['url'] == null) {
        out['url'] = out.remove('source');
      }
    }

    if (type == 'svg' && out['markup'] != null && out['data'] == null) {
      out['data'] = out.remove('markup');
    }

    if ((type == 'switch' || type == 'checkbox' || type == 'slider') &&
        out['onChanged'] != null &&
        out['onChange'] == null) {
      out['onChange'] = out.remove('onChanged');
    }

    if (type == 'dropdown' || type == 'select') {
      out['type'] = 'dropdown';
      if (out['onChanged'] != null && out['onChange'] == null) {
        out['onChange'] = out.remove('onChanged');
      }
    }
  }

  static String _aliasType(String raw) {
    final key = raw.trim();
    return _typeAliases[key] ?? _typeAliases[key.toLowerCase()] ?? key;
  }

  static const Map<String, String> _typeAliases = <String, String>{
    'Text': 'text',
    'text': 'text',
    'Label': 'text',
    'label': 'text',
    'p': 'text',
    'span': 'text',
    'Button': 'button',
    'button': 'button',
    'ElevatedButton': 'button',
    'elevatedButton': 'button',
    'TextButton': 'textButton',
    'OutlinedButton': 'outlinedButton',
    'IconButton': 'iconButton',
    'View': 'column',
    'view': 'column',
    'div': 'column',
    'box': 'container',
    'Box': 'container',
    'Fragment': 'column',
    'ScrollView': 'scroll',
    'scrollView': 'scroll',
    'scroll': 'scroll',
    'SingleChildScrollView': 'scroll',
    'singleChildScrollView': 'scroll',
    'ListView': 'listView',
    'GridView': 'gridView',
    'Image': 'image',
    'networkImage': 'image',
    'NetworkImage': 'image',
    'img': 'image',
    'Svg': 'svg',
    'SVG': 'svg',
    'Card': 'card',
    'Row': 'row',
    'Column': 'column',
    'Stack': 'stack',
    'Center': 'center',
    'Padding': 'padding',
    'SizedBox': 'sizedBox',
    'Container': 'container',
    'ListTile': 'listTile',
    'listItem': 'listTile',
    'ListItem': 'listTile',
    'ProgressBar': 'linearProgressIndicator',
    'progress': 'linearProgressIndicator',
    'linearProgress': 'linearProgressIndicator',
    'ActivityIndicator': 'circularProgressIndicator',
    'spinner': 'circularProgressIndicator',
    'TextInput': 'textField',
    'textInput': 'textField',
    'input': 'textField',
    'Switch': 'switch',
    'Checkbox': 'checkbox',
    'Slider': 'slider',
    'Markdown': 'markdown',
    'md': 'markdown',
    'Avatar': 'circleAvatar',
    'CircleAvatar': 'circleAvatar',
    'avatar': 'circleAvatar',
    'Chip': 'chip',
    'Tag': 'chip',
    'tag': 'chip',
    'Badge': 'badge',
    'Dropdown': 'dropdown',
    'Select': 'dropdown',
    'select': 'dropdown',
    'InkWell': 'inkWell',
    'GestureDetector': 'gestureDetector',
    'SafeArea': 'safeArea',
    'Divider': 'divider',
    'Spacer': 'spacer',
    'Icon': 'icon',
  };
}
