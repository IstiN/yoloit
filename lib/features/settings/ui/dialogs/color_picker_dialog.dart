import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

/// HSV-based color picker dialog.
class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({
    super.key,
    required this.title,
    required this.initialColor,
  });

  final String title;
  final Color initialColor;

  @override
  State<ColorPickerDialog> createState() => ColorPickerDialogState();
}

class ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor _hsv;
  late TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(text: _colorToHex(_hsv.toColor()));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _colorToHex(Color c) {
    return '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _updateFromHex(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return;
    try {
      final color = Color(int.parse('FF$h', radix: 16));
      setState(() {
        _hsv = HSVColor.fromColor(color);
      });
    } catch (_) {}
  }

  static const _presetColors = [
    Color(0xFF00FF9F),
    Color(0xFF00DD88),
    Color(0xFF00CC7A),
    Color(0xFF067D17),
    Color(0xFF2ECC71),
    Color(0xFF27AE60),
    Color(0xFF1ABC9C),
    Color(0xFF16A085),
    Color(0xFFFF4F6A),
    Color(0xFFFF6B6B),
    Color(0xFFE74C3C),
    Color(0xFFC0392B),
    Color(0xFFDE1B2E),
    Color(0xFFFF1744),
    Color(0xFFD50000),
    Color(0xFFB71C1C),
    Color(0xFF00B4FF),
    Color(0xFF3498DB),
    Color(0xFF2980B9),
    Color(0xFF0066CC),
    Color(0xFF548AF7),
    Color(0xFF2196F3),
    Color(0xFF1976D2),
    Color(0xFF0D47A1),
    Color(0xFFFF9500),
    Color(0xFFF39C12),
    Color(0xFFE67E22),
    Color(0xFFD35400),
    Color(0xFFCC7700),
    Color(0xFFFF6F00),
    Color(0xFFFF8F00),
    Color(0xFFFFAB00),
    Color(0xFF9B59B6),
    Color(0xFF8E44AD),
    Color(0xFF7C3AED),
    Color(0xFF6C3483),
    Color(0xFFE91E63),
    Color(0xFFF06292),
    Color(0xFFFFEB3B),
    Color(0xFFCDDC39),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final pickedColor = _hsv.toColor();
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: pickedColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.border),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hexController,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontFamily: 'SF Mono',
                      ),
                      decoration: InputDecoration(
                        labelText: 'Hex',
                        labelStyle: TextStyle(
                          color: colors.textMuted,
                          fontSize: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (v) {
                        _updateFromHex(v);
                        _hexController.text = _colorToHex(_hsv.toColor());
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              HsvSlider(
                label: 'Hue',
                value: _hsv.hue,
                max: 360,
                color: _hsv.toColor(),
                borderColor: colors.border,
                labelColor: colors.textMuted,
                onChanged:
                    (v) => setState(() {
                      _hsv = _hsv.withHue(v);
                      _hexController.text = _colorToHex(_hsv.toColor());
                    }),
              ),
              const SizedBox(height: 8),
              HsvSlider(
                label: 'Saturation',
                value: _hsv.saturation,
                max: 1,
                color: _hsv.toColor(),
                borderColor: colors.border,
                labelColor: colors.textMuted,
                onChanged:
                    (v) => setState(() {
                      _hsv = _hsv.withSaturation(v);
                      _hexController.text = _colorToHex(_hsv.toColor());
                    }),
              ),
              const SizedBox(height: 8),
              HsvSlider(
                label: 'Brightness',
                value: _hsv.value,
                max: 1,
                color: _hsv.toColor(),
                borderColor: colors.border,
                labelColor: colors.textMuted,
                onChanged:
                    (v) => setState(() {
                      _hsv = _hsv.withValue(v);
                      _hexController.text = _colorToHex(_hsv.toColor());
                    }),
              ),
              const SizedBox(height: 14),
              const Caption('Presets', fontSize: 10),
              const SizedBox(height: 6),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children:
                    _presetColors.map((c) {
                      return GestureDetector(
                        onTap:
                            () => setState(() {
                              _hsv = HSVColor.fromColor(c);
                              _hexController.text = _colorToHex(c);
                            }),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color:
                                  c == pickedColor
                                      ? Colors.white
                                      : colors.border,
                              width: c == pickedColor ? 2 : 1,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: colors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(pickedColor),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HsvSlider extends StatelessWidget {
  const HsvSlider({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    required this.borderColor,
    required this.labelColor,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final Color color;
  final Color borderColor;
  final Color labelColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: labelColor, fontSize: 10)),
        const SizedBox(height: 2),
        SizedBox(
          height: 24,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 10,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: color,
              inactiveTrackColor: borderColor,
              thumbColor: Colors.white,
            ),
            child: Slider(value: value, min: 0, max: max, onChanged: onChanged),
          ),
        ),
      ],
    );
  }
}
