import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

class MiroToolbarValueMenu<T> extends StatelessWidget {
  const MiroToolbarValueMenu({
    super.key,
    required this.tooltip,
    required this.valueLabel,
    required this.values,
    required this.itemLabel,
    required this.onSelected,
  });

  final String tooltip;
  final String valueLabel;
  final List<T> values;
  final String Function(T value) itemLabel;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: PopupMenuButton<T>(
        tooltip: tooltip,
        onSelected: onSelected,
        itemBuilder:
            (context) => values
                .map(
                  (value) => PopupMenuItem<T>(
                    value: value,
                    child: Text(itemLabel(value)),
                  ),
                )
                .toList(growable: false),
        child: SizedBox(
          height: 36,
          width: 46,
          child: Center(
            child: Text(
              valueLabel,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MiroToolbarColorMenu extends StatelessWidget {
  const MiroToolbarColorMenu({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.colors,
    required this.onSelected,
    required this.onCustomSelected,
  });

  static const _customColorValue = '__custom_color__';

  final String tooltip;
  final IconData icon;
  final Color selected;
  final List<Color> colors;
  final ValueChanged<Color> onSelected;
  final Future<Color?> Function(Color initialColor) onCustomSelected;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: PopupMenuButton<Object>(
        tooltip: tooltip,
        onSelected: (value) async {
          if (value is Color) {
            onSelected(value);
            return;
          }
          if (value == _customColorValue) {
            final color = await onCustomSelected(selected);
            if (color != null) {
              onSelected(color);
            }
          }
        },
        itemBuilder:
            (context) => [
              ...colors.map(
                (color) => PopupMenuItem<Object>(
                  value: color,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MiroToolbarColorDot(
                        color: color,
                        selected: color.toARGB32() == selected.toARGB32(),
                      ),
                      const SizedBox(width: 10),
                      Text(miroToolbarColorLabel(color)),
                    ],
                  ),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<Object>(
                value: _customColorValue,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.palette_outlined, size: 19, color: textColor),
                    const SizedBox(width: 10),
                    const Text('Custom...'),
                  ],
                ),
              ),
            ],
        child: SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 20, color: textColor),
              Positioned(
                right: 7,
                bottom: 6,
                child: MiroToolbarColorDot(color: selected, size: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MiroToolbarIconValueMenu<T> extends StatelessWidget {
  const MiroToolbarIconValueMenu({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.values,
    required this.itemLabel,
    required this.itemIcon,
    required this.onSelected,
  });

  final String tooltip;
  final IconData icon;
  final List<T> values;
  final String Function(T value) itemLabel;
  final IconData Function(T value) itemIcon;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: PopupMenuButton<T>(
        tooltip: tooltip,
        onSelected: onSelected,
        itemBuilder:
            (context) => values
                .map(
                  (value) => PopupMenuItem<T>(
                    value: value,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(itemIcon(value), size: 19, color: textColor),
                        const SizedBox(width: 10),
                        Text(itemLabel(value)),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: textColor),
        ),
      ),
    );
  }
}

class MiroToolbarColorDot extends StatelessWidget {
  const MiroToolbarColorDot({
    super.key,
    required this.color,
    this.selected = false,
    this.size = 18,
  });

  final Color color;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isTransparent = color.a == 0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isTransparent ? Colors.white : color,
        shape: BoxShape.circle,
        border: Border.all(
          color:
              selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
          width: selected ? 2 : 1,
        ),
      ),
      child:
          isTransparent
              ? Icon(Icons.block_rounded, size: size * 0.72, color: Colors.grey)
              : null,
    );
  }
}

class MiroToolbarShapeMenu extends StatelessWidget {
  const MiroToolbarShapeMenu({
    super.key,
    required this.selectedShape,
    required this.onSelected,
  });

  final String selectedShape;
  final ValueChanged<String> onSelected;

  static const _shapes = <String>[
    'rectangle',
    'circle',
    'diamond',
    'triangle',
    'hexagon',
    'frame',
  ];

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: 'Shape',
      child: PopupMenuButton<String>(
        tooltip: 'Shape',
        onSelected: onSelected,
        itemBuilder:
            (context) => _shapes
                .map(
                  (shape) => PopupMenuItem<String>(
                    value: shape,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          miroToolbarShapeIcon(shape),
                          size: 19,
                          color: textColor,
                        ),
                        const SizedBox(width: 10),
                        Text(miroToolbarShapeLabel(shape)),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            miroToolbarShapeIcon(selectedShape),
            size: 22,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

class MiroToolbarIcon extends StatelessWidget {
  const MiroToolbarIcon({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    required this.color,
    this.swatch,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              if (swatch != null)
                Positioned(
                  right: 7,
                  bottom: 7,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    child: const SizedBox(width: 8, height: 8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class MiroToolbarDragIcon extends StatelessWidget {
  const MiroToolbarDragIcon({
    super.key,
    required this.tooltip,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.color,
  });

  final String tooltip;
  final ValueChanged<DragStartDetails> onStart;
  final ValueChanged<DragUpdateDetails>? onUpdate;
  final VoidCallback onEnd;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor:
            onUpdate == null
                ? SystemMouseCursors.forbidden
                : SystemMouseCursors.move,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: onStart,
          onPanUpdate: onUpdate,
          onPanEnd: (_) => onEnd(),
          onPanCancel: onEnd,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.open_with_rounded, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

class MiroToolbarDivider extends StatelessWidget {
  const MiroToolbarDivider({super.key, required this.colors});

  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: colors.divider,
    );
  }
}

Future<Color?> showMiroToolbarCustomColor(
  BuildContext context,
  Color initialColor,
) {
  var selectedColor =
      initialColor.a == 0
          ? Theme.of(context).colorScheme.primary
          : initialColor;
  return showDialog<Color?>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: const Text('Custom color'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: ColorPicker(
                pickerColor: selectedColor,
                onColorChanged: (color) {
                  selectedColor = color;
                },
                enableAlpha: true,
                displayThumbColor: true,
                portraitOnly: true,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(selectedColor),
              child: const Text('Apply'),
            ),
          ],
        ),
  );
}

String miroToolbarHex(Color color) {
  final alpha = (color.a * 255).round() & 255;
  final red = (color.r * 255).round() & 255;
  final green = (color.g * 255).round() & 255;
  final blue = (color.b * 255).round() & 255;
  if (alpha == 255) {
    return '#${red.toRadixString(16).padLeft(2, '0')}'
            '${green.toRadixString(16).padLeft(2, '0')}'
            '${blue.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }
  return '#${alpha.toRadixString(16).padLeft(2, '0')}'
          '${red.toRadixString(16).padLeft(2, '0')}'
          '${green.toRadixString(16).padLeft(2, '0')}'
          '${blue.toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
}

String miroToolbarColorLabel(Color color) =>
    color.a == 0 ? 'Transparent' : miroToolbarHex(color);

IconData miroToolbarShapeIcon(String shape) => switch (shape) {
  'circle' => Icons.circle_outlined,
  'diamond' => Icons.diamond_outlined,
  'triangle' => Icons.change_history_rounded,
  'hexagon' => Icons.hexagon_outlined,
  'frame' => Icons.crop_square_rounded,
  _ => Icons.rectangle_outlined,
};

String miroToolbarShapeLabel(String shape) => switch (shape) {
  'circle' => 'Oval',
  'diamond' => 'Rhombus',
  'triangle' => 'Triangle',
  'hexagon' => 'Hexagon',
  'frame' => 'Frame',
  _ => 'Rectangle',
};

IconData miroToolbarHorizontalAlignIcon(String value) => switch (value) {
  'left' => Icons.format_align_left_rounded,
  'right' => Icons.format_align_right_rounded,
  _ => Icons.format_align_center_rounded,
};

String miroToolbarHorizontalAlignLabel(String value) => switch (value) {
  'left' => 'Left',
  'right' => 'Right',
  _ => 'Center',
};

IconData miroToolbarVerticalAlignIcon(String value) => switch (value) {
  'top' => Icons.vertical_align_top_rounded,
  'bottom' => Icons.vertical_align_bottom_rounded,
  _ => Icons.vertical_align_center_rounded,
};

String miroToolbarVerticalAlignLabel(String value) => switch (value) {
  'top' => 'Top',
  'bottom' => 'Bottom',
  _ => 'Middle',
};

IconData miroToolbarTextOrientationIcon(String value) => switch (value) {
  'vertical' => Icons.text_rotation_angleup_rounded,
  _ => Icons.text_fields_rounded,
};

String miroToolbarTextOrientationLabel(String value) => switch (value) {
  'vertical' => 'Vertical',
  _ => 'Horizontal',
};
