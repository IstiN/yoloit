import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/chart/model/chart_models.dart';

void main() {
  final colors = AppColorScheme.fromAccent(const Color(0xFF7C4DFF));
  final data = ChartDataHelper.defaultData();

  test('buildLineData produces line bars', () {
    final chart = ChartDataHelper.buildLineData(
      data: data,
      xKey: 'month',
      yKey: 'sales',
      colors: colors,
      area: false,
      animated: false,
    );
    expect(chart.lineBarsData, isNotEmpty);
  });

  test('buildBarData produces bar groups', () {
    final chart = ChartDataHelper.buildBarData(
      data: data,
      xKey: 'month',
      yKey: 'sales',
      colors: colors,
      animated: false,
    );
    expect(chart.barGroups.length, data.length);
  });

  test('buildPieData produces sections', () {
    final chart = ChartDataHelper.buildPieData(
      data: data,
      xKey: 'month',
      yKey: 'sales',
      colors: colors,
      animated: false,
    );
    expect(chart.sections.length, data.length);
  });

  test('buildScatterData produces spots', () {
    final chart = ChartDataHelper.buildScatterData(
      data: data,
      xKey: 'month',
      yKey: 'sales',
      colors: colors,
    );
    expect(chart.scatterSpots, isNotEmpty);
  });

  test('buildRadarData produces dataset', () {
    final chart = ChartDataHelper.buildRadarData(
      data: data,
      xKey: 'month',
      yKey: 'sales',
      colors: colors,
    );
    expect(chart.dataSets.single.dataEntries.length, data.length);
  });
}
