import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:highlight/highlight_core.dart' show Mode;
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/swift.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:yoloit/core/services/git_service.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/editor/bloc/file_editor_state.dart';
import 'package:yoloit/features/editor/utils/file_type_utils.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_cubit.dart';
import 'package:yoloit/features/review/models/review_models.dart';

class FileEditorPanel extends StatefulWidget {
  const FileEditorPanel({
    super.key,
    this.immersive = false,
    this.hideTabBar = false,
    this.onToggleImmersive,
  });

  /// When true the tab bar and toggle bar are hidden so only raw content shows.
  final bool immersive;
  final bool hideTabBar;

  /// Called by buttons inside the panel to enter/exit immersive mode.
  final VoidCallback? onToggleImmersive;

  @override
  State<FileEditorPanel> createState() => _FileEditorPanelState();
}

class _FileEditorPanelState extends State<FileEditorPanel>
    with WidgetsBindingObserver {
  /// One CodeController per open file path.
  final Map<String, CodeController> _controllers = {};

  /// Tracks which content was last loaded into each controller (to avoid loops).
  final Map<String, String> _loadedContent = {};

  /// True when we're programmatically updating a controller (suppress auto-save).
  bool _suppressControllerUpdates = false;

  /// File paths currently showing Markdown/SVG preview instead of raw code.
  final Set<String> _previewPaths = {};

  /// Paths we have already auto-decided preview mode for (prevents repeated auto-toggle).
  final Set<String> _seenPaths = {};
  double _scaleBase = 13.0;
  final _fontSizeNotifier = ValueNotifier<double>(13.0);

  /// True after first frame renders for the current file (prevents toggle bar
  /// from appearing before CodeField has painted its content).
  bool _editorReady = false;
  String? _lastRenderedPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SessionPrefs.load().then((snap) {
      if (mounted) _fontSizeNotifier.value = snap.editorFontSize;
    });
    // Restore which files were in preview mode.
    SessionPrefs.loadPreviewPaths().then((saved) {
      if (mounted) setState(() => _previewPaths.addAll(saved));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _controllers.values) {
      c.dispose();
    }
    _fontSizeNotifier.dispose();
    super.dispose();
  }

  /// Reload active file from disk when app regains focus (external edits).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<FileEditorCubit>().reloadActiveIfUnchanged();
    }
  }

  static Mode? _modeFor(String path) {
    final lang = FileTypeUtils.languageFor(path);
    return switch (lang) {
      'dart' => dart,
      'javascript' => javascript,
      'typescript' => typescript,
      'python' => python,
      'java' => java,
      'kotlin' => kotlin,
      'go' => go,
      'rust' => rust,
      'bash' => bash,
      'cpp' => cpp,
      'css' => css,
      'json' => json,
      'yaml' => yaml,
      'xml' => xml,
      'sql' => sql,
      'markdown' =>
        null, // markdown has preview mode — skip slow syntax parsing
      'swift' => swift,
      _ => null,
    };
  }

  /// Returns the controller for [tab], creating it if needed.
  CodeController _controllerFor(EditorTab tab, BuildContext context) {
    if (!_controllers.containsKey(tab.filePath)) {
      final ctrl = CodeController(
        text: tab.content ?? '',
        language: _modeFor(tab.filePath),
      );
      _controllers[tab.filePath] = ctrl;
      _loadedContent[tab.filePath] = tab.content ?? '';
      ctrl.addListener(() {
        if (_suppressControllerUpdates) return;
        final text = ctrl.text;
        final cubit = context.read<FileEditorCubit>();
        final currentTab = cubit.state.activeTab;
        if (currentTab?.filePath == tab.filePath &&
            text != currentTab?.content) {
          cubit.updateContent(text);
        }
      });
    } else {
      // Sync content if it was updated externally — but ONLY with real content.
      final incoming = tab.content;
      if (incoming != null && _loadedContent[tab.filePath] != incoming) {
        _suppressControllerUpdates = true;
        _loadedContent[tab.filePath] = incoming;
        _controllers[tab.filePath]!.text = incoming;
        _suppressControllerUpdates = false;
      }
    }
    return _controllers[tab.filePath]!;
  }

  /// Dispose controllers for tabs that are no longer open.
  void _cleanupControllers(List<EditorTab> openTabs) {
    final openPaths = openTabs.map((t) => t.filePath).toSet();
    final toRemove = _controllers.keys
        .where((p) => !openPaths.contains(p))
        .toList();
    for (final path in toRemove) {
      _controllers.remove(path)?.dispose();
      _loadedContent.remove(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FileEditorCubit, FileEditorState>(
      builder: (context, state) {
        _cleanupControllers(state.tabs);

        if (!state.isOpen) return _emptyState(context);

        final activeTab = state.activeTab!;
        // Only create controller when content is available (not during loading).
        CodeController? controller;
        if (!activeTab.isDiff &&
            !_isImage(activeTab.filePath) &&
            !activeTab.isLoading) {
          controller = _controllerFor(activeTab, context);
        }

        // Wait one frame after switching files before showing the toggle bar —
        // this lets CodeField finish its initial paint before the overlay appears.
        if (activeTab.filePath != _lastRenderedPath) {
          _lastRenderedPath = activeTab.filePath;
          _editorReady = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _editorReady = true);
          });
          // Auto-default to preview for previewable files the first time they open.
          final path = activeTab.filePath;
          if (!_seenPaths.contains(path)) {
            _seenPaths.add(path);
            if (!_previewPaths.contains(path) &&
                (_isMarkdown(path) || _isSvg(path) || _isImage(path))) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _previewPaths.add(path));
                  SessionPrefs.savePreviewPaths(_previewPaths.toList());
                }
              });
            }
          }
        }

        final toggleVisible =
            _editorReady &&
            !activeTab.isDiff &&
            !activeTab.isLoading &&
            !_isImage(activeTab.filePath) &&
            (_isMarkdown(activeTab.filePath) || _isSvg(activeTab.filePath));

        final isVisualPreview =
            !activeTab.isLoading &&
            !activeTab.isDiff &&
            (_isImage(activeTab.filePath) ||
                _isSvg(activeTab.filePath) ||
                _isMarkdown(activeTab.filePath)) &&
            (_isImage(activeTab.filePath) ||
                _previewPaths.contains(activeTab.filePath));

        final immersive = widget.immersive;

        return GestureDetector(
          onScaleStart: (d) => _scaleBase = _fontSizeNotifier.value,
          onScaleUpdate: (d) {
            // Update ValueNotifier directly — no setState, no full rebuild
            final newSize = (_scaleBase * d.scale).clamp(8.0, 48.0);
            _fontSizeNotifier.value = newSize;
            SessionPrefs.saveEditorFontSize(newSize);
          },
          child: Column(
            children: [
              // Tab bar — hidden in immersive mode.
              if (!immersive && !widget.hideTabBar) _TabBar(state: state),
              Expanded(
                child: Stack(
                  children: [
                    // Main content — full height, never resizes
                    Positioned.fill(
                      child: activeTab.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : activeTab.error != null
                          ? _ErrorView(message: activeTab.error!)
                          : activeTab.isDiff
                          ? _DiffBody(tab: activeTab)
                          : _isImage(activeTab.filePath)
                          ? _ImagePreview(filePath: activeTab.filePath)
                          : _previewPaths.contains(activeTab.filePath)
                          ? (_isSvg(activeTab.filePath)
                                ? _SvgPreview(filePath: activeTab.filePath)
                                : _MarkdownPreview(
                                    content: activeTab.content ?? '',
                                  ))
                          : _EditorBody(
                              key: ValueKey(activeTab.filePath),
                              tab: activeTab,
                              codeController: controller!,
                              fontSizeNotifier: _fontSizeNotifier,
                            ),
                    ),
                    // Toggle bar: floats at top, fades in/out — hidden in immersive mode.
                    if (!immersive)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _AnimatedToggleBar(
                          visible: toggleVisible,
                          child: _MarkdownToggleBar(
                            isPreview: _previewPaths.contains(
                              activeTab.filePath,
                            ),
                            onToggle: () => setState(() {
                              final path = activeTab.filePath;
                              if (_previewPaths.contains(path)) {
                                _previewPaths.remove(path);
                              } else {
                                _previewPaths.add(path);
                              }
                              SessionPrefs.savePreviewPaths(
                                _previewPaths.toList(),
                              );
                            }),
                          ),
                        ),
                      ),
                    // Immersive-mode exit button (top-right corner).
                    if (immersive && widget.onToggleImmersive != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _ImmersiveButton(
                          icon: Icons.close_fullscreen_rounded,
                          tooltip: 'Exit focus mode',
                          onTap: widget.onToggleImmersive!,
                        ),
                      ),
                    // Enter-immersive button — shown when in a visual preview and not already immersive.
                    if (!immersive &&
                        isVisualPreview &&
                        widget.onToggleImmersive != null)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: _ImmersiveButton(
                          icon: Icons.open_in_full_rounded,
                          tooltip: 'Focus mode — hide chrome',
                          onTap: widget.onToggleImmersive!,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    final colors = context.appColors;
    return Container(
      color: colors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.code,
              size: 40,
              color: AppColors.textMuted.withAlpha(60),
            ),
            const SizedBox(height: 12),
            const Text(
              'Open a file to edit',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  static bool _isMarkdown(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return ext == 'md' || ext == 'mdx' || ext == 'markdown';
  }

  static bool _isImage(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return const {
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'bmp',
      'ico',
    }.contains(ext);
  }

  static bool _isSvg(String filePath) =>
      filePath.split('.').last.toLowerCase() == 'svg';
}

// ── Animated wrapper for the markdown toggle bar ───────────────────────────

class _AnimatedToggleBar extends StatefulWidget {
  const _AnimatedToggleBar({required this.visible, required this.child});
  final bool visible;
  final Widget child;

  @override
  State<_AnimatedToggleBar> createState() => _AnimatedToggleBarState();
}

class _AnimatedToggleBarState extends State<_AnimatedToggleBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: widget.visible ? 1.0 : 0.0,
    );
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void didUpdateWidget(_AnimatedToggleBar old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      if (widget.visible) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(position: _slideAnim, child: widget.child),
    );
  }
}

// ── Markdown toggle bar ────────────────────────────────────────────────────

class _MarkdownToggleBar extends StatelessWidget {
  const _MarkdownToggleBar({required this.isPreview, required this.onToggle});
  final bool isPreview;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          const Spacer(),
          _ModeButton(
            label: 'Code',
            icon: Icons.code,
            active: !isPreview,
            onTap: isPreview ? onToggle : null,
          ),
          const SizedBox(width: 6),
          _ModeButton(
            label: 'Preview',
            icon: Icons.visibility_outlined,
            active: isPreview,
            onTap: isPreview ? null : onToggle,
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.active,
    this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? colors.primary.withAlpha(40) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? colors.primary.withAlpha(100) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11,
              color: active ? colors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? colors.primary : AppColors.textMuted,
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Immersive mode toggle button ───────────────────────────────────────────

class _ImmersiveButton extends StatefulWidget {
  const _ImmersiveButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_ImmersiveButton> createState() => _ImmersiveButtonState();
}

class _ImmersiveButtonState extends State<_ImmersiveButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _hovered
                  ? const Color(0xFF1E2330)
                  : const Color(0xCC0B0D12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _hovered
                    ? const Color(0xFF60A5FA)
                    : const Color(0x4060A5FA),
              ),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _hovered
                  ? const Color(0xFF60A5FA)
                  : const Color(0x9060A5FA),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Markdown preview ───────────────────────────────────────────────────────

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({required this.content});
  final String content;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final sheet = MarkdownStyleSheet(
      h1: const TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.w700, height: 1.4),
      h2: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700, height: 1.4),
      h3: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600, height: 1.4),
      h4: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
      p: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.65),
      strong: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
      em: const TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
      code: TextStyle(color: AppColors.neonGreen, backgroundColor: AppColors.textMuted.withAlpha(30), fontSize: 13, fontFamily: 'monospace'),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF0D0D1F),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.textMuted.withAlpha(40)),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.primary, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
      blockquote: const TextStyle(color: AppColors.textMuted, fontSize: 14, fontStyle: FontStyle.italic),
      listBullet: const TextStyle(color: AppColors.textMuted, fontSize: 14),
      tableHead: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
      tableBody: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      tableBorder: TableBorder.all(color: AppColors.textMuted.withAlpha(40)),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.textMuted.withAlpha(60))),
      ),
      a: TextStyle(color: colors.primary, decoration: TextDecoration.underline),
    );
    // Use SingleChildScrollView + shrinkWrap so Markdown does NOT create its
    // own internal scroll. This keeps the coordinate system flat, which fixes
    // text selection hitting the wrong position when content is scrolled.
    return Container(
      color: colors.background,
      child: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Markdown(
            data: content,
            selectable: false,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            styleSheet: sheet,
          ),
        ),
      ),
    );
  }
}

// ── Image preview (raster only) ────────────────────────────────────────────

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.filePath});
  final String filePath;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final ext = filePath.split('.').last.toLowerCase();
    final fileName = filePath.split('/').last;

    return Container(
      color: colors.background,
      child: Column(
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.image_outlined,
                  size: 14,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  fileName,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  ext.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              minScale: 0.1,
              maxScale: 10,
              child: Center(
                child: Image.file(
                  File(filePath),
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text(
                      'Cannot load image',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── SVG preview (used by toggle, like Markdown preview) ────────────────────

class _SvgPreview extends StatelessWidget {
  const _SvgPreview({required this.filePath});
  final String filePath;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      color: colors.background,
      child: InteractiveViewer(
        minScale: 0.1,
        maxScale: 10,
        child: Center(
          child: SvgPicture.file(File(filePath), fit: BoxFit.contain),
        ),
      ),
    );
  }
}

// ── Tab bar ────────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  const _TabBar({required this.state});

  final FileEditorState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: const Color(0xFF32327A), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: state.tabs.length,
              itemBuilder: (context, i) => _Tab(
                tab: state.tabs[i],
                isActive: i == state.activeIndex,
                onTap: () => context.read<FileEditorCubit>().switchTab(i),
                onClose: () => context.read<FileEditorCubit>().closeTab(i),
                onCloseOthers: () =>
                    context.read<FileEditorCubit>().closeOthers(i),
                onPopOut: () => _popOutTab(context, state.tabs[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _popOutTab(BuildContext context, EditorTab tab) {
    final nodeId = 'panel:${tab.filePath.hashCode}';
    context.read<MindMapCubit>().openFileAsPanel(
      id: nodeId,
      filePath: tab.filePath,
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.tab,
    required this.isActive,
    required this.onTap,
    required this.onClose,
    this.onCloseOthers,
    this.onPopOut,
  });

  final EditorTab tab;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onCloseOthers;
  final VoidCallback? onPopOut;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  Future<void> _showTabMenu(BuildContext context, Offset globalPos) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy),
      color: const Color(0xFF12151C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF2A3040)),
      ),
      items: [
        const PopupMenuItem(
          value: 'close',
          child: Text('✕ Close',
              style: TextStyle(fontSize: 12, color: Color(0xFFCECEEE))),
        ),
        const PopupMenuItem(
          value: 'close_others',
          child: Text('✕ Close Others',
              style: TextStyle(fontSize: 12, color: Color(0xFFCECEEE))),
        ),
        if (widget.onPopOut != null)
          const PopupMenuItem(
            value: 'pop_out',
            child: Text('⬡ Open in Map panel',
                style: TextStyle(fontSize: 12, color: Color(0xFFCECEEE))),
          ),
      ],
    );
    if (result == null) return;
    switch (result) {
      case 'close':
        widget.onClose();
      case 'close_others':
        widget.onCloseOthers?.call();
      case 'pop_out':
        widget.onPopOut?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final fileInfo =
        widget.tab.isDiff ? null : FileTypeUtils.forPath(widget.tab.filePath);
    final displayName = widget.tab.isDiff
        ? '${widget.tab.filePath.replaceFirst('diff:', '').split('/').last} (diff)'
        : widget.tab.fileName;

    // Close button is placed OUTSIDE the tap-to-switch GestureDetector so
    // clicking × closes the tab instead of switching to it.
    return GestureDetector(
      onSecondaryTapDown: (d) => _showTabMenu(context, d.globalPosition),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: widget.onTap,
            child: Container(
              constraints:
                  const BoxConstraints(maxWidth: 170, minWidth: 60),
              padding: const EdgeInsets.only(left: 10, right: 4, top: 0, bottom: 0),
              decoration: BoxDecoration(
                color:
                    widget.isActive ? colors.background : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: widget.isActive
                        ? colors.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.tab.isDiff ? Icons.difference : fileInfo!.icon,
                    size: 12,
                    color: widget.tab.isDiff
                        ? AppColors.textMuted
                        : fileInfo!.color,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      displayName,
                      style: TextStyle(
                        color: widget.isActive
                            ? colors.primaryLight
                            : AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: widget.isActive
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // × button lives OUTSIDE the switch-tab detector so it always fires.
          _TabCloseButton(onClose: widget.onClose),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _TabCloseButton extends StatefulWidget {
  const _TabCloseButton({required this.onClose});

  final VoidCallback onClose;

  @override
  State<_TabCloseButton> createState() => _TabCloseButtonState();
}

class _TabCloseButtonState extends State<_TabCloseButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onClose,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: _hovering ? Colors.white.withAlpha(30) : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Icon(
            Icons.close,
            size: 11,
            color: _hovering ? AppColors.textPrimary : const Color(0xFFAAB0CC),
          ),
        ),
      ),
    );
  }
}

// ── Error view ──────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      color: colors.background,
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ── Editor body (StatefulWidget) ────────────────────────────────────────────

class _EditorBody extends StatefulWidget {
  const _EditorBody({
    super.key,
    required this.tab,
    required this.codeController,
    required this.fontSizeNotifier,
  });
  final EditorTab tab;
  final CodeController codeController;
  final ValueNotifier<double> fontSizeNotifier;
  @override
  State<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends State<_EditorBody> {
  // ── Find / Replace ──────────────────────────────────────────────────────
  bool _showFind = false;
  bool _showReplace = false;
  bool _caseSensitive = false;
  String _findQuery = '';
  List<int> _matchOffsets = [];
  int _currentMatch = 0;
  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  final _findFocus = FocusNode();

  // ── Editor options ───────────────────────────────────────────────────────
  bool _wordWrap = false;
  bool _showOutline = false;

  // ── Auto-pairs ───────────────────────────────────────────────────────────
  bool _suppressPairInsert = false;
  TextEditingValue? _lastValue;

  // ── Git gutter ───────────────────────────────────────────────────────────
  Map<int, _GutterMarkerType> _gitMarkers = {};
  double _codeScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    widget.codeController.addListener(_onTextChanged);
    _loadGitGutter();
  }

  @override
  void didUpdateWidget(_EditorBody old) {
    super.didUpdateWidget(old);
    if (old.tab.filePath != widget.tab.filePath) {
      _gitMarkers = {};
      _loadGitGutter();
    }
    if (old.codeController != widget.codeController) {
      old.codeController.removeListener(_onTextChanged);
      widget.codeController.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.codeController.removeListener(_onTextChanged);
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  // ── Auto-pairs ───────────────────────────────────────────────────────────

  void _onTextChanged() {
    if (_suppressPairInsert) return;
    final cur = widget.codeController.value;
    final prev = _lastValue;
    _lastValue = cur;

    if (prev == null) return;
    if (!cur.selection.isCollapsed) return;
    if (cur.text.length != prev.text.length + 1) return;

    final pos = cur.selection.baseOffset;
    if (pos < 1) return;
    final ch = cur.text[pos - 1];
    final closing = _closingBracket(ch);
    if (closing == null) return;

    // Don't double-close when next char is already the closer.
    final nextCh = pos < cur.text.length ? cur.text[pos] : '';
    if (nextCh == closing) return;

    _suppressPairInsert = true;
    try {
      final newText =
          cur.text.substring(0, pos) + closing + cur.text.substring(pos);
      widget.codeController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: pos),
      );
      _lastValue = widget.codeController.value;
    } finally {
      _suppressPairInsert = false;
    }
  }

  static String? _closingBracket(String ch) => switch (ch) {
    '(' => ')',
    '[' => ']',
    '{' => '}',
    _ => null,
  };

  // ── Git gutter ───────────────────────────────────────────────────────────

  Future<void> _loadGitGutter() async {
    final workspacePath = widget.tab.workspacePath;
    if (workspacePath == null || widget.tab.isDiff) return;
    try {
      final diff = await GitService.instance.getDiff(
        workspacePath,
        widget.tab.filePath,
      );
      if (mounted && diff.isNotEmpty) {
        setState(() => _gitMarkers = _parseDiffMarkers(diff));
      }
    } catch (_) {}
  }

  /// Parses unified diff output into a line-number → marker type map.
  static Map<int, _GutterMarkerType> _parseDiffMarkers(String diff) {
    final result = <int, _GutterMarkerType>{};
    int newLine = 0;

    for (final line in diff.split('\n')) {
      if (line.startsWith('@@')) {
        final match = RegExp(r'\+(\d+)').firstMatch(line);
        if (match != null) newLine = int.parse(match.group(1)!) - 1;
      } else if (line.startsWith('+') && !line.startsWith('+++')) {
        newLine++;
        result[newLine] = _GutterMarkerType.added;
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        // Removed line — mark the next new-file line as a deletion indicator.
        final nextLine = newLine + 1;
        if (!result.containsKey(nextLine)) {
          result[nextLine] = _GutterMarkerType.removed;
        }
      } else if (!line.startsWith('\\')) {
        newLine++;
      }
    }
    return result;
  }

  // ── Language helpers ────────────────────────────────────────────────────
  static String _languageName(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' => 'Dart',
      'js' => 'JavaScript',
      'ts' => 'TypeScript',
      'jsx' || 'tsx' => 'React',
      'py' => 'Python',
      'java' => 'Java',
      'kt' => 'Kotlin',
      'go' => 'Go',
      'rs' => 'Rust',
      'sh' || 'bash' => 'Shell',
      'cpp' || 'cc' || 'cxx' => 'C++',
      'c' => 'C',
      'css' => 'CSS',
      'json' => 'JSON',
      'yaml' || 'yml' => 'YAML',
      'xml' => 'XML',
      'sql' => 'SQL',
      'md' => 'Markdown',
      'swift' => 'Swift',
      'html' => 'HTML',
      _ => ext.isEmpty ? 'Plain Text' : ext.toUpperCase(),
    };
  }

  static String _commentPrefix(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return switch (ext) {
      'py' || 'rb' || 'sh' || 'bash' || 'yaml' || 'yml' || 'toml' => '# ',
      'css' => '/* ',
      _ => '// ',
    };
  }

  // ── Line helpers ────────────────────────────────────────────────────────
  ({int start, int end}) _lineRange(String text, int pos) {
    final s = pos == 0 ? 0 : text.lastIndexOf('\n', pos - 1) + 1;
    final rawEnd = text.indexOf('\n', pos);
    return (start: s, end: rawEnd == -1 ? text.length : rawEnd);
  }

  // ── Find & replace ──────────────────────────────────────────────────────
  void _openFind() => setState(() {
    _showFind = true;
    _showReplace = false;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocus.requestFocus();
    });
  });
  void _openReplace() => setState(() {
    _showFind = true;
    _showReplace = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocus.requestFocus();
    });
  });
  void _closeFind() => setState(() {
    _showFind = false;
    _showReplace = false;
  });

  void _updateMatches() {
    if (_findQuery.isEmpty) {
      _matchOffsets = [];
      _currentMatch = 0;
      return;
    }
    final text = widget.codeController.text;
    final q = _caseSensitive ? _findQuery : _findQuery.toLowerCase();
    final src = _caseSensitive ? text : text.toLowerCase();
    final offsets = <int>[];
    int start = 0;
    while (true) {
      final idx = src.indexOf(q, start);
      if (idx == -1) break;
      offsets.add(idx);
      start = idx + 1;
    }
    _matchOffsets = offsets;
    if (_currentMatch >= offsets.length) _currentMatch = 0;
  }

  void _selectCurrentMatch() {
    if (_matchOffsets.isEmpty) return;
    final off = _matchOffsets[_currentMatch];
    widget.codeController.selection = TextSelection(
      baseOffset: off,
      extentOffset: off + _findQuery.length,
    );
  }

  void _findNext() {
    if (_matchOffsets.isEmpty) return;
    setState(() => _currentMatch = (_currentMatch + 1) % _matchOffsets.length);
    _selectCurrentMatch();
  }

  void _findPrev() {
    if (_matchOffsets.isEmpty) return;
    setState(
      () => _currentMatch =
          (_currentMatch - 1 + _matchOffsets.length) % _matchOffsets.length,
    );
    _selectCurrentMatch();
  }

  void _replaceOne() {
    if (_matchOffsets.isEmpty) return;
    final ctrl = widget.codeController;
    final off = _matchOffsets[_currentMatch];
    final text = ctrl.text;
    final newText =
        text.substring(0, off) +
        _replaceCtrl.text +
        text.substring(off + _findQuery.length);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: off + _replaceCtrl.text.length,
      ),
    );
    _updateMatches();
    setState(() {});
  }

  void _replaceAll() {
    if (_findQuery.isEmpty) return;
    final ctrl = widget.codeController;
    final newText = ctrl.text.replaceAll(
      _caseSensitive
          ? _findQuery
          : RegExp(RegExp.escape(_findQuery), caseSensitive: false),
      _replaceCtrl.text,
    );
    ctrl.value = TextEditingValue(
      text: newText,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _updateMatches();
    setState(() {});
  }

  // ── Text editing helpers ────────────────────────────────────────────────
  void _toggleComment() {
    final ctrl = widget.codeController;
    final text = ctrl.text;
    final sel = ctrl.selection;
    final r = _lineRange(text, sel.start);
    final lineContent = text.substring(r.start, r.end);
    final prefix = _commentPrefix(widget.tab.filePath);
    final trimmed = lineContent.trimLeft();
    final indent = lineContent.length - trimmed.length;
    String newLine;
    int delta;
    if (trimmed.startsWith(prefix)) {
      newLine =
          lineContent.substring(0, indent) + trimmed.substring(prefix.length);
      delta = -prefix.length;
    } else {
      newLine = lineContent.substring(0, indent) + prefix + trimmed;
      delta = prefix.length;
    }
    final newText =
        text.substring(0, r.start) + newLine + text.substring(r.end);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: (sel.start + delta).clamp(r.start, r.start + newLine.length),
      ),
    );
  }

  void _duplicateLine() {
    final ctrl = widget.codeController;
    final text = ctrl.text;
    final r = _lineRange(text, ctrl.selection.start);
    final lineContent = text.substring(r.start, r.end);
    final newText =
        '${text.substring(0, r.end)}\n$lineContent${text.substring(r.end)}';
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: r.end + 1 + (ctrl.selection.start - r.start),
      ),
    );
  }

  void _deleteLine() {
    final ctrl = widget.codeController;
    final text = ctrl.text;
    final r = _lineRange(text, ctrl.selection.start);
    String newText;
    int newCursor;
    if (r.end < text.length) {
      newText = text.substring(0, r.start) + text.substring(r.end + 1);
      newCursor = r.start;
    } else if (r.start > 0) {
      newText = text.substring(0, r.start - 1);
      newCursor = r.start - 1;
    } else {
      return;
    }
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: newCursor.clamp(0, newText.length),
      ),
    );
  }

  void _moveLineUp() {
    final ctrl = widget.codeController;
    final text = ctrl.text;
    final r = _lineRange(text, ctrl.selection.start);
    if (r.start == 0) return;
    final prev = _lineRange(text, r.start - 1);
    final cur = text.substring(r.start, r.end);
    final above = text.substring(prev.start, prev.end);
    final before = text.substring(0, prev.start);
    final after = r.end < text.length ? text.substring(r.end) : '';
    final newText = '$before$cur\n$above$after';
    final off = ctrl.selection.start - r.start;
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: prev.start + off.clamp(0, cur.length),
      ),
    );
  }

  void _moveLineDown() {
    final ctrl = widget.codeController;
    final text = ctrl.text;
    final r = _lineRange(text, ctrl.selection.start);
    if (r.end >= text.length) return;
    final next = _lineRange(text, r.end + 1);
    final cur = text.substring(r.start, r.end);
    final below = text.substring(next.start, next.end);
    final before = text.substring(0, r.start);
    final after = next.end < text.length ? text.substring(next.end) : '';
    final newText = '$before$below\n$cur$after';
    final off = ctrl.selection.start - r.start;
    final newLineStart = r.start + below.length + 1;
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: newLineStart + off.clamp(0, cur.length),
      ),
    );
  }

  void _indentLine() {
    final ctrl = widget.codeController;
    final text = ctrl.text;
    final r = _lineRange(text, ctrl.selection.start);
    const sp = '  ';
    ctrl.value = TextEditingValue(
      text: text.substring(0, r.start) + sp + text.substring(r.start),
      selection: TextSelection.collapsed(
        offset: ctrl.selection.start + sp.length,
      ),
    );
  }

  void _outdentLine() {
    final ctrl = widget.codeController;
    final text = ctrl.text;
    final r = _lineRange(text, ctrl.selection.start);
    final line = text.substring(r.start, r.end);
    final strip = line.startsWith('  ')
        ? 2
        : line.startsWith(' ')
        ? 1
        : 0;
    if (strip == 0) return;
    ctrl.value = TextEditingValue(
      text:
          text.substring(0, r.start) +
          line.substring(strip) +
          text.substring(r.end),
      selection: TextSelection.collapsed(
        offset: (ctrl.selection.start - strip).clamp(
          r.start,
          text.length - strip,
        ),
      ),
    );
  }

  // ── Format document ─────────────────────────────────────────────────────
  Future<void> _formatDocument() async {
    final path = widget.tab.filePath;
    if (!path.endsWith('.dart')) return;
    try {
      final result = await Process.run('dart', ['format', '--fix', path]);
      if (result.exitCode == 0 && mounted) {
        final newContent = await File(path).readAsString();
        widget.codeController.value = TextEditingValue(
          text: newContent,
          selection: const TextSelection.collapsed(offset: 0),
        );
        if (mounted) context.read<FileEditorCubit>().updateContent(newContent);
      }
    } catch (_) {}
  }

  // ── Go to line ──────────────────────────────────────────────────────────
  Future<void> _showGoToLine(BuildContext ctx) async {
    final ctrl = widget.codeController;
    final lineCount = '\n'.allMatches(ctrl.text).length + 1;
    final inputCtrl = TextEditingController();
    await showDialog<void>(
      context: ctx,
      barrierColor: Colors.black54,
      builder: (dctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Go to Line',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: inputCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: '1 – $lineCount',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  border: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF2A2A4E)),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF2A2A4E)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF7C3AED)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                onSubmitted: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n >= 1 && n <= lineCount)
                    _jumpToLine(ctrl, n);
                  Navigator.of(dctx).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
    inputCtrl.dispose();
  }

  void _jumpToLine(CodeController ctrl, int lineNumber) {
    final lines = ctrl.text.split('\n');
    int offset = 0;
    for (int i = 0; i < lineNumber - 1 && i < lines.length; i++) {
      offset += lines[i].length + 1;
    }
    ctrl.selection = TextSelection.collapsed(
      offset: offset.clamp(0, ctrl.text.length),
    );
  }

  // ── Outline toggle ──────────────────────────────────────────────────────
  void _toggleOutline() => setState(() => _showOutline = !_showOutline);

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final language = _languageName(widget.tab.filePath);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        const SingleActivator(LogicalKeyboardKey.keyH, meta: true):
            _openReplace,
        const SingleActivator(LogicalKeyboardKey.slash, meta: true):
            _toggleComment,
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
            _duplicateLine,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true, shift: true):
            _deleteLine,
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
            _moveLineUp,
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
            _moveLineDown,
        const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true):
            _indentLine,
        const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
            _outdentLine,
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () =>
            _showGoToLine(context),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
            _formatDocument,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true, shift: true):
            _toggleOutline,
        const SingleActivator(LogicalKeyboardKey.escape): _closeFind,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            _EditorToolbar(
              language: language,
              wordWrap: _wordWrap,
              showOutline: _showOutline,
              onToggleWordWrap: () => setState(() => _wordWrap = !_wordWrap),
              onFormat: _formatDocument,
              onToggleOutline: _toggleOutline,
              onGoToLine: () => _showGoToLine(context),
              onOpenFind: _openFind,
            ),
            if (_showFind)
              _FindBar(
                findCtrl: _findCtrl,
                replaceCtrl: _replaceCtrl,
                findFocus: _findFocus,
                showReplace: _showReplace,
                caseSensitive: _caseSensitive,
                matchCount: _matchOffsets.length,
                currentMatch: _currentMatch,
                onClose: _closeFind,
                onNext: _findNext,
                onPrev: _findPrev,
                onReplace: _replaceOne,
                onReplaceAll: _replaceAll,
                onToggleCase: () {
                  setState(() => _caseSensitive = !_caseSensitive);
                  _updateMatches();
                  setState(() {});
                },
                onToggleReplace: () =>
                    setState(() => _showReplace = !_showReplace),
                onQueryChanged: (q) {
                  setState(() {
                    _findQuery = q;
                    _updateMatches();
                  });
                },
              ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: ValueListenableBuilder<double>(
                            valueListenable: widget.fontSizeNotifier,
                            builder: (context, fontSize, _) {
                              final lineHeight = fontSize * 1.5;
                              return NotificationListener<ScrollNotification>(
                                onNotification: (n) {
                                  if (n.metrics.axis == Axis.vertical) {
                                    setState(
                                      () =>
                                          _codeScrollOffset = n.metrics.pixels,
                                    );
                                  }
                                  return false;
                                },
                                child: Stack(
                                  children: [
                                    CodeTheme(
                                      data: CodeThemeData(styles: _darkTheme),
                                      child: CodeField(
                                        controller: widget.codeController,
                                        expands: true,
                                        wrap: _wordWrap,
                                        textStyle: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: fontSize,
                                          height: 1.5,
                                        ),
                                        background: colors.background,
                                        gutterStyle: GutterStyle(
                                          width: 72,
                                          margin: 8,
                                          textStyle: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontFamily: 'monospace',
                                          ),
                                          background: colors.surfaceElevated,
                                        ),
                                      ),
                                    ),
                                    // Git gutter overlay — 3px strip at left edge of gutter.
                                    if (_gitMarkers.isNotEmpty)
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        width: 3,
                                        child: _GitGutterPainter(
                                          markers: _gitMarkers,
                                          lineHeight: lineHeight,
                                          scrollOffset: _codeScrollOffset,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        _EditorStatusBar(
                          controller: widget.codeController,
                          language: language,
                        ),
                      ],
                    ),
                  ),
                  if (_showOutline)
                    _SymbolOutline(
                      content: widget.codeController.text,
                      filePath: widget.tab.filePath,
                      onJumpToLine: (line) =>
                          _jumpToLine(widget.codeController, line),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const Map<String, TextStyle> _darkTheme = {
    'root': TextStyle(
      color: Color(0xFFABB2BF),
      backgroundColor: Colors.transparent,
    ),
    'comment': TextStyle(color: Color(0xFF5C6370), fontStyle: FontStyle.italic),
    'keyword': TextStyle(color: Color(0xFFC678DD)),
    'built_in': TextStyle(color: Color(0xFFE5C07B)),
    'type': TextStyle(color: Color(0xFFE5C07B)),
    'literal': TextStyle(color: Color(0xFF56B6C2)),
    'number': TextStyle(color: Color(0xFFD19A66)),
    'regexp': TextStyle(color: Color(0xFF98C379)),
    'string': TextStyle(color: Color(0xFF98C379)),
    'subst': TextStyle(color: Color(0xFFABB2BF)),
    'symbol': TextStyle(color: Color(0xFF61AFEF)),
    'class': TextStyle(color: Color(0xFFE5C07B)),
    'function': TextStyle(color: Color(0xFF61AFEF)),
    'title': TextStyle(color: Color(0xFF61AFEF)),
    'params': TextStyle(color: Color(0xFFABB2BF)),
    'formula': TextStyle(color: Color(0xFF98C379)),
    'comment-doc': TextStyle(
      color: Color(0xFF5C6370),
      fontStyle: FontStyle.italic,
    ),
    'meta': TextStyle(color: Color(0xFF56B6C2)),
    'tag': TextStyle(color: Color(0xFFE06C75)),
    'name': TextStyle(color: Color(0xFFE06C75)),
    'attr': TextStyle(color: Color(0xFFD19A66)),
    'attribute': TextStyle(color: Color(0xFFD19A66)),
    'variable': TextStyle(color: Color(0xFFE06C75)),
    'bullet': TextStyle(color: Color(0xFF61AFEF)),
    'code': TextStyle(color: Color(0xFF98C379)),
    'emphasis': TextStyle(fontStyle: FontStyle.italic),
    'strong': TextStyle(fontWeight: FontWeight.bold),
    'link': TextStyle(
      color: Color(0xFF56B6C2),
      decoration: TextDecoration.underline,
    ),
    'section': TextStyle(color: Color(0xFFE06C75), fontWeight: FontWeight.bold),
    'selector-tag': TextStyle(color: Color(0xFFE06C75)),
    'selector-id': TextStyle(color: Color(0xFF61AFEF)),
    'selector-class': TextStyle(color: Color(0xFFD19A66)),
    'addition': TextStyle(color: Color(0xFF98C379)),
    'deletion': TextStyle(color: Color(0xFFE06C75)),
  };
}

// ── Git gutter types & painter ────────────────────────────────────────────────

enum _GutterMarkerType { added, removed }

class _GitGutterPainter extends StatelessWidget {
  const _GitGutterPainter({
    required this.markers,
    required this.lineHeight,
    required this.scrollOffset,
  });

  final Map<int, _GutterMarkerType> markers;
  final double lineHeight;
  final double scrollOffset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) => CustomPaint(
        size: Size(3, constraints.maxHeight),
        painter: _GutterPaint(
          markers: markers,
          lineHeight: lineHeight,
          scrollOffset: scrollOffset,
        ),
      ),
    );
  }
}

class _GutterPaint extends CustomPainter {
  const _GutterPaint({
    required this.markers,
    required this.lineHeight,
    required this.scrollOffset,
  });

  final Map<int, _GutterMarkerType> markers;
  final double lineHeight;
  final double scrollOffset;

  static const _added = Color(0xFF00FF9F); // neon green
  static const _removed = Color(0xFFFF4F6A); // neon red

  @override
  void paint(Canvas canvas, Size size) {
    final addedPaint = Paint()..color = _added;
    final removedPaint = Paint()..color = _removed;

    for (final entry in markers.entries) {
      final lineIndex = entry.key - 1; // 0-indexed
      final top = lineIndex * lineHeight - scrollOffset;
      final bottom = top + lineHeight;
      if (bottom < 0 || top > size.height) continue;
      canvas.drawRect(
        Rect.fromLTRB(
          0,
          top.clamp(0, size.height),
          3,
          bottom.clamp(0, size.height),
        ),
        entry.value == _GutterMarkerType.added ? addedPaint : removedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GutterPaint old) =>
      old.scrollOffset != scrollOffset ||
      old.markers != markers ||
      old.lineHeight != lineHeight;
}

// ── Editor toolbar ───────────────────────────────────────────────────────────

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.language,
    required this.wordWrap,
    required this.showOutline,
    required this.onToggleWordWrap,
    required this.onFormat,
    required this.onToggleOutline,
    required this.onGoToLine,
    required this.onOpenFind,
  });
  final String language;
  final bool wordWrap;
  final bool showOutline;
  final VoidCallback onToggleWordWrap;
  final VoidCallback onFormat;
  final VoidCallback onToggleOutline;
  final VoidCallback onGoToLine;
  final VoidCallback onOpenFind;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          _ToolbarBtn(
            icon: Icons.search,
            tooltip: 'Find  ⌘F',
            onTap: onOpenFind,
          ),
          _ToolbarBtn(
            icon: Icons.wrap_text,
            tooltip: 'Word Wrap',
            active: wordWrap,
            onTap: onToggleWordWrap,
          ),
          _ToolbarBtn(
            icon: Icons.auto_fix_high,
            tooltip: 'Format  ⌘⇧F',
            onTap: onFormat,
          ),
          _ToolbarBtn(
            icon: Icons.last_page,
            tooltip: 'Go to Line  ⌘G',
            onTap: onGoToLine,
          ),
          _ToolbarBtn(
            icon: Icons.account_tree_outlined,
            tooltip: 'Outline  ⌘⇧O',
            active: showOutline,
            onTap: onToggleOutline,
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              language,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarBtn extends StatelessWidget {
  const _ToolbarBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          color: active ? colors.primary.withAlpha(40) : Colors.transparent,
          child: Icon(
            icon,
            size: 14,
            color: active ? colors.primaryLight : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

// ── Find / Replace bar ───────────────────────────────────────────────────────

class _FindBar extends StatelessWidget {
  const _FindBar({
    required this.findCtrl,
    required this.replaceCtrl,
    required this.findFocus,
    required this.showReplace,
    required this.caseSensitive,
    required this.matchCount,
    required this.currentMatch,
    required this.onClose,
    required this.onNext,
    required this.onPrev,
    required this.onReplace,
    required this.onReplaceAll,
    required this.onToggleCase,
    required this.onToggleReplace,
    required this.onQueryChanged,
  });
  final TextEditingController findCtrl;
  final TextEditingController replaceCtrl;
  final FocusNode findFocus;
  final bool showReplace;
  final bool caseSensitive;
  final int matchCount;
  final int currentMatch;
  final VoidCallback onClose;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onReplace;
  final VoidCallback onReplaceAll;
  final VoidCallback onToggleCase;
  final VoidCallback onToggleReplace;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasQuery = findCtrl.text.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.search, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              SizedBox(
                width: 220,
                height: 24,
                child: TextField(
                  controller: findCtrl,
                  focusNode: findFocus,
                  onChanged: onQueryChanged,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Find',
                    hintStyle: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (hasQuery && matchCount > 0)
                Text(
                  '${currentMatch + 1} / $matchCount',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              if (hasQuery && matchCount == 0)
                const Text(
                  'No results',
                  style: TextStyle(color: Colors.redAccent, fontSize: 10),
                ),
              const SizedBox(width: 4),
              _FBBtn(
                icon: Icons.text_fields,
                tooltip: 'Case sensitive',
                active: caseSensitive,
                onTap: onToggleCase,
              ),
              _FBBtn(
                icon: Icons.keyboard_arrow_up,
                tooltip: 'Previous  ⇧Enter',
                onTap: onPrev,
              ),
              _FBBtn(
                icon: Icons.keyboard_arrow_down,
                tooltip: 'Next  Enter',
                onTap: onNext,
              ),
              _FBBtn(
                icon: Icons.find_replace,
                tooltip: 'Toggle Replace  ⌘H',
                active: showReplace,
                onTap: onToggleReplace,
              ),
              const Spacer(),
              _FBBtn(icon: Icons.close, tooltip: 'Close  Esc', onTap: onClose),
            ],
          ),
          if (showReplace) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.edit, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
                SizedBox(
                  width: 220,
                  height: 24,
                  child: TextField(
                    controller: replaceCtrl,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Replace',
                      hintStyle: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _TextBtn(label: 'Replace', onTap: onReplace),
                const SizedBox(width: 4),
                _TextBtn(label: 'All', onTap: onReplaceAll),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FBBtn extends StatelessWidget {
  const _FBBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: active ? colors.primary.withAlpha(60) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 13,
            color: active ? colors.primaryLight : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _TextBtn extends StatelessWidget {
  const _TextBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
      ),
    );
  }
}

// ── Editor status bar ────────────────────────────────────────────────────────

class _EditorStatusBar extends StatefulWidget {
  const _EditorStatusBar({required this.controller, required this.language});
  final CodeController controller;
  final String language;

  @override
  State<_EditorStatusBar> createState() => _EditorStatusBarState();
}

class _EditorStatusBarState extends State<_EditorStatusBar> {
  int _line = 1;
  int _col = 1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    final text = widget.controller.text;
    final offset = widget.controller.selection.baseOffset;
    if (offset < 0 || offset > text.length) return;
    final before = text.substring(0, offset);
    final lines = before.split('\n');
    final l = lines.length;
    final c = lines.last.length + 1;
    if (l != _line || c != _col)
      setState(() {
        _line = l;
        _col = c;
      });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: 22,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          Text(
            'Ln $_line, Col $_col',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
          _SBar(),
          const Text(
            'UTF-8',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
          _SBar(),
          const Text(
            'LF',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
          _SBar(),
          Text(
            widget.language,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _SBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF2A2A4E),
    );
  }
}

// ── Symbol outline ───────────────────────────────────────────────────────────

class _OutlineSymbol {
  const _OutlineSymbol({
    required this.name,
    required this.line,
    required this.isClass,
  });
  final String name;
  final int line;
  final bool isClass;
}

List<_OutlineSymbol> _parseSymbols(String content, String filePath) {
  final ext = filePath.split('.').last.toLowerCase();
  final lines = content.split('\n');
  final symbols = <_OutlineSymbol>[];
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final t = line.trim();
    switch (ext) {
      case 'dart':
        if (RegExp(
          r'^(abstract\s+)?(?:class|enum|mixin|extension)\s+\w+',
        ).hasMatch(t)) {
          final m = RegExp(
            r'(?:class|enum|mixin|extension)\s+(\w+)',
          ).firstMatch(t);
          if (m != null)
            symbols.add(
              _OutlineSymbol(name: m.group(1)!, line: i + 1, isClass: true),
            );
        } else {
          final m = RegExp(
            r'(?:Future(?:<[^>]*>)?|Widget|void|String|int|bool|double|List|Map|dynamic)\s+(\w+)\s*[\(<]',
          ).firstMatch(line);
          if (m != null &&
              ![
                'if',
                'for',
                'while',
                'switch',
                'return',
              ].contains(m.group(1))) {
            symbols.add(
              _OutlineSymbol(
                name: '${m.group(1)!}()',
                line: i + 1,
                isClass: false,
              ),
            );
          }
        }
      case 'js' || 'ts' || 'jsx' || 'tsx':
        if (t.startsWith('class ')) {
          final m = RegExp(r'class\s+(\w+)').firstMatch(t);
          if (m != null)
            symbols.add(
              _OutlineSymbol(name: m.group(1)!, line: i + 1, isClass: true),
            );
        } else if (RegExp(
          r'^(?:export\s+)?(?:async\s+)?function\s+\w+',
        ).hasMatch(t)) {
          final m = RegExp(r'function\s+(\w+)').firstMatch(t);
          if (m != null)
            symbols.add(
              _OutlineSymbol(
                name: '${m.group(1)!}()',
                line: i + 1,
                isClass: false,
              ),
            );
        } else if (RegExp(
          r'^(?:const|let|var)\s+\w+\s*=\s*(?:async\s+)?\(',
        ).hasMatch(t)) {
          final m = RegExp(r'(?:const|let|var)\s+(\w+)').firstMatch(t);
          if (m != null)
            symbols.add(
              _OutlineSymbol(
                name: '${m.group(1)!}()',
                line: i + 1,
                isClass: false,
              ),
            );
        }
      case 'py':
        if (t.startsWith('class ')) {
          final m = RegExp(r'class\s+(\w+)').firstMatch(t);
          if (m != null)
            symbols.add(
              _OutlineSymbol(name: m.group(1)!, line: i + 1, isClass: true),
            );
        } else if (t.startsWith('def ') || t.startsWith('async def ')) {
          final m = RegExp(r'def\s+(\w+)').firstMatch(t);
          if (m != null)
            symbols.add(
              _OutlineSymbol(
                name: '${m.group(1)!}()',
                line: i + 1,
                isClass: false,
              ),
            );
        }
    }
  }
  return symbols;
}

class _SymbolOutline extends StatelessWidget {
  const _SymbolOutline({
    required this.content,
    required this.filePath,
    required this.onJumpToLine,
  });
  final String content;
  final String filePath;
  final void Function(int line) onJumpToLine;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final symbols = _parseSymbols(content, filePath);
    return Container(
      width: 185,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Outline',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            child: symbols.isEmpty
                ? const Center(
                    child: Text(
                      'No symbols',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: symbols.length,
                    itemBuilder: (_, i) {
                      final sym = symbols[i];
                      return InkWell(
                        onTap: () => onJumpToLine(sym.line),
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: sym.isClass ? 8 : 20,
                            right: 8,
                            top: 3,
                            bottom: 3,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                sym.isClass
                                    ? Icons.category_outlined
                                    : Icons.functions,
                                size: 11,
                                color: sym.isClass
                                    ? const Color(0xFFE5C07B)
                                    : const Color(0xFF61AFEF),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  sym.name,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${sym.line}',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DiffBody extends StatelessWidget {
  const _DiffBody({required this.tab});
  final EditorTab tab;

  @override
  Widget build(BuildContext context) {
    final hunks = tab.diffHunks!;
    if (hunks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.difference_outlined,
              size: 32,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            const Text(
              'No diff available',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tab.filePath.replaceFirst('diff:', ''),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: hunks.length,
      itemBuilder: (context, i) => _DiffHunkWidget(hunk: hunks[i]),
    );
  }
}

class _DiffHunkWidget extends StatelessWidget {
  const _DiffHunkWidget({required this.hunk});
  final DiffHunk hunk;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(3),
                topRight: Radius.circular(3),
              ),
            ),
            child: Text(
              hunk.header,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
          ...hunk.lines
              .where((l) => l.type != DiffLineType.header)
              .map((line) => _DiffLineWidget(line: line)),
        ],
      ),
    );
  }
}

class _DiffLineWidget extends StatelessWidget {
  const _DiffLineWidget({required this.line});
  final DiffLine line;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color textColor;
    String prefix;

    switch (line.type) {
      case DiffLineType.add:
        bg = AppColors.diffAddBg;
        textColor = AppColors.diffAddText;
        prefix = '+';
      case DiffLineType.remove:
        bg = AppColors.diffRemoveBg;
        textColor = AppColors.diffRemoveText;
        prefix = '-';
      default:
        bg = Colors.transparent;
        textColor = AppColors.textSecondary;
        prefix = ' ';
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${line.oldLineNum ?? ""}',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text(
              '${line.newLineNum ?? ""}',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            prefix,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              line.content,
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
