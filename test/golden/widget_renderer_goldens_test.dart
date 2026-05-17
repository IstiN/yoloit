// Golden tests for the native JS widget rendering pipeline.
//
// These tests verify that JsonWidgetRenderer correctly converts JSON trees
// (as produced by JS widgets via yoloit.render()) into Flutter UI.
//
// The test covers every widget type used by the 4 built-in example widgets:
// calculator, crypto, stocks, weather — plus error and picker states.
//
// Tests are organised by widget type / scenario so that a golden mismatch
// immediately pinpoints the broken node type.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/widgets/json_widget_renderer.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _shell({
  required Widget child,
  double width = 360,
  double height = 520,
}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        backgroundColor: const Color(0xFF0F0F1A),
        body: SizedBox(width: width, height: height, child: child),
      ),
    );

final _noop = JsonWidgetRenderer(onEvent: (_, __) {});

Widget _render(Map<String, dynamic> tree, {double w = 360, double h = 520}) =>
    _shell(width: w, height: h, child: _noop.build(tree));

// ---------------------------------------------------------------------------
// Calculator JSON tree (mirrors what calculator/widget.js produces)
// ---------------------------------------------------------------------------

Map<String, dynamic> _calcTree() {
  const opBg = '#b45309';
  const numBg = '#1e293b';
  const specBg = '#334155';
  const eqBg = '#2563eb';

  List<Map<String, dynamic>> btnRow(List<String> keys) {
    return [
      {
        'type': 'row',
        'children': keys.map((k) {
          final bg = ['÷', '×', '−', '+'].contains(k)
              ? opBg
              : k == '='
                  ? eqBg
                  : ['C', '±', '%', '⌫'].contains(k)
                      ? specBg
                      : numBg;
          return {
            'type': 'expanded',
            'child': {
              'type': 'padding',
              'padding': [3, 3, 3, 3],
              'child': {
                'type': 'inkWell',
                'onTap': 'btn_$k',
                'borderRadius': 8,
                'child': {
                  'type': 'container',
                  'decoration': {'color': bg, 'borderRadius': 8},
                  'padding': [0, 14, 0, 14],
                  'child': {
                    'type': 'text',
                    'data': k,
                    'style': {
                      'color': '#ffffff',
                      'fontSize': 18,
                      'fontWeight': 'w600',
                      'textAlign': 'center',
                    },
                  },
                },
              },
            },
          };
        }).toList(),
      }
    ];
  }

  final rows = [
    ...btnRow(['C', '±', '%', '÷']),
    ...btnRow(['7', '8', '9', '×']),
    ...btnRow(['4', '5', '6', '−']),
    ...btnRow(['1', '2', '3', '+']),
    ...btnRow(['0', '.', '⌫', '=']),
  ];

  final display = {
    'type': 'container',
    'decoration': {'color': '#0f172a', 'borderRadius': 12},
    'padding': [16, 12, 16, 12],
    'margin': [0, 0, 0, 8],
    'child': {
      'type': 'column',
      'crossAxisAlignment': 'end',
      'children': [
        {
          'type': 'text',
          'data': '2+2',
          'style': {'color': '#475569', 'fontSize': 13},
          'maxLines': 1,
          'overflow': 'ellipsis',
        },
        {'type': 'sizedBox', 'height': 4},
        {
          'type': 'text',
          'data': '4',
          'style': {
            'color': '#f1f5f9',
            'fontSize': 32,
            'fontWeight': 'w700',
          },
          'maxLines': 1,
          'overflow': 'ellipsis',
        },
      ],
    },
  };

  return {
    'type': 'padding',
    'padding': [12, 12, 12, 12],
    'child': {
      'type': 'column',
      'crossAxisAlignment': 'stretch',
      'children': [display, ...rows],
    },
  };
}

// ---------------------------------------------------------------------------
// Crypto-style card list tree
// ---------------------------------------------------------------------------

Map<String, dynamic> _cryptoTree() => {
      'type': 'column',
      'children': [
        {
          'type': 'padding',
          'padding': [16, 16, 16, 8],
          'child': {
            'type': 'text',
            'data': 'Crypto Prices',
            'style': {
              'color': '#f1f5f9',
              'fontSize': 18,
              'fontWeight': 'w700',
            },
          },
        },
        ...[
          {'name': 'Bitcoin', 'symbol': 'BTC', 'price': '\$67,432.10', 'change': '+2.4%', 'up': true},
          {'name': 'Ethereum', 'symbol': 'ETH', 'price': '\$3,521.80', 'change': '-0.8%', 'up': false},
          {'name': 'Solana', 'symbol': 'SOL', 'price': '\$178.45', 'change': '+5.1%', 'up': true},
        ].map(
          (c) => {
            'type': 'container',
            'margin': [12, 0, 12, 8],
            'decoration': {'color': '#1e293b', 'borderRadius': 12},
            'padding': [14, 12, 14, 12],
            'child': {
              'type': 'row',
              'mainAxisAlignment': 'spaceBetween',
              'children': [
                {
                  'type': 'column',
                  'crossAxisAlignment': 'start',
                  'children': [
                    {
                      'type': 'text',
                      'data': c['name']!,
                      'style': {'color': '#f1f5f9', 'fontSize': 15, 'fontWeight': 'w600'},
                    },
                    {
                      'type': 'text',
                      'data': c['symbol']!,
                      'style': {'color': '#64748b', 'fontSize': 12},
                    },
                  ],
                },
                {
                  'type': 'column',
                  'crossAxisAlignment': 'end',
                  'children': [
                    {
                      'type': 'text',
                      'data': c['price']!,
                      'style': {'color': '#f1f5f9', 'fontSize': 15, 'fontWeight': 'w600'},
                    },
                    {
                      'type': 'text',
                      'data': c['change']!,
                      'style': {
                        'color': (c['up'] as bool) ? '#22c55e' : '#ef4444',
                        'fontSize': 12,
                      },
                    },
                  ],
                },
              ],
            },
          },
        ),
      ],
    };

// ---------------------------------------------------------------------------
// Weather-style card tree
// ---------------------------------------------------------------------------

Map<String, dynamic> _weatherTree() => {
      'type': 'center',
      'child': {
        'type': 'padding',
        'padding': [16, 16, 16, 16],
        'child': {
          'type': 'column',
          'mainAxisAlignment': 'center',
          'children': [
            {
              'type': 'text',
              'data': '🌤️',
              'style': {'fontSize': 64},
            },
            {'type': 'sizedBox', 'height': 8},
            {
              'type': 'text',
              'data': 'Berlin',
              'style': {'color': '#94a3b8', 'fontSize': 18},
            },
            {
              'type': 'text',
              'data': '21°C',
              'style': {
                'color': '#f1f5f9',
                'fontSize': 48,
                'fontWeight': 'w700',
              },
            },
            {'type': 'sizedBox', 'height': 4},
            {
              'type': 'text',
              'data': 'Partly cloudy · Humidity 62%',
              'style': {'color': '#64748b', 'fontSize': 13},
            },
            {'type': 'sizedBox', 'height': 20},
            {
              'type': 'divider',
              'color': '#334155',
            },
            {'type': 'sizedBox', 'height': 12},
            {
              'type': 'row',
              'mainAxisAlignment': 'spaceAround',
              'children': [
                ...[
                  {'label': 'Feels', 'value': '19°C'},
                  {'label': 'Wind', 'value': '14 km/h'},
                  {'label': 'UV', 'value': '4'},
                ].map(
                  (s) => {
                    'type': 'column',
                    'children': [
                      {
                        'type': 'text',
                        'data': s['value']!,
                        'style': {'color': '#e2e8f0', 'fontSize': 15, 'fontWeight': 'w600'},
                      },
                      {
                        'type': 'text',
                        'data': s['label']!,
                        'style': {'color': '#64748b', 'fontSize': 11},
                      },
                    ],
                  },
                ),
              ],
            },
          ],
        },
      },
    };

// ---------------------------------------------------------------------------
// Error state tree (produced by yoloit.showError)
// ---------------------------------------------------------------------------

Map<String, dynamic> _errorTree(String msg) => {
      'type': 'center',
      'child': {
        'type': 'padding',
        'padding': [16, 16, 16, 16],
        'child': {
          'type': 'column',
          'mainAxisSize': 'min',
          'children': [
            {'type': 'text', 'data': '⚠️', 'style': {'fontSize': 28}},
            {'type': 'sizedBox', 'height': 8},
            {
              'type': 'text',
              'data': msg,
              'style': {'color': '#ef4444', 'fontSize': 13, 'textAlign': 'center'},
            },
          ],
        },
      },
    };

// ---------------------------------------------------------------------------
// Loading state tree
// ---------------------------------------------------------------------------

Map<String, dynamic> _loadingTree() => {
      'type': 'center',
      'child': {
        'type': 'column',
        'mainAxisSize': 'min',
        'children': [
          {'type': 'circularProgressIndicator', 'size': 32, 'strokeWidth': 2},
          {'type': 'sizedBox', 'height': 12},
          {
            'type': 'text',
            'data': 'Loading…',
            'style': {'color': '#64748b', 'fontSize': 13},
          },
        ],
      },
    };

// ---------------------------------------------------------------------------
// Helper: skip pumpAndSettle for tests with infinite animations (spinners)
// ---------------------------------------------------------------------------

Future<void> _pumpOnce(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 50));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Golden tests — JsonWidgetRenderer', () {
    testGoldens('calculator layout', (tester) async {
      await tester.pumpWidgetBuilder(
        _render(_calcTree(), h: 520),
        surfaceSize: const Size(360, 520),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'widget_calculator',
          customPump: _pumpOnce);
    });

    testGoldens('crypto price list', (tester) async {
      await tester.pumpWidgetBuilder(
        _render(_cryptoTree(), h: 400),
        surfaceSize: const Size(360, 400),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'widget_crypto',
          customPump: _pumpOnce);
    });

    testGoldens('weather card', (tester) async {
      await tester.pumpWidgetBuilder(
        _render(_weatherTree(), h: 480),
        surfaceSize: const Size(360, 480),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'widget_weather',
          customPump: _pumpOnce);
    });

    testGoldens('error state', (tester) async {
      await tester.pumpWidgetBuilder(
        _render(_errorTree('Network request failed: Connection timeout'), h: 200),
        surfaceSize: const Size(360, 200),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'widget_error_state',
          customPump: _pumpOnce);
    });

    testGoldens('loading state', (tester) async {
      await tester.pumpWidgetBuilder(
        _render(_loadingTree(), h: 200),
        surfaceSize: const Size(360, 200),
      );
      await tester.pump();
      // customPump required — CircularProgressIndicator never settles
      await screenMatchesGolden(tester, 'widget_loading_state',
          customPump: _pumpOnce);
    });

    // Verify every leaf node type renders without throwing.
    testGoldens('all node types grid', (tester) async {
      final tree = {
        'type': 'column',
        'crossAxisAlignment': 'stretch',
        'children': [
          // text variants
          {'type': 'text', 'data': 'Normal text'},
          {'type': 'text', 'data': 'Bold w700', 'style': {'fontWeight': 'w700', 'color': '#7c3aed'}},
          {'type': 'text', 'data': 'Small muted', 'style': {'fontSize': 11, 'color': '#64748b'}},
          {'type': 'divider'},
          // icon (material name + emoji)
          {
            'type': 'row',
            'children': [
              {'type': 'icon', 'name': 'star', 'color': '#f59e0b', 'size': 20},
              {'type': 'sizedBox', 'width': 8},
              {'type': 'icon', 'name': '☀️', 'size': 20},
              {'type': 'sizedBox', 'width': 8},
              {'type': 'text', 'data': 'Icons'},
            ],
          },
          {'type': 'divider'},
          // container with decoration
          {
            'type': 'container',
            'decoration': {'color': '#1e293b', 'borderRadius': 8},
            'padding': [12, 8, 12, 8],
            'margin': [0, 4, 0, 4],
            'child': {'type': 'text', 'data': 'Decorated container', 'style': {'color': '#f1f5f9'}},
          },
          // card
          {
            'type': 'card',
            'color': '#1e293b',
            'child': {
              'type': 'padding',
              'padding': [12, 8, 12, 8],
              'child': {'type': 'text', 'data': 'Card widget'},
            },
          },
          // button types
          {
            'type': 'wrap',
            'spacing': 8,
            'runSpacing': 8,
            'children': [
              {'type': 'button', 'label': 'Elevated', 'onTap': 'ev'},
              {'type': 'textButton', 'label': 'Text', 'onTap': 'tb'},
              {'type': 'outlinedButton', 'label': 'Outlined', 'onTap': 'ob'},
            ],
          },
          // wrap
          {
            'type': 'wrap',
            'spacing': 6,
            'runSpacing': 6,
            'children': ['Dart', 'Flutter', 'JS', 'Widgets'].map((t) => {
              'type': 'container',
              'decoration': {'color': '#334155', 'borderRadius': 16},
              'padding': [8, 4, 8, 4],
              'child': {'type': 'text', 'data': t, 'style': {'color': '#e2e8f0', 'fontSize': 11}},
            }).toList(),
          },
          // spinner
          {
            'type': 'row',
            'mainAxisAlignment': 'center',
            'children': [
              {'type': 'circularProgressIndicator', 'size': 20, 'strokeWidth': 2},
              {'type': 'sizedBox', 'width': 8},
              {'type': 'text', 'data': 'Loading…', 'style': {'color': '#64748b'}},
            ],
          },
        ],
      };

      await tester.pumpWidgetBuilder(
        _render(tree, h: 560),
        surfaceSize: const Size(360, 560),
      );
      await tester.pump();
      // customPump required — CircularProgressIndicator never settles
      await screenMatchesGolden(tester, 'widget_all_node_types',
          customPump: _pumpOnce);
    });
  });
}
