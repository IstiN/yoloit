import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/table/model/table_models.dart';

enum ChartType { line, bar, pie, scatter, radar, area }

extension ChartTypeExtension on ChartType {
  static ChartType fromJson(dynamic value) {
    final raw = value?.toString().toLowerCase() ?? 'line';
    return ChartType.values.firstWhere(
      (t) => t.name == raw,
      orElse: () => ChartType.line,
    );
  }
}

/// Helpers for parsing Chart panel state and building fl_chart data objects.
class ChartDataHelper {
  const ChartDataHelper._();

  static List<Map<String, dynamic>> defaultData() => <Map<String, dynamic>>[
    {'month': 'Jan', 'sales': 120},
    {'month': 'Feb', 'sales': 190},
    {'month': 'Mar', 'sales': 150},
    {'month': 'Apr', 'sales': 220},
    {'month': 'May', 'sales': 280},
  ];

  static ChartType typeFromState(Map<String, dynamic> state) =>
      ChartTypeExtension.fromJson(state['type']);

  static String xKeyFromState(Map<String, dynamic> state) =>
      _string(state['xKey']) ?? 'month';

  static String yKeyFromState(Map<String, dynamic> state) =>
      _string(state['yKey']) ?? 'sales';

  static String? groupKeyFromState(Map<String, dynamic> state) =>
      _string(state['groupKey']);

  static String? tablePanelIdFromState(Map<String, dynamic> state) =>
      _string(state['tablePanelId']);

  static bool animatedFromState(Map<String, dynamic> state) {
    final raw = state['animated'];
    if (raw is bool) return raw;
    if (raw is String) return raw.toLowerCase() == 'true';
    return true;
  }

  static List<Map<String, dynamic>> resolveData(
    Map<String, dynamic> state,
    BoardPanelRenderContext renderContext,
  ) {
    final tablePanelId = tablePanelIdFromState(state);
    if (tablePanelId != null && tablePanelId.isNotEmpty) {
      final tablePanel = renderContext.onFindPanelById?.call(tablePanelId);
      if (tablePanel != null) {
        final rows = TableDataHelper.parseRows(tablePanel.state['rows']);
        return rows.map((row) => row.cells).toList();
      }
    }
    final inline = state['data'];
    if (inline is List) {
      return
          inline
              .whereType<Map<Object?, Object?>>()
              .map(
                (entry) => Map<String, dynamic>.from(
                  entry.map((k, v) => MapEntry(k.toString(), v)),
                ),
              )
              .toList();
    }
    return defaultData();
  }

  static LineChartData buildLineData({
    required List<Map<String, dynamic>> data,
    required String xKey,
    required String yKey,
    String? groupKey,
    required AppColorScheme colors,
    required bool area,
    required bool animated,
  }) {
    final series = _groupSeries(data, groupKey);
    final isNumericX = _isNumericX(data, xKey);
    final xLabels = _xLabels(data, xKey);

    return LineChartData(
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: _axisTitles(xLabels, colors, numericX: isNumericX),
      borderData: FlBorderData(show: true),
      lineBarsData: [
        for (var i = 0; i < series.length; i++)
          _lineBar(
            series[i],
            xKey,
            yKey,
            _seriesColor(i, colors),
            area: area,
            animated: animated,
          ),
      ],
      lineTouchData: const LineTouchData(enabled: true),
    );
  }

  static BarChartData buildBarData({
    required List<Map<String, dynamic>> data,
    required String xKey,
    required String yKey,
    String? groupKey,
    required AppColorScheme colors,
    required bool animated,
  }) {
    final series = _groupSeries(data, groupKey);
    final xLabels = _xLabels(data, xKey);

    return BarChartData(
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: _axisTitles(xLabels, colors),
      borderData: FlBorderData(show: true),
      barGroups: [
        for (var i = 0; i < data.length; i++)
          BarChartGroupData(
            x: i,
            barRods: [
              for (var s = 0; s < series.length; s++)
                BarChartRodData(
                  toY: _toDouble(data[i][yKey]),
                  color: _seriesColor(s, colors),
                  width: 12,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
            ],
          ),
      ],
      barTouchData: BarTouchData(enabled: true),
    );
  }

  static PieChartData buildPieData({
    required List<Map<String, dynamic>> data,
    required String xKey,
    required String yKey,
    required AppColorScheme colors,
    required bool animated,
    double? radius,
    int? touchedIndex,
    PieTouchData? pieTouchData,
  }) {
    final effectiveRadius = radius ?? 80;
    return PieChartData(
      sections: [
        for (var i = 0; i < data.length; i++)
          PieChartSectionData(
            value: _toDouble(data[i][yKey]).clamp(0, double.infinity),
            title: '${data[i][xKey]}',
            color: _seriesColor(i, colors),
            radius: i == touchedIndex ? effectiveRadius * 1.2 : effectiveRadius,
            titleStyle: TextStyle(
              fontSize: i == touchedIndex ? 12 : 10,
              fontWeight:
                  i == touchedIndex ? FontWeight.bold : FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
      ],
      sectionsSpace: 2,
      centerSpaceRadius: effectiveRadius * 0.4,
      pieTouchData: pieTouchData ?? PieTouchData(enabled: true),
    );
  }

  static ScatterChartData buildScatterData({
    required List<Map<String, dynamic>> data,
    required String xKey,
    required String yKey,
    String? groupKey,
    required AppColorScheme colors,
  }) {
    final series = _groupSeries(data, groupKey);
    return ScatterChartData(
      gridData: const FlGridData(show: true),
      titlesData: _axisTitles(<String>[], colors, numericX: true),
      borderData: FlBorderData(show: true),
      scatterSpots: [
        for (var s = 0; s < series.length; s++)
          for (final row in series[s])
            ScatterSpot(
              _toDouble(row[xKey]),
              _toDouble(row[yKey]),
              dotPainter: FlDotCirclePainter(
                color: _seriesColor(s, colors),
                radius: 5,
              ),
            ),
      ],
      scatterTouchData: ScatterTouchData(enabled: true),
    );
  }

  static RadarChartData buildRadarData({
    required List<Map<String, dynamic>> data,
    required String xKey,
    required String yKey,
    required AppColorScheme colors,
  }) {
    final entries = data.take(8).toList();
    final values = entries.map((row) => _toDouble(row[yKey])).toList();
    final maxValue = values.isEmpty ? 1 : values.reduce(math.max);
    return RadarChartData(
      radarShape: RadarShape.circle,
      dataSets: [
        RadarDataSet(
          dataEntries: [
            for (final row in entries)
              RadarEntry(value: _toDouble(row[yKey])),
          ],
          fillColor: colors.accentBlue.withValues(alpha: 0.3),
          borderColor: colors.accentBlue,
          borderWidth: 2,
        ),
      ],
      radarBorderData: BorderSide(color: colors.border),
      gridBorderData: BorderSide(color: colors.border),
      tickBorderData: BorderSide(color: colors.border),
      titlePositionPercentageOffset: 0.12,
      ticksTextStyle: TextStyle(color: colors.textMuted, fontSize: 9),
      getTitle: (index, angle) {
        if (index < 0 || index >= entries.length) return const RadarChartTitle(text: '');
        return RadarChartTitle(text: '${entries[index][xKey]}');
      },
      tickCount: maxValue > 0 ? 4 : 1,
    );
  }

  static LineChartBarData _lineBar(
    List<Map<String, dynamic>> data,
    String xKey,
    String yKey,
    Color color, {
    required bool area,
    required bool animated,
  }) {
    final isNumericX = _isNumericX(data, xKey);
    return LineChartBarData(
      spots: [
        for (var i = 0; i < data.length; i++)
          FlSpot(
            isNumericX ? _toDouble(data[i][xKey]) : i.toDouble(),
            _toDouble(data[i][yKey]),
          ),
      ],
      isCurved: true,
      color: color,
      barWidth: 3,
      dotData: FlDotData(show: data.length < 24),
      belowBarData:
          area
              ? BarAreaData(
                  show: true,
                  color: color.withValues(alpha: 0.2),
                )
              : BarAreaData(show: false),
      preventCurveOverShooting: true,
    );
  }

  static List<List<Map<String, dynamic>>> _groupSeries(
    List<Map<String, dynamic>> data,
    String? groupKey,
  ) {
    if (groupKey == null || groupKey.isEmpty) return <List<Map<String, dynamic>>>[data];
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in data) {
      final key = row[groupKey]?.toString() ?? '';
      groups.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(row);
    }
    return groups.values.toList();
  }

  static List<String> _xLabels(List<Map<String, dynamic>> data, String xKey) =>
      data.map((row) => row[xKey]?.toString() ?? '').toList();

  static bool _isNumericX(List<Map<String, dynamic>> data, String xKey) {
    if (data.isEmpty) return false;
    final first = data.first[xKey];
    return first is num || (first is String && double.tryParse(first) != null);
  }

  static FlTitlesData _axisTitles(
    List<String> xLabels,
    AppColorScheme colors, {
    bool numericX = false,
  }) {
    return FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          getTitlesWidget: (value, meta) => Text(
            value.toStringAsFixed(value == value.toInt() ? 0 : 1),
            style: TextStyle(fontSize: 9, color: colors.textMuted),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (numericX || index < 0 || index >= xLabels.length) {
              return const SizedBox.shrink();
            }
            return Text(
              xLabels[index],
              style: TextStyle(fontSize: 9, color: colors.textMuted),
            );
          },
        ),
      ),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  static Color _seriesColor(int index, AppColorScheme colors) {
    final palette = <Color>[
      colors.accentBlue,
      colors.accentGreen,
      colors.accentOrange,
      colors.accentRed,
      colors.orbCyan,
      colors.orbPurple,
      colors.orbPink,
      colors.primary,
    ];
    return palette[index % palette.length];
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static String? _string(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
