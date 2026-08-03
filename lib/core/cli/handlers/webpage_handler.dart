import 'dart:convert';

import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/webview_manager.dart';

/// Signature of a webpage action handler: the CLI arguments plus the panel
/// whose WebView is being read or driven.
typedef _WebpageActionHandler =
    Future<CliActionResult> Function(
      Map<String, dynamic> args,
      BoardPanelInstance panel,
    );

/// CLI handler for Webpage/Browser panels (`board.webpage`).
class WebpageCliHandler extends PanelCliHandler {
  const WebpageCliHandler();

  @override
  String get typeId => 'board.webpage';

  @override
  List<String> get supportedActions => [
    'open',
    'get',
    'exec',
    'content',
    'title',
    'url',
    'scroll',
    'click',
  ];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {
      'url': panel.state['url'] ?? '',
      'title': panel.state['title'] ?? '',
      'favicon': panel.state['favicon'] ?? '',
      'hasLiveWebView': WebViewManager.instance.has(panel.id),
    };
  }

  Map<String, _WebpageActionHandler> get _actionHandlers => {
    'open': _handleOpen,
    'get': _handleGet,
    'exec': _handleExec,
    'content': _handleContent,
    'title': _handleTitle,
    'url': _handleUrl,
    'scroll': _handleScroll,
    'click': _handleClick,
  };

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final handler = _actionHandlers[action];
    if (handler == null) {
      return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
    return handler(args, panel);
  }

  Future<CliActionResult> _handleOpen(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final url = args['url'] as String?;
    if (url == null || url.isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'Missing "url" field',
      );
    }
    return CliActionResult(
      message: 'Opening $url',
      stateUpdate: {'url': url},
    );
  }

  Future<CliActionResult> _handleGet(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    return CliActionResult(data: getContent(panel));
  }

  Future<CliActionResult> _handleExec(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final js = args['js'] as String?;
    if (js == null || js.isEmpty) {
      return const CliActionResult(ok: false, message: 'Missing js parameter');
    }
    return _withWebView(panel.id, () async {
      final result = await WebViewManager.instance.runJavaScriptReturningResult(
        panel.id,
        js,
      );
      return CliActionResult(data: {'result': result?.toString()});
    });
  }

  Future<CliActionResult> _handleContent(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    return _withWebView(panel.id, () async {
      final html = await WebViewManager.instance.runJavaScriptReturningResult(
        panel.id,
        'document.documentElement.outerHTML',
      );
      return CliActionResult(data: {'html': html?.toString()});
    });
  }

  Future<CliActionResult> _handleTitle(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    return _withWebView(panel.id, () async {
      final title = await WebViewManager.instance.pageTitle(panel.id);
      return CliActionResult(data: {'title': title});
    });
  }

  Future<CliActionResult> _handleUrl(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    return _withWebView(panel.id, () async {
      final url = await WebViewManager.instance.currentUrl(panel.id);
      return CliActionResult(data: {'url': url});
    });
  }

  Future<CliActionResult> _handleScroll(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final x = _parseDouble(args['x']);
    final y = _parseDouble(args['y']);
    final by = args['by'] == true || args['mode']?.toString() == 'by';
    final fn = by ? 'scrollBy' : 'scrollTo';

    return _withWebView(panel.id, () async {
      await WebViewManager.instance.runJavaScript(
        panel.id,
        'window.$fn(${_formatNumber(x)}, ${_formatNumber(y)});',
      );
      return CliActionResult(
        message: by ? 'Scrolled by ($x, $y)' : 'Scrolled to ($x, $y)',
        data: {'x': x, 'y': y, 'by': by},
      );
    });
  }

  Future<CliActionResult> _handleClick(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final selector = args['selector'] as String?;
    if (selector == null || selector.isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'Missing selector parameter',
      );
    }

    return _withWebView(panel.id, () async {
      final clicked = await WebViewManager.instance
          .runJavaScriptReturningResult(panel.id, '''
(function() {
  const element = document.querySelector(${jsonEncode(selector)});
  if (!element) return false;
  element.click();
  return true;
})();
''');
      if (clicked != true && !_jsTruthy(clicked)) {
        return CliActionResult(
          ok: false,
          message: 'No element matched selector: $selector',
        );
      }
      return CliActionResult(
        message: 'Clicked $selector',
        data: {'selector': selector},
      );
    });
  }

  Future<CliActionResult> _withWebView(
    String panelId,
    Future<CliActionResult> Function() action,
  ) async {
    if (!WebViewManager.instance.has(panelId)) {
      return const CliActionResult(
        ok: false,
        message: 'WebView is not initialized for this panel',
      );
    }

    try {
      return await action();
    } catch (error) {
      return CliActionResult(
        ok: false,
        message: 'WebView action failed: $error',
      );
    }
  }

  double _parseDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  bool _jsTruthy(dynamic value) {
    if (value == true) return true;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'open': const CliActionHelp(
      description: 'Open a URL in the panel',
      params: {'url': 'URL to load'},
    ),
    'exec': const CliActionHelp(
      description: 'Execute JavaScript in the panel WebView',
      params: {'js': 'JavaScript source to execute'},
    ),
    'content': const CliActionHelp(description: 'Return the current page HTML'),
    'title': const CliActionHelp(description: 'Return the current page title'),
    'url': const CliActionHelp(
      description: 'Return the current live URL from the WebView',
    ),
    'scroll': const CliActionHelp(
      description: 'Scroll the page to or by coordinates',
      params: {
        'x': 'Horizontal offset (default: 0)',
        'y': 'Vertical offset (default: 0)',
        'by': 'Set true to use window.scrollBy instead of scrollTo',
      },
    ),
    'click': const CliActionHelp(
      description: 'Click the first element matching a CSS selector',
      params: {'selector': 'CSS selector to click'},
    ),
  };
}
