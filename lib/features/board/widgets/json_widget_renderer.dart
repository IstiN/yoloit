import 'package:flutter/material.dart';

/// Converts a JSON widget tree (produced by JS widgets) into Flutter widgets.
///
/// Supported node types:
/// Layout:   column, row, stack, center, padding, sizedBox, expanded, flexible, wrap, align
/// Display:  text, icon, divider, spacer, image, circularProgressIndicator
/// Container: container, card, inkWell, safeArea
/// List:     listView, gridView
/// Input:    button (ElevatedButton), textButton, outlinedButton, iconButton
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
  const JsonWidgetRenderer({required this.onEvent});

  /// Called when a user-triggered event fires (e.g. button tap).
  final void Function(String actionId, Map<String, dynamic> payload) onEvent;

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
      'column'                    => _column(m),
      'row'                       => _row(m),
      'stack'                     => _stack(m),
      'center'                    => Center(child: _child(m)),
      'align'                     => _align(m),
      'expanded'                  => Expanded(flex: _int(m['flex'], 1), child: _child(m)!),
      'flexible'                  => Flexible(flex: _int(m['flex'], 1), child: _child(m)!),
      'wrap'                      => _wrap(m),
      'padding'                   => Padding(padding: _edgeInsets(m['padding']), child: _child(m)),
      'sizedBox'                  => _sizedBox(m),
      'spacer'                    => Spacer(flex: _int(m['flex'], 1)),
      'safeArea'                  => SafeArea(child: _child(m) ?? const SizedBox()),
      'text'                      => _text(m),
      'icon'                      => _icon(m),
      'divider'                   => _divider(m),
      'circularProgressIndicator' => _spinner(m),
      'container'                 => _container(m),
      'card'                      => _card(m),
      'inkWell'                   => _inkWell(m),
      'listView'                  => _listView(m),
      'gridView'                  => _gridView(m),
      'button'                    => _elevatedButton(m),
      'textButton'                => _textButton(m),
      'outlinedButton'            => _outlinedButton(m),
      'iconButton'                => _iconButton(m),
      'image'                     => _image(m),
      'aspectRatio'               => _aspectRatio(m),
      'opacity'                   => Opacity(opacity: _double(m['opacity'], 1.0), child: _child(m)),
      'clipRRect'                 => _clipRRect(m),
      'textField'                 => _textFieldNode(m),

      _                           => const SizedBox.shrink(),
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
    final children = (m['children'] as List? ?? [])
        .map((c) {
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
        })
        .toList();
    return Stack(
      alignment: _alignment(m['alignment']),
      children: children,
    );
  }

  Widget _wrap(Map<String, dynamic> m) => Wrap(
    spacing: _double(m['spacing'], 4),
    runSpacing: _double(m['runSpacing'], 4),
    alignment: _wrapAlignment(m['alignment']),
    children: _children(m),
  );

  Widget _align(Map<String, dynamic> m) => Align(
    alignment: _alignment(m['alignment']),
    child: _child(m),
  );

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
    final align = _textAlign(m['textAlign'] as String? ?? (m['style'] as Map?)?['textAlign'] as String?);
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
    color: _color(m['color'] as String?) ?? const Color(0x33FFFFFF),
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
      errorBuilder: (_, __, ___) => Icon(Icons.broken_image, size: w ?? 48),
    );
  }

  // ── Container & decoration ────────────────────────────────────────────────

  Widget _container(Map<String, dynamic> m) {
    final deco = m['decoration'] as Map?;
    return Container(
      width: _doubleOrNull(m['width']),
      height: _doubleOrNull(m['height']),
      padding: _edgeInsetsOrNull(m['padding']),
      margin: _edgeInsetsOrNull(m['margin']),
      alignment: m['alignment'] != null ? _alignment(m['alignment']) : null,
      decoration: deco != null ? _boxDecoration(deco.cast<String, dynamic>()) : (m['color'] != null ? BoxDecoration(color: _color(m['color'] as String?)) : null),
      child: _child(m),
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

  Widget _aspectRatio(Map<String, dynamic> m) => AspectRatio(
    aspectRatio: _double(m['aspectRatio'], 1),
    child: _child(m),
  );

  // ── Lists ─────────────────────────────────────────────────────────────────

  Widget _listView(Map<String, dynamic> m) {
    final items = m['children'] as List? ?? [];
    final shrink = m['shrinkWrap'] as bool? ?? true;
    final reverse = m['reverse'] as bool? ?? false;
    return ListView.builder(
      shrinkWrap: shrink,
      reverse: reverse,
      physics: shrink ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
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
    final onTap = _tapHandler(m['onTap'], m['payload']);
    final style = m['style'] as Map?;
    final bg = _color(style?['backgroundColor'] as String?);
    final fg = _color(style?['foregroundColor'] as String?);
    return ElevatedButton(
      onPressed: onTap,
      style: bg != null || fg != null ? ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: fg) : null,
      child: label,
    );
  }

  Widget _textButton(Map<String, dynamic> m) => TextButton(
    onPressed: _tapHandler(m['onTap'], m['payload']),
    child: _buttonLabel(m),
  );

  Widget _outlinedButton(Map<String, dynamic> m) => OutlinedButton(
    onPressed: _tapHandler(m['onTap'], m['payload']),
    child: _buttonLabel(m),
  );

  Widget _iconButton(Map<String, dynamic> m) => IconButton(
    icon: Icon(_iconData(m['icon'] as String? ?? 'info')),
    iconSize: _double(m['size'], 24),
    color: _color(m['color'] as String?),
    onPressed: _tapHandler(m['onTap'], m['payload']),
    tooltip: m['tooltip'] as String?,
  );

  Widget _buttonLabel(Map<String, dynamic> m) {
    final text = m['text'] as String? ?? m['label'] as String? ?? '';
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
    final p = payload is Map ? payload.cast<String, dynamic>() : <String, dynamic>{};
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
      border: borderColor != null ? Border.all(color: borderColor, width: borderWidth) : null,
      gradient: _gradient(d['gradient'] as Map?),
    );
  }

  Gradient? _gradient(Map? g) {
    if (g == null) return null;
    final colors = (g['colors'] as List? ?? [])
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

  Color? _namedColor(String name) => const {
    'transparent': Colors.transparent,
    'white': Colors.white,
    'black': Colors.black,
    'red': Colors.red,
    'green': Colors.green,
    'blue': Colors.blue,
    'yellow': Colors.yellow,
    'orange': Colors.orange,
    'purple': Colors.purple,
    'grey': Colors.grey,
    'gray': Colors.grey,
    'pink': Colors.pink,
    'teal': Colors.teal,
    'cyan': Colors.cyan,
    'amber': Colors.amber,
    'indigo': Colors.indigo,
    'lime': Colors.lime,
    'brown': Colors.brown,
  }[name.toLowerCase()];

  IconData _iconData(String name) => const {
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
  }[name.toLowerCase()] ?? Icons.widgets;

  MainAxisAlignment _mainAxis(dynamic v) => switch (v as String?) {
    'start'        => MainAxisAlignment.start,
    'end'          => MainAxisAlignment.end,
    'center'       => MainAxisAlignment.center,
    'spaceBetween' => MainAxisAlignment.spaceBetween,
    'spaceAround'  => MainAxisAlignment.spaceAround,
    'spaceEvenly'  => MainAxisAlignment.spaceEvenly,
    _              => MainAxisAlignment.start,
  };

  CrossAxisAlignment _crossAxis(dynamic v) => switch (v as String?) {
    'start'    => CrossAxisAlignment.start,
    'end'      => CrossAxisAlignment.end,
    'center'   => CrossAxisAlignment.center,
    'stretch'  => CrossAxisAlignment.stretch,
    'baseline' => CrossAxisAlignment.baseline,
    _          => CrossAxisAlignment.start,
  };

  MainAxisSize _mainSize(dynamic v) =>
      v == 'min' ? MainAxisSize.min : MainAxisSize.max;

  TextAlign? _textAlign(String? v) => switch (v) {
    'left'    => TextAlign.left,
    'right'   => TextAlign.right,
    'center'  => TextAlign.center,
    'justify' => TextAlign.justify,
    _         => null,
  };

  TextOverflow? _overflow(String? v) => switch (v) {
    'ellipsis' => TextOverflow.ellipsis,
    'clip'     => TextOverflow.clip,
    'fade'     => TextOverflow.fade,
    _          => null,
  };

  FontWeight? _fontWeight(dynamic v) {
    if (v == null) return null;
    if (v is num) return FontWeight.values.firstWhere(
      (w) => w.value == ((v / 100).round() * 100).clamp(100, 900),
      orElse: () => FontWeight.normal,
    );
    return switch (v.toString()) {
      'bold'   => FontWeight.bold,
      'w100'   => FontWeight.w100,
      'w200'   => FontWeight.w200,
      'w300'   => FontWeight.w300,
      'w400'   => FontWeight.w400,
      'w500'   => FontWeight.w500,
      'w600'   => FontWeight.w600,
      'w700'   => FontWeight.w700,
      'w800'   => FontWeight.w800,
      'w900'   => FontWeight.w900,
      _        => FontWeight.normal,
    };
  }

  Alignment _alignment(dynamic v) {
    if (v == null) return Alignment.center;
    if (v is String) {
      return switch (v) {
        'topLeft'      => Alignment.topLeft,
        'topCenter'    => Alignment.topCenter,
        'topRight'     => Alignment.topRight,
        'centerLeft'   => Alignment.centerLeft,
        'center'       => Alignment.center,
        'centerRight'  => Alignment.centerRight,
        'bottomLeft'   => Alignment.bottomLeft,
        'bottomCenter' => Alignment.bottomCenter,
        'bottomRight'  => Alignment.bottomRight,
        _              => Alignment.center,
      };
    }
    return Alignment.center;
  }

  AlignmentGeometry _alignmentGradient(String? v) => switch (v) {
    'topLeft'    => Alignment.topLeft,
    'topRight'   => Alignment.topRight,
    'bottomLeft' => Alignment.bottomLeft,
    'bottomRight'=> Alignment.bottomRight,
    'topCenter'  => Alignment.topCenter,
    'bottomCenter' => Alignment.bottomCenter,
    'centerLeft' => Alignment.centerLeft,
    'centerRight'=> Alignment.centerRight,
    _            => Alignment.centerLeft,
  };

  WrapAlignment _wrapAlignment(dynamic v) => switch (v as String?) {
    'center'       => WrapAlignment.center,
    'end'          => WrapAlignment.end,
    'spaceBetween' => WrapAlignment.spaceBetween,
    'spaceAround'  => WrapAlignment.spaceAround,
    'spaceEvenly'  => WrapAlignment.spaceEvenly,
    _              => WrapAlignment.start,
  };

  BoxFit _boxFit(String? v) => switch (v) {
    'fill'      => BoxFit.fill,
    'contain'   => BoxFit.contain,
    'cover'     => BoxFit.cover,
    'fitWidth'  => BoxFit.fitWidth,
    'fitHeight' => BoxFit.fitHeight,
    'none'      => BoxFit.none,
    _           => BoxFit.cover,
  };

  double _double(dynamic v, double def) =>
      v == null ? def : (v as num).toDouble();

  double? _doubleOrNull(dynamic v) =>
      v == null ? null : (v as num).toDouble();

  Widget _textFieldNode(Map<String, dynamic> m) => _TextFieldNode(
    initialValue: m['value'] as String? ?? '',
    hint: m['hint'] as String? ?? '',
    onSubmit: m['onSubmit'] as String?,
    onChange: m['onChange'] as String?,
    style: _textStyle(m['style'] as Map?),
    obscure: m['obscure'] == true,
    onEvent: onEvent,
  );

  int _int(dynamic v, int def) =>
      v == null ? def : (v as num).toInt();
}

// ── TextField node ────────────────────────────────────────────────────────────

class _TextFieldNode extends StatefulWidget {
  const _TextFieldNode({
    required this.initialValue,
    required this.hint,
    required this.onSubmit,
    required this.onChange,
    required this.style,
    required this.obscure,
    required this.onEvent,
  });

  final String initialValue;
  final String hint;
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

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(_TextFieldNode old) {
    super.didUpdateWidget(old);
    // Only update controller if value changes externally and field is not focused
    if (widget.initialValue != old.initialValue && !_ctrl.selection.isValid) {
      _ctrl.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      obscureText: widget.obscure,
      style: widget.style ?? const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFF1e293b),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3b82f6)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      onSubmitted: (val) {
        final action = widget.onSubmit;
        if (action != null) widget.onEvent(action, {'value': val});
      },
      onChanged: (val) {
        final action = widget.onChange;
        if (action != null) widget.onEvent(action, {'value': val});
      },
    );
  }
}
