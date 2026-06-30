import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/input_decoration_utils.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_field_registry.dart';

final _jsonWidgetDefaultColors = AppColorScheme.fromAccent(Colors.deepPurple);

/// Converts a JSON widget tree (produced by JS widgets) into Flutter widgets.
///
/// Supported node types:
/// Layout:   column, row, stack, center, padding, sizedBox, expanded, flexible, wrap, align
/// Display:  text, icon, markdown, divider, spacer, image, svg, avatar, chip, badge,
///           linearProgressIndicator, circularProgressIndicator
/// Container: container, card, inkWell, safeArea, scroll
/// List:     listView, gridView, listTile
/// Input:    button, textButton, outlinedButton, iconButton, textField,
///           switch, checkbox, slider, dropdown
///
/// Node shape:
/// ```json
/// {
///   "type": "column",
///   "children": [...],
///   "mainAxisAlignment": "center",
///   "crossAxisAlignment": "start"
/// }
/// ```
class JsonWidgetRenderer {
  const JsonWidgetRenderer({
    required this.onEvent,
    this.fieldRegistry,
  });

  /// Called when a user-triggered event fires (e.g. button tap).
  final void Function(String actionId, Map<String, dynamic> payload) onEvent;
  final UiViewFieldRegistry? fieldRegistry;

  Widget build(Map<String, dynamic>? tree, [BuildContext? ctx]) {
    if (tree == null) return const SizedBox.shrink();
    return _build(tree);
  }

  // ── Dispatcher ────────────────────────────────────────────────────────────

  Widget _build(dynamic node) {
    if (node == null) return const SizedBox.shrink();
    if (node is! Map) return const SizedBox.shrink();
    final m = node.cast<String, dynamic>();
    final type = m['type'] as String? ?? '';

    return switch (type) {
      'column' => _column(m),
      'row' => _row(m),
      'stack' => _stack(m),
      'center' => Center(child: _child(m)),
      'align' => _align(m),
      'expanded' => Expanded(flex: _int(m['flex'], 1), child: _child(m)!),
      'flexible' => Flexible(flex: _int(m['flex'], 1), child: _child(m)!),
      'wrap' => _wrap(m),
      'padding' => Padding(
        padding: _edgeInsets(m['padding']),
        child: _child(m),
      ),
      'sizedBox' => _sizedBox(m),
      'spacer' => Spacer(flex: _int(m['flex'], 1)),
      'safeArea' => SafeArea(child: _child(m) ?? const SizedBox()),
      'text' => _text(m),
      'icon' => _icon(m),
      'divider' => _divider(m),
      'circularProgressIndicator' => _spinner(m),
      'linearProgressIndicator' => _linearProgress(m),
      'container' => _container(m),
      'card' => _card(m),
      'inkWell' => _inkWell(m),
      'scroll' => _scroll(m),
      'listView' => _listView(m),
      'gridView' => _gridView(m),
      'listTile' => _listTile(m),
      'markdown' => _markdown(m),
      'circleAvatar' => _circleAvatar(m),
      'chip' => _chip(m),
      'badge' => _badge(m),
      'switch' => _switchNode(m),
      'checkbox' => _checkboxNode(m),
      'slider' => _sliderNode(m),
      'dropdown' => _dropdown(m),
      'button' => _elevatedButton(m),
      'textButton' => _textButton(m),
      'outlinedButton' => _outlinedButton(m),
      'iconButton' => _iconButton(m),
      'image' => _image(m),
      'svg' => _svg(m),
      'aspectRatio' => _aspectRatio(m),
      'opacity' => Opacity(
        opacity: _double(m['opacity'], 1.0),
        child: _child(m),
      ),
      'clipRRect' => _clipRRect(m),
      'textField' => _textFieldNode(m),
      'chart' => _chartNode(m),

      // Animated widgets (implicit animations)
      'animatedContainer' => _animatedContainer(m),
      'animatedOpacity' => _animatedOpacity(m),
      'animatedPositioned' => _animatedPositioned(m),

      // Gesture input
      'gestureDetector' => _gestureDetector(m),

      _ => _unknownType(m),
    };
  }

  // ── Layout ────────────────────────────────────────────────────────────────

  Widget _column(Map<String, dynamic> m) => Column(
    mainAxisAlignment: _mainAxis(m['mainAxisAlignment']),
    crossAxisAlignment: _crossAxis(m['crossAxisAlignment']),
    mainAxisSize: _mainSize(m['mainAxisSize']),
    children: _children(m),
  );

  Widget _row(Map<String, dynamic> m) => Row(
    mainAxisAlignment: _mainAxis(m['mainAxisAlignment']),
    crossAxisAlignment: _crossAxis(m['crossAxisAlignment']),
    mainAxisSize: _mainSize(m['mainAxisSize']),
    children: _children(m),
  );

  Widget _stack(Map<String, dynamic> m) {
    final children =
        (m['children'] as List? ?? []).map((c) {
          final cm = (c as Map?)?.cast<String, dynamic>() ?? {};
          if (cm['positioned'] != null) {
            final p = (cm['positioned'] as Map).cast<String, dynamic>();
            return Positioned(
              left: _doubleOrNull(p['left']),
              top: _doubleOrNull(p['top']),
              right: _doubleOrNull(p['right']),
              bottom: _doubleOrNull(p['bottom']),
              child: _build(cm['child'] ?? cm),
            );
          }
          return _build(c);
        }).toList();
    return Stack(alignment: _alignment(m['alignment']), children: children);
  }

  Widget _wrap(Map<String, dynamic> m) => Wrap(
    spacing: _double(m['spacing'], 4),
    runSpacing: _double(m['runSpacing'], 4),
    alignment: _wrapAlignment(m['alignment']),
    children: _children(m),
  );

  Widget _align(Map<String, dynamic> m) =>
      Align(alignment: _alignment(m['alignment']), child: _child(m));

  Widget _sizedBox(Map<String, dynamic> m) {
    final w = _doubleOrNull(m['width']);
    final h = _doubleOrNull(m['height']);
    final child = _child(m);
    if (child != null) return SizedBox(width: w, height: h, child: child);
    return SizedBox(width: w, height: h);
  }

  // ── Display ───────────────────────────────────────────────────────────────

  Widget _text(Map<String, dynamic> m) {
    final data = (m['data'] ?? m['text'] ?? '').toString();
    final style = _textStyle(m['style'] as Map?);
    final align = _textAlign(
      m['textAlign'] as String? ??
          (m['style'] as Map?)?['textAlign'] as String?,
    );
    final maxLines = m['maxLines'] as int?;
    final overflow = _overflow(m['overflow'] as String?);
    return Text(
      data,
      style: style,
      textAlign: align,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  Widget _icon(Map<String, dynamic> m) {
    final name = m['name'] as String? ?? m['icon'] as String? ?? '';
    final size = _double(m['size'], 24);
    final color = _color(m['color'] as String?);
    // Emoji / unicode strings pass through as Text
    if (name.runes.any((r) => r > 127)) {
      return Text(name, style: TextStyle(fontSize: size));
    }
    return Icon(_iconData(name), size: size, color: color);
  }

  Widget _divider(Map<String, dynamic> m) => Divider(
    color:
        _color(m['color'] as String?) ??
        _jsonWidgetDefaultColors.divider.withValues(alpha: 0.6),
    thickness: _double(m['thickness'], 1),
    height: _double(m['height'], 16),
    indent: _double(m['indent'], 0),
    endIndent: _double(m['endIndent'], 0),
  );

  Widget _spinner(Map<String, dynamic> m) => SizedBox(
    width: _double(m['size'], 24),
    height: _double(m['size'], 24),
    child: CircularProgressIndicator(
      strokeWidth: _double(m['strokeWidth'], 2),
      color: _color(m['color'] as String?),
    ),
  );

  Widget _linearProgress(Map<String, dynamic> m) => LinearProgressIndicator(
    value: _doubleOrNull(m['value']),
    minHeight: _double(m['height'], 4),
    color: _color(m['color'] as String?),
    backgroundColor: _color(m['backgroundColor'] as String?),
  );

  Widget _scroll(Map<String, dynamic> m) => SingleChildScrollView(
    padding: _edgeInsetsOrNull(m['padding']),
    reverse: m['reverse'] as bool? ?? false,
    child: _child(m) ?? Column(children: _children(m)),
  );

  Widget _listTile(Map<String, dynamic> m) {
    final title = (m['title'] ?? m['data'] ?? m['label'] ?? '').toString();
    final subtitle = m['subtitle'] as String?;
    final leading = _childFromKey(m, 'leading');
    final trailing = _childFromKey(m, 'trailing');
    return ListTile(
      dense: m['dense'] as bool? ?? false,
      enabled: m['enabled'] as bool? ?? true,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      leading: leading,
      trailing: trailing,
      onTap: _tapHandler(m['onTap'] ?? m['onPress'], m['payload']),
    );
  }

  Widget? _childFromKey(Map<String, dynamic> m, String key) {
    final raw = m[key];
    if (raw is Map) return _build(raw);
    if (raw is String && raw.isNotEmpty) {
      return Icon(_iconData(raw), size: 20);
    }
    return null;
  }

  Widget _markdown(Map<String, dynamic> m) {
    final data = (m['data'] ?? m['text'] ?? m['markdown'] ?? '').toString();
    if (data.trim().isEmpty) return const SizedBox.shrink();
    return MarkdownBody(
      data: data,
      selectable: m['selectable'] as bool? ?? false,
      shrinkWrap: true,
    );
  }

  Widget _circleAvatar(Map<String, dynamic> m) {
    final radius = _double(m['radius'], 20);
    final bg = _color(m['backgroundColor'] as String? ?? m['color'] as String?);
    final label = (m['data'] ?? m['label'] ?? m['text'] ?? '').toString();
    final url = m['url'] as String? ?? m['image'] as String?;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(url),
        backgroundColor: bg,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg ?? _jsonWidgetDefaultColors.primary,
      child: Text(
        label.isEmpty ? '?' : label.characters.first.toUpperCase(),
        style: TextStyle(
          color: _color(m['foregroundColor'] as String? ?? 'white'),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _chip(Map<String, dynamic> m) {
    final label = (m['label'] ?? m['data'] ?? m['text'] ?? '').toString();
    return ActionChip(
      label: Text(label),
      avatar:
          m['icon'] is String
              ? Icon(_iconData(m['icon'] as String), size: 16)
              : null,
      onPressed: _tapHandler(m['onTap'], m['payload']) ?? () {},
    );
  }

  Widget _badge(Map<String, dynamic> m) {
    final label = (m['label'] ?? m['data'] ?? m['text'] ?? '').toString();
    final child = _child(m);
    return Badge(
      label: Text(label),
      isLabelVisible: label.isNotEmpty,
      backgroundColor: _color(m['backgroundColor'] as String?),
      child: child ?? const Icon(Icons.notifications_none),
    );
  }

  Widget _switchNode(Map<String, dynamic> m) {
    final value = m['value'] as bool? ?? false;
    return Switch(
      value: value,
      activeThumbColor: _color(m['color'] as String?),
      onChanged: (next) {
        final action = m['onChange'] ?? m['onChanged'] ?? m['onTap'];
        if (action == null) return;
        onEvent('$action', <String, dynamic>{'value': next});
      },
    );
  }

  Widget _checkboxNode(Map<String, dynamic> m) {
    final value = m['value'] as bool? ?? false;
    final label = m['label'] as String?;
    final control = Checkbox(
      value: value,
      activeColor: _color(m['color'] as String?),
      onChanged: (next) {
        final action = m['onChange'] ?? m['onChanged'] ?? m['onTap'];
        if (action == null || next == null) return;
        onEvent('$action', <String, dynamic>{'value': next});
      },
    );
    if (label == null) return control;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        control,
        const SizedBox(width: 8),
        Flexible(child: Text(label)),
      ],
    );
  }

  Widget _sliderNode(Map<String, dynamic> m) {
    final value = _double(m['value'], 0);
    final min = _double(m['min'], 0);
    final max = _double(m['max'], 1);
    return Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      activeColor: _color(m['color'] as String?),
      onChanged: (next) {
        final action = m['onChange'] ?? m['onChanged'] ?? m['onTap'];
        if (action == null) return;
        onEvent('$action', <String, dynamic>{'value': next});
      },
    );
  }

  Widget _dropdown(Map<String, dynamic> m) {
    final items = _dropdownItems(m);
    if (items.isEmpty) return const SizedBox.shrink();
    final value = (m['value'] ?? items.first.value)?.toString();
    return DropdownButton<String>(
      isExpanded: m['expanded'] as bool? ?? true,
      value: items.any((item) => item.value == value) ? value : items.first.value,
      items: items,
      onChanged: (next) {
        final action = m['onChange'] ?? m['onChanged'] ?? m['onTap'];
        if (action == null || next == null) return;
        onEvent('$action', <String, dynamic>{'value': next});
      },
    );
  }

  List<DropdownMenuItem<String>> _dropdownItems(Map<String, dynamic> m) {
    final raw = m['items'] as List? ?? m['options'] as List? ?? const <dynamic>[];
    return raw.map((item) {
      if (item is String) {
        return DropdownMenuItem<String>(value: item, child: Text(item));
      }
      if (item is Map) {
        final map = item.cast<String, dynamic>();
        final value = (map['value'] ?? map['id'] ?? map['label'] ?? '').toString();
        final label = (map['label'] ?? map['text'] ?? value).toString();
        return DropdownMenuItem<String>(value: value, child: Text(label));
      }
      return DropdownMenuItem<String>(value: '$item', child: Text('$item'));
    }).toList();
  }

  Widget _unknownType(Map<String, dynamic> m) {
    final type = m['type'] as String? ?? '?';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.orange.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
        color: Colors.orange.withValues(alpha: 0.08),
      ),
      child: Text(
        'Unknown type: $type',
        style: const TextStyle(fontSize: 11, color: Colors.orange),
      ),
    );
  }

  Widget _image(Map<String, dynamic> m) {
    final url = m['url'] as String? ?? m['src'] as String? ?? '';
    final w = _doubleOrNull(m['width']);
    final h = _doubleOrNull(m['height']);
    final fit = _boxFit(m['fit'] as String?);
    if (url.isEmpty) return const SizedBox.shrink();
    return Image.network(
      url,
      width: w,
      height: h,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Icon(Icons.broken_image, size: w ?? 48),
    );
  }

  Widget _svg(Map<String, dynamic> m) {
    final raw =
        m['data'] as String? ??
        m['svg'] as String? ??
        m['path'] as String? ??
        '';
    final w = _doubleOrNull(m['width']) ?? _doubleOrNull(m['size']);
    final h = _doubleOrNull(m['height']) ?? _doubleOrNull(m['size']);
    final fit = _boxFit(m['fit'] as String?);
    final tint = _color(m['color'] as String? ?? m['fill'] as String?);
    if (raw.trim().isEmpty) {
      return Icon(Icons.image_not_supported_outlined, size: w ?? 48);
    }

    final markup = _normalizeSvgMarkup(raw, m);
    Widget picture = SvgPicture.string(
      markup,
      fit: fit,
      width: w,
      height: h,
      colorFilter:
          tint == null
              ? null
              : ColorFilter.mode(tint, BlendMode.srcIn),
    );
    if (w != null || h != null) {
      picture = SizedBox(width: w, height: h, child: picture);
    }
    return picture;
  }

  String _normalizeSvgMarkup(String raw, Map<String, dynamic> m) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('<')) return trimmed;

    final fill =
        m['fill'] as String? ??
        m['color'] as String? ??
        '#FF5733';
    final viewBox = m['viewBox'] as String? ?? '0 0 100 100';
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="$viewBox">'
        '<path d="$trimmed" fill="$fill"/></svg>';
  }

  // ── Container & decoration ────────────────────────────────────────────────

  Decoration? _containerDecoration(Map<String, dynamic> m) {
    final deco = m['decoration'] as Map?;
    if (deco != null) {
      return _boxDecoration(deco.cast<String, dynamic>());
    }
    final bg =
        m['backgroundColor'] as String? ??
        m['color'] as String?;
    if (bg != null) {
      return BoxDecoration(color: _color(bg));
    }
    return null;
  }

  ({double? width, double? height, EdgeInsetsGeometry? padding, EdgeInsetsGeometry? margin, Alignment? alignment, Decoration? decoration, Widget? child}) _containerProps(Map<String, dynamic> m) => (
    width: _doubleOrNull(m['width']),
    height: _doubleOrNull(m['height']),
    padding: _edgeInsetsOrNull(m['padding']),
    margin: _edgeInsetsOrNull(m['margin']),
    alignment: m['alignment'] != null ? _alignment(m['alignment']) : null,
    decoration: _containerDecoration(m),
    child: _child(m),
  );

  Widget _container(Map<String, dynamic> m) {
    final p = _containerProps(m);
    return Container(
      width: p.width,
      height: p.height,
      padding: p.padding,
      margin: p.margin,
      alignment: p.alignment,
      decoration: p.decoration,
      child: p.child,
    );
  }

  Widget _card(Map<String, dynamic> m) => Card(
    elevation: _double(m['elevation'], 2),
    margin: _edgeInsetsOrNull(m['margin']) ?? EdgeInsets.zero,
    color: _color(m['color'] as String?),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_double(m['borderRadius'], 8)),
    ),
    child: _child(m),
  );

  Widget _inkWell(Map<String, dynamic> m) => InkWell(
    onTap: _tapHandler(m['onTap'], m['payload']),
    borderRadius: BorderRadius.circular(_double(m['borderRadius'], 8)),
    child: _child(m),
  );

  Widget _clipRRect(Map<String, dynamic> m) => ClipRRect(
    borderRadius: BorderRadius.circular(_double(m['borderRadius'], 8)),
    child: _child(m),
  );

  Widget _aspectRatio(Map<String, dynamic> m) =>
      AspectRatio(aspectRatio: _double(m['aspectRatio'], 1), child: _child(m));

  // ── Lists ─────────────────────────────────────────────────────────────────

  Widget _listView(Map<String, dynamic> m) {
    final items = m['children'] as List? ?? [];
    final shrink = m['shrinkWrap'] as bool? ?? true;
    final reverse = m['reverse'] as bool? ?? false;
    return ListView.builder(
      shrinkWrap: shrink,
      reverse: reverse,
      physics:
          shrink
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
      padding: _edgeInsetsOrNull(m['padding']),
      itemCount: items.length,
      itemBuilder: (_, i) => _build(items[i]),
    );
  }

  Widget _gridView(Map<String, dynamic> m) {
    final items = m['children'] as List? ?? [];
    final cols = _int(m['crossAxisCount'], 2);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: _edgeInsetsOrNull(m['padding']),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: _double(m['crossAxisSpacing'], 4),
        mainAxisSpacing: _double(m['mainAxisSpacing'], 4),
        childAspectRatio: _double(m['childAspectRatio'], 1),
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _build(items[i]),
    );
  }

  // ── Buttons ───────────────────────────────────────────────────────────────

  Widget _elevatedButton(Map<String, dynamic> m) {
    final label = _buttonLabel(m);
    final onTap = _tapHandler(_buttonActionId(m), m['payload']);
    return ElevatedButton(
      onPressed: onTap,
      style: _materialButtonStyle(
        m['style'] is Map
            ? Map<String, dynamic>.from(
              (m['style'] as Map).cast<String, dynamic>(),
            )
            : null,
      ),
      child: label,
    );
  }

  Widget _textButton(Map<String, dynamic> m) {
    return TextButton(
      onPressed: _tapHandler(_buttonActionId(m), m['payload']),
      style: _materialButtonStyle(
        m['style'] is Map
            ? Map<String, dynamic>.from(
              (m['style'] as Map).cast<String, dynamic>(),
            )
            : null,
        textButton: true,
      ),
      child: _buttonLabel(m),
    );
  }

  Widget _outlinedButton(Map<String, dynamic> m) {
    final style =
        m['style'] is Map
            ? Map<String, dynamic>.from(
              (m['style'] as Map).cast<String, dynamic>(),
            )
            : null;
    final border = _color(style?['borderColor'] as String?);
    final base = _materialButtonStyle(style, outlined: true);
    return OutlinedButton(
      onPressed: _tapHandler(_buttonActionId(m), m['payload']),
      style:
          border != null
              ? (base ?? const ButtonStyle()).merge(
                ButtonStyle(side: WidgetStatePropertyAll(BorderSide(color: border))),
              )
              : base,
      child: _buttonLabel(m),
    );
  }

  String _buttonActionId(Map<String, dynamic> m) {
    final raw = m['onTap'] ?? m['action'] ?? m['actionId'];
    if (raw == null) return '_tap';
    final text = '$raw'.trim();
    return text.isEmpty ? '_tap' : text;
  }

  ButtonStyle? _materialButtonStyle(
    Map<String, dynamic>? style, {
    bool textButton = false,
    bool outlined = false,
  }) {
    if (style == null) return null;
    final bg = _color(style['backgroundColor'] as String?);
    final fg = _color(
      style['foregroundColor'] as String? ?? style['color'] as String?,
    );
    if (bg == null && fg == null) return null;
    if (textButton) {
      return TextButton.styleFrom(foregroundColor: fg).merge(
        ButtonStyle(
          foregroundColor: fg != null ? WidgetStatePropertyAll(fg) : null,
        ),
      );
    }
    if (outlined) {
      return OutlinedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
      ).merge(
        ButtonStyle(
          backgroundColor: bg != null ? WidgetStatePropertyAll(bg) : null,
          foregroundColor: fg != null ? WidgetStatePropertyAll(fg) : null,
        ),
      );
    }
    return ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
    ).merge(
      ButtonStyle(
        backgroundColor: bg != null ? WidgetStatePropertyAll(bg) : null,
        foregroundColor: fg != null ? WidgetStatePropertyAll(fg) : null,
      ),
    );
  }

  Widget _iconButton(Map<String, dynamic> m) => IconButton(
    icon: Icon(_iconData(m['icon'] as String? ?? 'info')),
    iconSize: _double(m['size'], 24),
    color: _color(m['color'] as String?),
    onPressed: _tapHandler(m['onTap'], m['payload']),
    tooltip: m['tooltip'] as String?,
  );

  Widget _buttonLabel(Map<String, dynamic> m) {
    final text =
        m['text'] as String? ??
        m['label'] as String? ??
        m['data'] as String? ??
        '';
    final icon = m['icon'] as String?;
    if (icon != null && text.isNotEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconData(icon), size: 16),
          const SizedBox(width: 6),
          Text(text),
        ],
      );
    }
    if (icon != null) return Icon(_iconData(icon));
    return Text(text);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget? _child(Map<String, dynamic> m) {
    final c = m['child'];
    if (c == null) return null;
    return _build(c);
  }

  List<Widget> _children(Map<String, dynamic> m) =>
      (m['children'] as List? ?? []).map<Widget>(_build).toList();

  VoidCallback? _tapHandler(dynamic actionId, dynamic payload) {
    if (actionId == null) return null;
    final id = actionId.toString();
    final p =
        payload is Map ? payload.cast<String, dynamic>() : <String, dynamic>{};
    return () => onEvent(id, p);
  }

  // ── Style helpers ─────────────────────────────────────────────────────────

  TextStyle? _textStyle(Map? style) {
    if (style == null) return null;
    return TextStyle(
      color: _color(style['color'] as String?),
      fontSize: _doubleOrNull(style['fontSize']),
      fontWeight: _fontWeight(style['fontWeight']),
      fontStyle: style['italic'] == true ? FontStyle.italic : null,
      letterSpacing: _doubleOrNull(style['letterSpacing']),
      height: _doubleOrNull(style['height']),
    );
  }

  BoxDecoration _boxDecoration(Map<String, dynamic> d) {
    final br = _doubleOrNull(d['borderRadius']);
    final borderColor = _color(d['borderColor'] as String?);
    final borderWidth = _double(d['borderWidth'], 1);
    return BoxDecoration(
      color: _color(d['color'] as String?),
      borderRadius: br != null ? BorderRadius.circular(br) : null,
      border:
          borderColor != null
              ? Border.all(color: borderColor, width: borderWidth)
              : null,
      gradient: _gradient(d['gradient'] as Map?),
    );
  }

  Gradient? _gradient(Map? g) {
    if (g == null) return null;
    final colors =
        (g['colors'] as List? ?? [])
            .map((c) => _color(c as String?) ?? Colors.transparent)
            .toList();
    if (colors.isEmpty) return null;
    return LinearGradient(
      begin: _alignmentGradient(g['begin'] as String?),
      end: _alignmentGradient(g['end'] as String?),
      colors: colors,
    );
  }

  EdgeInsets _edgeInsets(dynamic v) {
    if (v == null) return EdgeInsets.zero;
    if (v is num) return EdgeInsets.all(v.toDouble());
    if (v is List && v.length == 4) {
      return EdgeInsets.fromLTRB(
        (v[0] as num).toDouble(),
        (v[1] as num).toDouble(),
        (v[2] as num).toDouble(),
        (v[3] as num).toDouble(),
      );
    }
    if (v is Map) {
      return EdgeInsets.only(
        left: _double(v['left'], 0),
        top: _double(v['top'], 0),
        right: _double(v['right'], 0),
        bottom: _double(v['bottom'], 0),
      );
    }
    return EdgeInsets.zero;
  }

  EdgeInsetsGeometry? _edgeInsetsOrNull(dynamic v) =>
      v == null ? null : _edgeInsets(v);

  Color? _color(String? s) {
    if (s == null || s.isEmpty) return null;
    if (s.startsWith('#')) {
      var hex = s.substring(1);
      if (hex.length == 3) {
        hex = hex.split('').map((c) => c + c).join();
      }
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    }
    return _namedColor(s);
  }

  Color? _namedColor(String name) {
    return switch (name.toLowerCase()) {
      'transparent' => Colors.transparent,
      'white' => Colors.white,
      'black' => Colors.black,
      'red' => Colors.red,
      'green' => Colors.green,
      'blue' => Colors.blue,
      'yellow' => Colors.yellow,
      'orange' => Colors.orange,
      'purple' => Colors.purple,
      'grey' => Colors.grey,
      'gray' => Colors.grey,
      'pink' => Colors.pink,
      'teal' => Colors.teal,
      'cyan' => Colors.cyan,
      'amber' => Colors.amber,
      'indigo' => Colors.indigo,
      'lime' => Colors.lime,
      'brown' => Colors.brown,
      _ => null,
    };
  }

  IconData _iconData(String name) =>
      const {
        'star': Icons.star,
        'favorite': Icons.favorite,
        'home': Icons.home,
        'settings': Icons.settings,
        'search': Icons.search,
        'add': Icons.add,
        'remove': Icons.remove,
        'delete': Icons.delete,
        'edit': Icons.edit,
        'info': Icons.info,
        'check': Icons.check,
        'close': Icons.close,
        'arrow_forward': Icons.arrow_forward,
        'arrow_back': Icons.arrow_back,
        'refresh': Icons.refresh,
        'share': Icons.share,
        'download': Icons.download,
        'upload': Icons.upload,
        'cloud': Icons.cloud,
        'person': Icons.person,
        'menu': Icons.menu,
        'more_vert': Icons.more_vert,
        'trending_up': Icons.trending_up,
        'trending_down': Icons.trending_down,
        'attach_money': Icons.attach_money,
        'show_chart': Icons.show_chart,
        'bar_chart': Icons.bar_chart,
        'notifications': Icons.notifications,
        'lock': Icons.lock,
        'key': Icons.key,
        'language': Icons.language,
        'thermostat': Icons.thermostat,
        'water_drop': Icons.water_drop,
        'air': Icons.air,
        'wb_sunny': Icons.wb_sunny,
        'nights_stay': Icons.nights_stay,
        'umbrella': Icons.umbrella,
        'calculate': Icons.calculate,
        'timer': Icons.timer,
        'calendar_today': Icons.calendar_today,
        'warning': Icons.warning,
        'error': Icons.error,
        'done': Icons.done,
        'play_arrow': Icons.play_arrow,
        'pause': Icons.pause,
        'stop': Icons.stop,
        'skip_next': Icons.skip_next,
        'skip_previous': Icons.skip_previous,
      }[name.toLowerCase()] ??
      Icons.widgets;

  MainAxisAlignment _mainAxis(dynamic v) => switch (v as String?) {
    'start' => MainAxisAlignment.start,
    'end' => MainAxisAlignment.end,
    'center' => MainAxisAlignment.center,
    'spaceBetween' => MainAxisAlignment.spaceBetween,
    'spaceAround' => MainAxisAlignment.spaceAround,
    'spaceEvenly' => MainAxisAlignment.spaceEvenly,
    _ => MainAxisAlignment.start,
  };

  CrossAxisAlignment _crossAxis(dynamic v) => switch (v as String?) {
    'start' => CrossAxisAlignment.start,
    'end' => CrossAxisAlignment.end,
    'center' => CrossAxisAlignment.center,
    'stretch' => CrossAxisAlignment.stretch,
    'baseline' => CrossAxisAlignment.baseline,
    _ => CrossAxisAlignment.start,
  };

  MainAxisSize _mainSize(dynamic v) =>
      v == 'min' ? MainAxisSize.min : MainAxisSize.max;

  TextAlign? _textAlign(String? v) => switch (v) {
    'left' => TextAlign.left,
    'right' => TextAlign.right,
    'center' => TextAlign.center,
    'justify' => TextAlign.justify,
    _ => null,
  };

  TextOverflow? _overflow(String? v) => switch (v) {
    'ellipsis' => TextOverflow.ellipsis,
    'clip' => TextOverflow.clip,
    'fade' => TextOverflow.fade,
    _ => null,
  };

  FontWeight? _fontWeight(dynamic v) {
    if (v == null) return null;
    if (v is num) {
      return FontWeight.values.firstWhere(
        (w) => w.value == ((v / 100).round() * 100).clamp(100, 900),
        orElse: () => FontWeight.normal,
      );
    }
    return switch (v.toString()) {
      'bold' => FontWeight.bold,
      'w100' => FontWeight.w100,
      'w200' => FontWeight.w200,
      'w300' => FontWeight.w300,
      'w400' => FontWeight.w400,
      'w500' => FontWeight.w500,
      'w600' => FontWeight.w600,
      'w700' => FontWeight.w700,
      'w800' => FontWeight.w800,
      'w900' => FontWeight.w900,
      _ => FontWeight.normal,
    };
  }

  Alignment _alignment(dynamic v) {
    if (v == null) return Alignment.center;
    if (v is String) {
      return switch (v) {
        'topLeft' => Alignment.topLeft,
        'topCenter' => Alignment.topCenter,
        'topRight' => Alignment.topRight,
        'centerLeft' => Alignment.centerLeft,
        'center' => Alignment.center,
        'centerRight' => Alignment.centerRight,
        'bottomLeft' => Alignment.bottomLeft,
        'bottomCenter' => Alignment.bottomCenter,
        'bottomRight' => Alignment.bottomRight,
        _ => Alignment.center,
      };
    }
    return Alignment.center;
  }

  AlignmentGeometry _alignmentGradient(String? v) => switch (v) {
    'topLeft' => Alignment.topLeft,
    'topRight' => Alignment.topRight,
    'bottomLeft' => Alignment.bottomLeft,
    'bottomRight' => Alignment.bottomRight,
    'topCenter' => Alignment.topCenter,
    'bottomCenter' => Alignment.bottomCenter,
    'centerLeft' => Alignment.centerLeft,
    'centerRight' => Alignment.centerRight,
    _ => Alignment.centerLeft,
  };

  WrapAlignment _wrapAlignment(dynamic v) => switch (v as String?) {
    'center' => WrapAlignment.center,
    'end' => WrapAlignment.end,
    'spaceBetween' => WrapAlignment.spaceBetween,
    'spaceAround' => WrapAlignment.spaceAround,
    'spaceEvenly' => WrapAlignment.spaceEvenly,
    _ => WrapAlignment.start,
  };

  BoxFit _boxFit(String? v) => switch (v) {
    'fill' => BoxFit.fill,
    'contain' => BoxFit.contain,
    'cover' => BoxFit.cover,
    'fitWidth' => BoxFit.fitWidth,
    'fitHeight' => BoxFit.fitHeight,
    'none' => BoxFit.none,
    _ => BoxFit.cover,
  };

  double _double(dynamic v, double def) =>
      v == null ? def : (v as num).toDouble();

  double? _doubleOrNull(dynamic v) => v == null ? null : (v as num).toDouble();

  Widget _textFieldNode(Map<String, dynamic> m) => _TextFieldNode(
    initialValue:
        m['initialValue'] as String? ?? m['value'] as String? ?? '',
    hint: m['hint'] as String? ?? '',
    storageKey:
        m['storageKey'] as String? ??
        m['id'] as String? ??
        m['name'] as String?,
    fieldRegistry: fieldRegistry,
    onSubmit: m['onSubmit'] as String?,
    onChange: m['onChange'] as String? ?? m['onChanged'] as String?,
    style: _textStyle(m['style'] as Map?),
    obscure: m['obscure'] == true,
    onEvent: onEvent,
  );

  Widget _chartNode(Map<String, dynamic> m) {
    final rawPoints = m['points'] as List?;
    if (rawPoints == null || rawPoints.isEmpty) return const SizedBox.shrink();
    final points = rawPoints.map((v) => (v as num).toDouble()).toList();
    final color =
        _color(m['color'] as String? ?? '#4ade80') ?? Colors.greenAccent;
    final height = _double(m['height'], 60.0);
    final fill = m['fill'] == true;
    final onTap = m['onTap'] as String?;
    Widget chart = SizedBox(
      height: height,
      child: CustomPaint(
        isComplex: true,
        painter: _SparklinePainter(points: points, color: color, fill: fill),
        size: Size.infinite,
      ),
    );
    if (onTap != null) {
      chart = GestureDetector(onTap: () => onEvent(onTap, {}), child: chart);
    }
    return chart;
  }

  int _int(dynamic v, int def) => v == null ? def : (v as num).toInt();

  // ── Animated widgets ──────────────────────────────────────────────────────

  Widget _animatedContainer(Map<String, dynamic> m) {
    final p = _containerProps(m);
    return AnimatedContainer(
      duration: Duration(milliseconds: _int(m['duration'], 300)),
      curve: _curve(m['curve'] as String?),
      width: p.width,
      height: p.height,
      padding: p.padding,
      margin: p.margin,
      alignment: p.alignment,
      decoration: p.decoration,
      transform: _matrix4(m['transform']),
      child: p.child,
    );
  }

  Widget _animatedOpacity(Map<String, dynamic> m) => AnimatedOpacity(
    duration: Duration(milliseconds: _int(m['duration'], 300)),
    curve: _curve(m['curve'] as String?),
    opacity: _double(m['opacity'], 1.0),
    child: _child(m) ?? const SizedBox.shrink(),
  );

  Widget _animatedPositioned(Map<String, dynamic> m) => AnimatedPositioned(
    duration: Duration(milliseconds: _int(m['duration'], 300)),
    curve: _curve(m['curve'] as String?),
    left: _doubleOrNull(m['left']),
    top: _doubleOrNull(m['top']),
    right: _doubleOrNull(m['right']),
    bottom: _doubleOrNull(m['bottom']),
    width: _doubleOrNull(m['width']),
    height: _doubleOrNull(m['height']),
    child: _child(m) ?? const SizedBox.shrink(),
  );

  Curve _curve(String? v) => switch (v) {
    'linear' => Curves.linear,
    'easeIn' => Curves.easeIn,
    'easeOut' => Curves.easeOut,
    'easeInOut' => Curves.easeInOut,
    'bounce' => Curves.bounceOut,
    'bounceIn' => Curves.bounceIn,
    'elastic' => Curves.elasticOut,
    'elasticIn' => Curves.elasticIn,
    'decelerate' => Curves.decelerate,
    'fastOutSlowIn' => Curves.fastOutSlowIn,
    _ => Curves.easeInOut,
  };

  Matrix4? _matrix4(dynamic v) {
    if (v == null) return null;
    if (v is Map) {
      final m = v.cast<String, dynamic>();
      final tx = _double(m['translateX'], 0);
      final ty = _double(m['translateY'], 0);
      final scale = _double(m['scale'], 1);
      final rotate = _double(m['rotate'], 0); // radians
      return Matrix4.identity()
        ..translateByDouble(tx, ty, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..rotateZ(rotate);
    }
    return null;
  }

  // ── Gesture Detector ──────────────────────────────────────────────────────

  Widget _gestureDetector(Map<String, dynamic> m) {
    final child = _child(m) ?? const SizedBox.shrink();
    // Use scheduleMicrotask to defer onEvent calls outside Flutter's gesture/mouse
    // tracking pipeline — prevents !_debugDuringDeviceUpdate assertion.
    void fire(String event, Map<String, dynamic> payload) =>
        scheduleMicrotask(() => onEvent(event, payload));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: m['onTap'] != null ? () => fire(m['onTap'] as String, {}) : null,
      onTapDown:
          m['onTapDown'] != null
              ? (d) => fire(m['onTapDown'] as String, {
                'x': d.localPosition.dx,
                'y': d.localPosition.dy,
              })
              : null,
      onTapUp:
          m['onTapUp'] != null
              ? (d) => fire(m['onTapUp'] as String, {
                'x': d.localPosition.dx,
                'y': d.localPosition.dy,
              })
              : null,
      onPanStart:
          m['onPanStart'] != null
              ? (d) => fire(m['onPanStart'] as String, {
                'x': d.localPosition.dx,
                'y': d.localPosition.dy,
              })
              : null,
      onPanUpdate:
          m['onPanUpdate'] != null
              ? (d) => fire(m['onPanUpdate'] as String, {
                'x': d.localPosition.dx,
                'y': d.localPosition.dy,
                'dx': d.delta.dx,
                'dy': d.delta.dy,
              })
              : null,
      onPanEnd:
          m['onPanEnd'] != null
              ? (d) => fire(m['onPanEnd'] as String, {
                'velocityX': d.velocity.pixelsPerSecond.dx,
                'velocityY': d.velocity.pixelsPerSecond.dy,
              })
              : null,
      child: child,
    );
  }
}

// ── TextField node ────────────────────────────────────────────────────────────

class _TextFieldNode extends StatefulWidget {
  const _TextFieldNode({
    required this.initialValue,
    required this.hint,
    required this.storageKey,
    required this.fieldRegistry,
    required this.onSubmit,
    required this.onChange,
    required this.style,
    required this.obscure,
    required this.onEvent,
  });

  final String initialValue;
  final String hint;
  final String? storageKey;
  final UiViewFieldRegistry? fieldRegistry;
  final String? onSubmit;
  final String? onChange;
  final TextStyle? style;
  final bool obscure;
  final void Function(String actionId, Map<String, dynamic> payload) onEvent;

  @override
  State<_TextFieldNode> createState() => _TextFieldNodeState();
}

class _TextFieldNodeState extends State<_TextFieldNode> {
  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _registerField();
  }

  @override
  void didUpdateWidget(_TextFieldNode old) {
    super.didUpdateWidget(old);
    if (widget.storageKey != old.storageKey) {
      _unregisterField(old.storageKey);
      _registerField();
    }
    if (widget.initialValue != old.initialValue &&
        widget.initialValue != _ctrl.text &&
        !_focusNode.hasFocus) {
      _ctrl.text = widget.initialValue;
    }
  }

  void _registerField() {
    final key = widget.storageKey;
    final registry = widget.fieldRegistry;
    if (key == null || key.isEmpty || registry == null) return;
    registry.register(key, () => _ctrl.text);
  }

  void _unregisterField(String? key) {
    final registry = widget.fieldRegistry;
    if (key == null || key.isEmpty || registry == null) return;
    registry.unregister(key);
  }

  @override
  void dispose() {
    _unregisterField(widget.storageKey);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _emitChange(String value) {
    final key = widget.storageKey;
    if (key != null && key.isNotEmpty) {
      widget.onEvent('_field', <String, dynamic>{'key': key, 'value': value});
    }
    final action = widget.onChange;
    if (action != null) {
      widget.onEvent(action, <String, dynamic>{'value': value});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TextField(
      controller: _ctrl,
      focusNode: _focusNode,
      obscureText: widget.obscure,
      style: widget.style ?? TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: appInputDecoration(
        colors: colors,
        hintText: widget.hint,
        hintFontSize: 14,
        borderRadius: 8,
        fillColor: colors.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.accentBlue),
        ),
      ),
      onSubmitted: (val) {
        _emitChange(val);
        final action = widget.onSubmit;
        if (action != null) {
          widget.onEvent(action, <String, dynamic>{'value': val});
        }
      },
      onChanged: _emitChange,
    );
  }
}

// ── Sparkline chart painter ───────────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.points,
    required this.color,
    required this.fill,
  });
  final List<double> points;
  final Color color;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final min = points.reduce((a, b) => a < b ? a : b);
    final max = points.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs();
    final effectiveRange = range < 0.0001 ? 1.0 : range;

    final xStep = size.width / (points.length - 1);

    double toY(double v) =>
        size.height -
        ((v - min) / effectiveRange) * size.height * 0.85 -
        size.height * 0.05;

    final path = Path();
    path.moveTo(0, toY(points[0]));
    for (int i = 1; i < points.length; i++) {
      final x = i * xStep;
      final prev = points[i - 1];
      final curr = points[i];
      final cpx = (i - 0.5) * xStep;
      path.cubicTo(cpx, toY(prev), cpx, toY(curr), x, toY(curr));
    }

    final linePaint =
        Paint()
          ..color = color
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    if (fill) {
      final fillPath = Path()..addPath(path, Offset.zero);
      fillPath.lineTo(size.width, size.height);
      fillPath.lineTo(0, size.height);
      fillPath.close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..color = color.withAlpha(40)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.points != points || old.color != color || old.fill != fill;
}
