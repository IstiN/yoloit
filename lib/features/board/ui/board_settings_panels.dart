import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/tools/board_tool.dart';
import 'package:yoloit/features/board/ui/board_link_widgets.dart';

class DrawSettingsPanel extends StatelessWidget {
  const DrawSettingsPanel({super.key, required this.settings, required this.onChanged});

  final DrawSettings settings;
  final ValueChanged<DrawSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor = colors.textMuted;
    return _SettingsPanel(
      width: 160,
      title: 'Draw settings',
      children: [
        // Color swatches
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in [
                colors.primaryLight,
                colors.accentBlue,
                colors.statusActive,
                colors.statusWarning,
                colors.statusError,
                colors.textPrimary,
              ])
                GestureDetector(
                  onTap: () => onChanged(settings.copyWith(strokeColor: c)),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            settings.strokeColor == c
                                ? colors.textPrimary
                                : colors.textPrimary.withAlpha(40),
                        width: settings.strokeColor == c ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              // Custom color picker
              GestureDetector(
                onTap: () async {
                  Color picked = settings.strokeColor;
                  await showDialog<void>(
                    context: context,
                    builder:
                        (ctx) => AlertDialog(
                          title: const Text('Stroke color'),
                          content: ColorPicker(
                            pickerColor: picked,
                            onColorChanged: (c) => picked = c,
                            enableAlpha: false,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () {
                                onChanged(
                                  settings.copyWith(strokeColor: picked),
                                );
                                Navigator.of(ctx).pop();
                              },
                              child: const Text('Apply'),
                            ),
                          ],
                        ),
                  );
                },
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: SweepGradient(
                      colors: [
                        colors.statusError,
                        colors.statusWarning,
                        colors.statusActive,
                        colors.accentBlue,
                        colors.primary,
                        colors.primaryLight,
                        colors.statusError,
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.textPrimary.withAlpha(60)),
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        // Stroke width slider
        Text('Size', style: TextStyle(color: mutedColor, fontSize: 11)),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: settings.strokeColor,
            thumbColor: settings.strokeColor,
            overlayColor: settings.strokeColor.withAlpha(40),
            inactiveTrackColor: colors.border,
          ),
          child: Slider(
            value: settings.strokeWidth,
            min: 1,
            max: 20,
            onChanged: (v) => onChanged(settings.copyWith(strokeWidth: v)),
          ),
        ),
      ],
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.width,
    required this.title,
    required this.children,
  });

  final double width;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor = colors.textMuted;
    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(0xE5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: mutedColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class ConnectSettingsPanel extends StatelessWidget {
  const ConnectSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final ConnectSettings settings;
  final ValueChanged<ConnectSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor = colors.textMuted;
    final activeColor = settings.color;
    return _SettingsPanel(
      width: 200,
      title: 'Connect',
      children: [
        // ── Live mini preview ──────────────────────────────────────────
          SizedBox(
            height: 56,
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  size: const Size(double.infinity, 56),
                  painter: LinkPreviewPainter(
                    geometry: settings.geometry,
                    showArrow: settings.showArrow,
                    color: activeColor,
                    borderColor: colors.border,
                    panelColor: colors.surface,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // ── Geometry buttons ───────────────────────────────────────────
          Row(
            children: [
              for (final geo in BoardLinkGeometry.values) ...[
                if (BoardLinkGeometry.values.indexOf(geo) > 0)
                  const SizedBox(width: 4),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(settings.copyWith(geometry: geo)),
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color:
                            settings.geometry == geo
                                ? activeColor.withAlpha(25)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              settings.geometry == geo
                                  ? activeColor.withAlpha(160)
                                  : colors.border,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CustomPaint(
                            size: const Size(32, 14),
                            painter: LinkMiniPreviewPainter(
                              geometry: geo,
                              color:
                                  settings.geometry == geo
                                      ? activeColor
                                      : mutedColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            switch (geo) {
                              BoardLinkGeometry.bezier => 'Bézier',
                              BoardLinkGeometry.straight => 'Line',
                              BoardLinkGeometry.elbow => 'Elbow',
                            },
                            style: TextStyle(
                              fontSize: 8,
                              color:
                                  settings.geometry == geo
                                      ? activeColor
                                      : mutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // ── Arrow + color row ──────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Arrow', style: TextStyle(color: mutedColor, fontSize: 11)),
              Transform.scale(
                scale: 0.75,
                alignment: Alignment.centerRight,
                child: Switch.adaptive(
                  value: settings.showArrow,
                  onChanged: (v) => onChanged(settings.copyWith(showArrow: v)),
                  activeColor: activeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ── Color swatches ─────────────────────────────────────────────
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final c in [
                colors.accentBlue,
                colors.statusActive,
                colors.statusError,
                colors.statusWarning,
                colors.primaryLight,
                colors.textPrimary,
              ])
                GestureDetector(
                  onTap: () => onChanged(settings.copyWith(color: c)),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            settings.color == c
                                ? colors.textPrimary
                                : colors.textPrimary.withAlpha(30),
                        width: settings.color == c ? 2 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
  }
}
