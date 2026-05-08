import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

class WebpagePlugin extends BoardPanelPlugin {
  const WebpagePlugin();

  static const String kTypeId = 'board.webpage';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Webpage';

  @override
  IconData get icon => Icons.language_outlined;

  @override
  Color get accentColor => const Color(0xFF0EA5E9);

  @override
  Size get defaultSize => const Size(360, 220);

  @override
  Map<String, dynamic> get initialState => {'url': '', 'title': '', 'favicon': ''};

  @override
  bool get hasEditor => false;

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _WebpageContent(panel: panel, renderContext: renderContext);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _WebpageContent extends StatefulWidget {
  const _WebpageContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_WebpageContent> createState() => _WebpageContentState();
}

class _WebpageContentState extends State<_WebpageContent> {
  static const Color _accent = Color(0xFF0EA5E9);

  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(
      text: widget.panel.state['url'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  String get _currentUrl => widget.panel.state['url'] as String? ?? '';

  String _hostname(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.isEmpty ? url : uri.host;
    } catch (_) {
      return url;
    }
  }

  String _normalizeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }

  void _commit() {
    final url = _normalizeUrl(_urlCtrl.text);
    _urlCtrl.text = url;
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'url': url,
      'title': url.isEmpty ? '' : _hostname(url),
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = _currentUrl;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // URL bar
          Row(
            children: [
              const Icon(Icons.link, size: 16, color: Color(0xFF0EA5E9)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _urlCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'https://example.com',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF0EA5E9)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF0EA5E9), width: 2),
                    ),
                  ),
                  onSubmitted: (_) => _commit(),
                ),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: _commit,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 36),
                ),
                child: const Text('Go', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Preview card
          if (url.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language, size: 40, color: _accent.withOpacity(0.4)),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter a URL above',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _accent.withOpacity(0.2)),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _accent.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.language, size: 20, color: Color(0xFF0EA5E9)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _hostname(url),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                url.length > 50 ? '${url.substring(0, 50)}…' : url,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => PlatformLauncher.instance.openUrl(url),
                        icon: const Icon(Icons.open_in_browser, size: 16),
                        label: const Text('Open in Browser'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
