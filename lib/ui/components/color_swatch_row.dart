import 'package:flutter/material.dart';
import 'package:yoloit/core/utils/color_utils.dart';

/// A row of circular color swatches for picking a color from a list of hex
/// strings.  Used by board plugin editors (sticky note, shape, etc.).
class ColorSwatchRow extends StatelessWidget {
  const ColorSwatchRow({
    super.key,
    required this.colors,
    required this.selected,
    required this.onSelected,
    this.transparentIcon,
  });

  /// List of hex color strings (e.g. `['#FF5733', '#00000000']`).
  final List<String> colors;

  /// Currently selected hex string.
  final String selected;

  /// Called when the user taps a swatch.
  final ValueChanged<String> onSelected;

  /// Optional widget shown inside a swatch when its hex is `'#00000000'`
  /// (fully transparent).  If `null`, transparent swatches render empty.
  final Widget? transparentIcon;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          colors.map((hex) {
            final color = parseHexColor(hex) ?? Colors.transparent;
            final isTransparent = hex == '#00000000';
            final isSelected = selected.toUpperCase() == hex.toUpperCase();
            return InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onSelected(hex),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor,
                    width: isSelected ? 3 : 1,
                  ),
                ),
                child: isTransparent ? transparentIcon : null,
              ),
            );
          }).toList(),
    );
  }
}
