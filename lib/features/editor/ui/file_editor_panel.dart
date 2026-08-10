import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
// ignore: implementation_imports
import 'package:flutter_code_editor/src/search/match.dart';
// ignore: implementation_imports
import 'package:flutter_code_editor/src/search/result.dart';
// ignore: implementation_imports
import 'package:flutter_code_editor/src/search/search_navigation_state.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:highlight/highlight_core.dart' show Mode;
import 'package:yoloit/core/services/git_service.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/editor/bloc/file_editor_state.dart';
import 'package:yoloit/features/editor/ui/widgets/search_replace_bar.dart';
import 'package:yoloit/features/editor/utils/editor_language_registry.dart';
import 'package:yoloit/features/editor/utils/editor_panel_logic.dart';
import 'package:yoloit/features/editor/utils/file_type_utils.dart';
import 'package:yoloit/features/preview/widgets/markdown_document_preview.dart';
import 'package:yoloit/features/review/models/review_models.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

/// Test seam for [FileEditorPanel]'s format action — spawns `dart format`.
/// Matches the repo's `ProcessRunner` idiom and is replaced by a fake in tests.
@visibleForTesting
Future<ProcessResult> Function(String executable, List<String> arguments)
formatDocumentProcessRunner = Process.run;

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
    final spec = EditorLanguageRegistry.forPath(path);
    if (spec.id == 'markdown') return null;
    return spec.mode;
  }

  /// Returns the controller for [tab], creating it if needed.
  CodeController _controllerFor(EditorTab tab, BuildContext context) {
    if (!_controllers.containsKey(tab.filePath)) {
      final large = isLargeEditorFile(tab.content);
      final ctrl = CodeController(
        text: tab.content ?? '',
        // Disable syntax highlighting for large files — the highlight package
        // tokenizes the entire file eagerly and freezes the UI on open.
        language: large ? null : _modeFor(tab.filePath),
      );
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
      _controllers[tab.filePath] = ctrl;
      _loadedContent[tab.filePath] = tab.content ?? '';
      ctrl.addListener(() {
        if (_suppressControllerUpdates) return;
        final text = ctrl.text;
        final cubit = context.read<FileEditorCubit>();
        final currentTab = cubit.state.activeTab;
        if (currentTab?.filePath == tab.filePath &&
            text != currentTab?.content) {
          _loadedContent[tab.filePath] = text;
          cubit.updateContent(text);
        }
      });
    } else {
      // Sync content if it was updated externally — but ONLY with real content.
      final incoming = tab.content;
      if (incoming != null && _loadedContent[tab.filePath] != incoming) {
        final controller = _controllers[tab.filePath]!;
        final oldSelection = controller.selection;
        final preservedSelection = TextSelection(
          baseOffset: oldSelection.baseOffset.clamp(0, incoming.length),
          extentOffset: oldSelection.extentOffset.clamp(0, incoming.length),
          affinity: oldSelection.affinity,
          isDirectional: oldSelection.isDirectional,
        );
        _suppressControllerUpdates = true;
        _loadedContent[tab.filePath] = incoming;
        controller.value = TextEditingValue(
          text: incoming,
          selection: preservedSelection,
          composing: TextRange.empty,
        );
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
        final controller = _activeController(activeTab, context);
        _syncPathChange(activeTab);

        final toggleVisible = _toggleVisibleFor(activeTab);
        final isVisualPreview = _isVisualPreviewFor(activeTab);

        final body = _buildBody(
          state,
          controller,
          toggleVisible,
          isVisualPreview,
        );
        if (isVisualPreview) return body;
        return _wrapScaleGestures(body);
      },
    );
  }

  /// Only create controller when content is available (not during loading).
  CodeController? _activeController(EditorTab activeTab, BuildContext context) {
    if (!activeTab.isDiff &&
        !isEditorImagePath(activeTab.filePath) &&
        !activeTab.isLoading) {
      return _controllerFor(activeTab, context);
    }
    return null;
  }

  /// Wait one frame after switching files before showing the toggle bar —
  /// this lets CodeField finish its initial paint before the overlay appears.
  void _syncPathChange(EditorTab activeTab) {
    if (activeTab.filePath == _lastRenderedPath) return;
    _lastRenderedPath = activeTab.filePath;
    _editorReady = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _editorReady = true);
    });
    // Auto-default to preview for previewable files the first time they open.
    final path = activeTab.filePath;
    if (_seenPaths.contains(path)) return;
    _seenPaths.add(path);
    if (!_previewPaths.contains(path) &&
        (isMarkdownPath(path) || isSvgPath(path) || isEditorImagePath(path))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _previewPaths.add(path));
          SessionPrefs.savePreviewPaths(_previewPaths.toList());
        }
      });
    }
  }

  bool _toggleVisibleFor(EditorTab activeTab) {
    return _editorReady &&
        !activeTab.isDiff &&
        !activeTab.isLoading &&
        !isEditorImagePath(activeTab.filePath) &&
        (isMarkdownPath(activeTab.filePath) || isSvgPath(activeTab.filePath));
  }

  bool _isVisualPreviewFor(EditorTab activeTab) {
    return !activeTab.isLoading &&
        !activeTab.isDiff &&
        (isEditorImagePath(activeTab.filePath) ||
            isSvgPath(activeTab.filePath) ||
            isMarkdownPath(activeTab.filePath)) &&
        (isEditorImagePath(activeTab.filePath) ||
            _previewPaths.contains(activeTab.filePath));
  }

  Widget _wrapScaleGestures(Widget body) {
    return GestureDetector(
      onScaleStart: (d) => _scaleBase = _fontSizeNotifier.value,
      onScaleUpdate: (d) {
        final newSize = (_scaleBase * d.scale).clamp(8.0, 48.0);
        _fontSizeNotifier.value = newSize;
        SessionPrefs.saveEditorFontSize(newSize);
      },
      child: body,
    );
  }

  Widget _buildBody(
    FileEditorState state,
    CodeController? controller,
    bool toggleVisible,
    bool isVisualPreview,
  ) {
    final activeTab = state.activeTab!;
    final immersive = widget.immersive;
    return Column(
      children: [
        if (!immersive && !widget.hideTabBar) _TabBar(state: state),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _mainContent(activeTab, controller)),
              if (!immersive) _toggleBarOverlay(activeTab, toggleVisible),
              if (immersive && widget.onToggleImmersive != null)
                _exitImmersiveOverlay(),
              if (!immersive &&
                  isVisualPreview &&
                  widget.onToggleImmersive != null)
                _enterImmersiveOverlay(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mainContent(EditorTab activeTab, CodeController? controller) {
    return activeTab.isLoading
        ? const Center(child: CircularProgressIndicator())
        : activeTab.error != null
        ? _ErrorView(message: activeTab.error!)
        : activeTab.isDiff
        ? _DiffBody(tab: activeTab)
        : isEditorImagePath(activeTab.filePath)
        ? _ImagePreview(filePath: activeTab.filePath)
        : _previewPaths.contains(activeTab.filePath)
        ? (isSvgPath(activeTab.filePath)
              ? _SvgPreview(filePath: activeTab.filePath)
              : _MarkdownPreview(content: activeTab.content ?? ''))
        : _EditorBody(
            key: ValueKey(activeTab.filePath),
            tab: activeTab,
            codeController: controller!,
            fontSizeNotifier: _fontSizeNotifier,
            isLargeFile: isLargeEditorFile(activeTab.content),
          );
  }

  Widget _toggleBarOverlay(EditorTab activeTab, bool toggleVisible) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: _AnimatedToggleBar(
        visible: toggleVisible,
        child: _MarkdownToggleBar(
          isPreview: _previewPaths.contains(activeTab.filePath),
          onToggle: () => setState(() {
            final path = activeTab.filePath;
            if (_previewPaths.contains(path)) {
              _previewPaths.remove(path);
            } else {
              _previewPaths.add(path);
            }
            SessionPrefs.savePreviewPaths(_previewPaths.toList());
          }),
        ),
      ),
    );
  }

  Widget _exitImmersiveOverlay() {
    return Positioned(
      top: 8,
      right: 8,
      child: _ImmersiveButton(
        icon: Icons.close_fullscreen_rounded,
        tooltip: 'Exit focus mode',
        onTap: widget.onToggleImmersive!,
      ),
    );
  }

  Widget _enterImmersiveOverlay() {
    return Positioned(
      bottom: 8,
      right: 8,
      child: _ImmersiveButton(
        icon: Icons.open_in_full_rounded,
        tooltip: 'Focus mode — hide chrome',
        onTap: widget.onToggleImmersive!,
      ),
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
            Icon(Icons.code, size: 40, color: colors.textMuted.withAlpha(60)),
            const SizedBox(height: 12),
            const Caption('Open a file to edit', fontSize: 13),
          ],
        ),
      ),
    );
  }
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
              color: active ? colors.primary : colors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? colors.primary : colors.textMuted,
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
    final colors = context.appColors;
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
                  ? colors.surfaceHighlight
                  : colors.surface.withAlpha(0xCC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _hovered
                    ? colors.primary
                    : colors.primary.withAlpha(0x40),
              ),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _hovered ? colors.primary : colors.primary.withAlpha(0x90),
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
    return Padding(
      padding: const EdgeInsets.only(top: 34),
      child: MarkdownDocumentPreview(content: content),
    );
  }
}

// ── Image preview (raster only) ────────────────────────────────────────────

class _ImagePreviewHeader extends StatelessWidget {
  const _ImagePreviewHeader({required this.filePath});
  final String filePath;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final ext = filePath.split('.').last.toLowerCase();
    final fileName = filePath.split('/').last;
    final muted = Theme.of(context).colorScheme.onSurface.withAlpha(120);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.image_outlined, size: 14, color: muted),
          const SizedBox(width: 6),
          Text(fileName, style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(width: 6),
          Text(ext.toUpperCase(), style: TextStyle(color: muted, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.filePath});
  final String filePath;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      color: colors.background,
      child: Column(
        children: [
          _ImagePreviewHeader(filePath: filePath),
          Expanded(
            child: InteractiveViewer(
              minScale: 0.1,
              maxScale: 10,
              child: Center(
                child: Image.file(
                  File(filePath),
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Text(
                      'Cannot load image',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(120),
                      ),
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
        border: Border(bottom: BorderSide(color: colors.border, width: 1)),
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
              ),
            ),
          ),
        ],
      ),
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
  });

  final EditorTab tab;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onCloseOthers;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  Future<void> _showTabMenu(BuildContext context, Offset globalPos) async {
    final colors = context.appColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx,
        globalPos.dy,
      ),
      color: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      items: [
        PopupMenuItem(
          value: 'close',
          child: Text(
            '✕ Close',
            style: TextStyle(fontSize: 12, color: onSurface),
          ),
        ),
        PopupMenuItem(
          value: 'close_others',
          child: Text(
            '✕ Close Others',
            style: TextStyle(fontSize: 12, color: onSurface),
          ),
        ),
      ],
    );
    if (result == null) return;
    switch (result) {
      case 'close':
        widget.onClose();
      case 'close_others':
        widget.onCloseOthers?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final fileInfo = widget.tab.isDiff
        ? null
        : FileTypeUtils.forPath(widget.tab.filePath);
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
              constraints: const BoxConstraints(maxWidth: 170, minWidth: 60),
              padding: const EdgeInsets.only(
                left: 10,
                right: 4,
                top: 0,
                bottom: 0,
              ),
              decoration: BoxDecoration(
                color: widget.isActive ? colors.background : Colors.transparent,
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
                        ? Theme.of(context).colorScheme.onSurface.withAlpha(120)
                        : fileInfo!.color,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      displayName,
                      style: TextStyle(
                        color: widget.isActive
                            ? colors.primaryLight
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withAlpha(120),
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
            color: _hovering
                ? context.appColors.textPrimary.withAlpha(30)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Icon(
            Icons.close,
            size: 11,
            color: _hovering
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurface.withAlpha(180),
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
          style: TextStyle(color: colors.statusError, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ── Editor body (StatefulWidget) ────────────────────────────────────────────

class _LargeFileBanner extends StatelessWidget {
  const _LargeFileBanner();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      color: colors.accentOrange.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: colors.accentOrange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Large file — syntax highlighting disabled for performance.',
              style: TextStyle(fontSize: 11, color: colors.accentOrange),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorBody extends StatefulWidget {
  const _EditorBody({
    super.key,
    required this.tab,
    required this.codeController,
    required this.fontSizeNotifier,
    this.isLargeFile = false,
  });
  final EditorTab tab;
  final CodeController codeController;
  final ValueNotifier<double> fontSizeNotifier;
  final bool isLargeFile;
  @override
  State<_EditorBody> createState() => _EditorBodyState();
}

enum _QuickFindCloseSelection { selected, collapsedStart, collapsedEnd }

class _EditorBodyState extends State<_EditorBody> {
  final _editorFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _replaceCtrl = TextEditingController();
  final _replaceFocus = FocusNode();
  bool _showQuickFind = false;
  bool _showReplace = false;
  String _quickFindQuery = '';
  List<int> _quickFindOffsets = [];
  int _quickFindCurrent = 0;
  int _quickFindOrigin = 0;

  // ── Editor options ───────────────────────────────────────────────────────
  bool _wordWrap = false;
  bool _showOutline = false;

  // ── Auto-pairs ───────────────────────────────────────────────────────────
  bool _suppressPairInsert = false;
  TextEditingValue? _lastValue;

  // ── Git gutter ───────────────────────────────────────────────────────────
  Map<int, GutterMarkerType> _gitMarkers = {};
  final ValueNotifier<double> _codeScrollOffset = ValueNotifier(0);

  late final Map<ShortcutActivator, VoidCallback> _shortcutBindings = {
    const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
    const SingleActivator(LogicalKeyboardKey.keyH, meta: true): _openReplace,
    const SingleActivator(LogicalKeyboardKey.keyJ, meta: true): _openQuickFind,
    const SingleActivator(LogicalKeyboardKey.slash, meta: true): _toggleComment,
    const SingleActivator(LogicalKeyboardKey.keyD, meta: true): _duplicateLine,
    const SingleActivator(LogicalKeyboardKey.keyK, meta: true, shift: true):
        _deleteLine,
    const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _moveLineUp,
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
  };

  @override
  void initState() {
    super.initState();
    widget.codeController.addListener(_onTextChanged);
    widget.codeController.searchController.addListener(_onSearchChanged);
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
      _clearQuickFindSearchResult(
        controller: old.codeController,
        notify: false,
      );
      old.codeController.removeListener(_onTextChanged);
      old.codeController.searchController.removeListener(_onSearchChanged);
      widget.codeController.addListener(_onTextChanged);
      widget.codeController.searchController.addListener(_onSearchChanged);
    }
  }

  @override
  void dispose() {
    _clearQuickFindSearchResult(notify: false);
    widget.codeController.removeListener(_onTextChanged);
    widget.codeController.searchController.removeListener(_onSearchChanged);
    _replaceCtrl.dispose();
    _replaceFocus.dispose();
    _editorFocus.dispose();
    _codeFocus.dispose();
    _codeScrollOffset.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;
    if (!widget.codeController.searchController.shouldShow && _showReplace) {
      setState(() => _showReplace = false);
      return;
    }
    setState(() {});
  }

  // ── Auto-pairs ───────────────────────────────────────────────────────────

  void _onTextChanged() {
    if (_suppressPairInsert) return;
    final cur = widget.codeController.value;
    final prev = _lastValue;
    _lastValue = cur;

    if (prev == null) return;
    final paired = applyAutoPair(
      prevText: prev.text,
      curText: cur.text,
      selectionCollapsed: cur.selection.isCollapsed,
      cursorPos: cur.selection.baseOffset,
    );
    if (paired == null) return;

    _suppressPairInsert = true;
    try {
      widget.codeController.value = TextEditingValue(
        text: paired.text,
        selection: TextSelection.collapsed(offset: paired.cursor),
      );
      _lastValue = widget.codeController.value;
    } finally {
      _suppressPairInsert = false;
    }
  }

  // ── Git gutter ───────────────────────────────────────────────────────────

  Future<void> _loadGitGutter() async {
    if (!_shouldLoadGitGutter) return;
    await _doLoadGitGutter();
  }

  bool get _shouldLoadGitGutter =>
      widget.tab.workspacePath != null && !widget.tab.isDiff;

  Future<void> _doLoadGitGutter() async {
    try {
      final diff = await GitService.instance.getDiff(
        widget.tab.workspacePath!,
        widget.tab.filePath,
      );
      if (mounted && diff.isNotEmpty) {
        setState(() => _gitMarkers = parseDiffMarkers(diff));
      }
    } catch (_) {}
  }

  // ── Language helpers ────────────────────────────────────────────────────
  static String _languageName(String filePath) =>
      EditorLanguageRegistry.forPath(filePath).label;

  static String _commentPrefix(String filePath) {
    return EditorLanguageRegistry.forPath(filePath).commentPrefix;
  }

  // ── Find & replace ──────────────────────────────────────────────────────
  void _openFind() {
    _closeQuickFind(returnFocusToCode: false);
    _codeFocus.requestFocus();
    widget.codeController.showSearch();
  }

  void _openReplace() {
    _closeQuickFind(returnFocusToCode: false);
    setState(() => _showReplace = true);
    _codeFocus.requestFocus();
    widget.codeController.showSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _replaceFocus.requestFocus();
    });
  }

  void _openQuickFind() {
    final cursor = widget.codeController.selection.extentOffset;
    _clearQuickFindSearchResult();
    setState(() {
      _showQuickFind = true;
      _quickFindQuery = '';
      _quickFindOffsets = [];
      _quickFindCurrent = 0;
      _quickFindOrigin = cursor.clamp(0, widget.codeController.text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editorFocus.requestFocus();
    });
  }

  void _closeQuickFind({
    bool returnFocusToCode = true,
    _QuickFindCloseSelection selection = _QuickFindCloseSelection.selected,
  }) {
    if (!_showQuickFind) return;
    final currentRange = _quickFindCurrentRange();
    _clearQuickFindSearchResult(notify: false);
    if (currentRange != null) {
      final nextSelection = switch (selection) {
        _QuickFindCloseSelection.selected => TextSelection(
          baseOffset: currentRange.start,
          extentOffset: currentRange.end,
        ),
        _QuickFindCloseSelection.collapsedStart => TextSelection.collapsed(
          offset: currentRange.start,
        ),
        _QuickFindCloseSelection.collapsedEnd => TextSelection.collapsed(
          offset: currentRange.end,
        ),
      };
      widget.codeController.selection = nextSelection;
    } else {
      widget.codeController.notifyListeners();
    }
    setState(() {
      _showQuickFind = false;
      _quickFindQuery = '';
      _quickFindOffsets = [];
      _quickFindCurrent = 0;
    });
    if (returnFocusToCode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _codeFocus.requestFocus();
      });
    }
  }

  ({int start, int end})? _quickFindCurrentRange() {
    if (_quickFindQuery.isEmpty || _quickFindOffsets.isEmpty) return null;
    final start = _quickFindOffsets[_quickFindCurrent];
    return (start: start, end: start + _quickFindQuery.length);
  }

  void _updateQuickFindQuery(String query) {
    final currentSelection = widget.codeController.selection.start;
    final searchOrigin = _quickFindOffsets.isEmpty || currentSelection < 0
        ? _quickFindOrigin
        : currentSelection.clamp(0, widget.codeController.text.length);
    final matches = computeQuickFindMatches(
      text: widget.codeController.text,
      query: query,
      searchOrigin: searchOrigin,
    );

    setState(() {
      _quickFindQuery = query;
      _quickFindOffsets = matches.offsets;
      _quickFindCurrent = matches.current;
    });
    _selectQuickFindCurrent();
  }

  void _selectQuickFindCurrent() {
    _syncQuickFindSearchResult();
    if (_quickFindQuery.isEmpty || _quickFindOffsets.isEmpty) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editorFocus.requestFocus();
      });
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editorFocus.requestFocus();
    });
  }

  void _syncQuickFindSearchResult() {
    final matches = _quickFindOffsets
        .map(
          (offset) =>
              SearchMatch(start: offset, end: offset + _quickFindQuery.length),
        )
        .toList(growable: false);
    widget.codeController.fullSearchResult = SearchResult(matches: matches);
    widget.codeController.searchController.navigationController.value =
        matches.isEmpty
        ? SearchNavigationState.noMatches
        : SearchNavigationState(
            totalMatchCount: matches.length,
            currentMatchIndex: _quickFindCurrent,
          );
  }

  void _clearQuickFindSearchResult({
    CodeController? controller,
    bool notify = true,
  }) {
    final target = controller ?? widget.codeController;
    target.fullSearchResult = SearchResult.empty;
    target.searchController.navigationController.value =
        SearchNavigationState.noMatches;
    if (notify) target.notifyListeners();
  }

  void _quickFindNext() {
    if (_quickFindOffsets.isEmpty) return;
    setState(() {
      _quickFindCurrent = (_quickFindCurrent + 1) % _quickFindOffsets.length;
    });
    _selectQuickFindCurrent();
  }

  void _quickFindPrev() {
    if (_quickFindOffsets.isEmpty) return;
    setState(() {
      _quickFindCurrent =
          (_quickFindCurrent - 1 + _quickFindOffsets.length) %
          _quickFindOffsets.length;
    });
    _selectQuickFindCurrent();
  }

  void _replaceCurrentMatch() {
    final result = widget.codeController.fullSearchResult;
    final nav =
        widget.codeController.searchController.navigationController.value;
    final index = nav.currentMatchIndex;
    if (index == null || index < 0 || index >= result.matches.length) return;
    final match = result.matches[index];
    _replaceRange(match.start, match.end, _replaceCtrl.text);
  }

  void _replaceAllMatches() {
    final matches = widget.codeController.fullSearchResult.matches;
    if (matches.isEmpty) return;
    var text = widget.codeController.text;
    for (final match in matches.reversed) {
      text =
          text.substring(0, match.start) +
          _replaceCtrl.text +
          text.substring(match.end);
    }
    widget.codeController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _replaceRange(int start, int end, String replacement) {
    final text = widget.codeController.text;
    final nextText =
        text.substring(0, start) + replacement + text.substring(end);
    widget.codeController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  bool _handleQuickFindKey(KeyEvent event) {
    if (!_showQuickFind) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final action = _quickFindKeyActions[event.logicalKey];
    if (action != null) {
      action();
      return true;
    }
    return _handleQuickFindCharacter(event);
  }

  late final Map<LogicalKeyboardKey, void Function()> _quickFindKeyActions = {
    LogicalKeyboardKey.escape: _closeQuickFind,
    LogicalKeyboardKey.arrowLeft: () =>
        _closeQuickFind(selection: _QuickFindCloseSelection.collapsedStart),
    LogicalKeyboardKey.arrowRight: () =>
        _closeQuickFind(selection: _QuickFindCloseSelection.collapsedEnd),
    LogicalKeyboardKey.arrowDown: _quickFindNext,
    LogicalKeyboardKey.enter: _quickFindNext,
    LogicalKeyboardKey.arrowUp: _quickFindPrev,
    LogicalKeyboardKey.backspace: _quickFindBackspace,
  };

  void _quickFindBackspace() {
    if (_quickFindQuery.isNotEmpty) {
      _updateQuickFindQuery(
        _quickFindQuery.substring(0, _quickFindQuery.length - 1),
      );
    }
  }

  bool _handleQuickFindCharacter(KeyEvent event) {
    final modifierPressed =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed;
    if (!shouldAcceptQuickFindCharacter(
      modifierPressed: modifierPressed,
      character: event.character,
    )) {
      return false;
    }
    _updateQuickFindQuery(_quickFindQuery + event.character!);
    return true;
  }

  bool _handleNativeSearchTypeahead(KeyEvent event) {
    if (_shouldIgnoreTypeahead(event)) return false;
    final ch = event.character!;
    final searchController = widget.codeController.searchController;

    final controller = searchController.settingsController.patternController;
    final value = controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final start = selection.start.clamp(0, value.text.length);
    final end = selection.end.clamp(0, value.text.length);
    final nextText = value.text.replaceRange(start, end, ch);
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + ch.length),
    );
    searchController.patternFocusNode.requestFocus();
    return true;
  }

  bool _shouldIgnoreTypeahead(KeyEvent event) {
    final searchController = widget.codeController.searchController;
    final modifierPressed =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed;
    return shouldIgnoreTypeahead(
      searchVisible: searchController.shouldShow,
      patternFocused: searchController.patternFocusNode.hasFocus,
      isKeyDownOrRepeat: event is KeyDownEvent || event is KeyRepeatEvent,
      modifierPressed: modifierPressed,
      character: event.character,
    );
  }

  // ── Text editing helpers ────────────────────────────────────────────────
  void _toggleComment() {
    final ctrl = widget.codeController;
    final result = toggleCommentLine(
      ctrl.text,
      ctrl.selection.start,
      _commentPrefix(widget.tab.filePath),
    );
    ctrl.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursor),
    );
  }

  void _duplicateLine() {
    final ctrl = widget.codeController;
    final result = duplicateLineInText(ctrl.text, ctrl.selection.start);
    ctrl.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursor),
    );
  }

  void _deleteLine() {
    final ctrl = widget.codeController;
    final result = deleteLineInText(ctrl.text, ctrl.selection.start);
    if (result == null) return;
    ctrl.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursor),
    );
  }

  void _moveLineUp() {
    final ctrl = widget.codeController;
    final result = moveLineUpInText(ctrl.text, ctrl.selection.start);
    if (result == null) return;
    ctrl.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursor),
    );
  }

  void _moveLineDown() {
    final ctrl = widget.codeController;
    final result = moveLineDownInText(ctrl.text, ctrl.selection.start);
    if (result == null) return;
    ctrl.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursor),
    );
  }

  void _indentLine() {
    final ctrl = widget.codeController;
    final result = indentLineInText(ctrl.text, ctrl.selection.start);
    ctrl.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursor),
    );
  }

  void _outdentLine() {
    final ctrl = widget.codeController;
    final result = outdentLineInText(ctrl.text, ctrl.selection.start);
    if (result == null) return;
    ctrl.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursor),
    );
  }

  // ── Format document ─────────────────────────────────────────────────────
  Future<void> _formatDocument() async {
    final path = widget.tab.filePath;
    if (!path.endsWith('.dart')) return;
    try {
      final result = await formatDocumentProcessRunner('dart', [
        'format',
        '--fix',
        path,
      ]);
      if (result.exitCode == 0 && mounted) {
        final newContent = await File(path).readAsString();
        if (!mounted) return;
        widget.codeController.value = TextEditingValue(
          text: newContent,
          selection: const TextSelection.collapsed(offset: 0),
        );
        context.read<FileEditorCubit>().updateContent(newContent);
      }
    } catch (_) {}
  }

  // ── Go to line ──────────────────────────────────────────────────────────
  Future<void> _showGoToLine(BuildContext ctx) async {
    final ctrl = widget.codeController;
    final lineCount = '\n'.allMatches(ctrl.text).length + 1;
    final colors = ctx.appColors;
    final colorScheme = Theme.of(ctx).colorScheme;
    await showDialog<void>(
      context: ctx,
      barrierColor: colors.background.withAlpha(138),
      builder: (dctx) {
        final onSurface = colorScheme.onSurface;
        final mutedColor = onSurface.withAlpha(120);
        final borderColor = colors.border;
        return Dialog(
          backgroundColor: colors.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Go to Line',
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: onSurface, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '1 – $lineCount',
                    hintStyle: TextStyle(color: mutedColor),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: colors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n >= 1 && n <= lineCount) {
                      _jumpToLine(ctrl, n);
                    }
                    Navigator.of(dctx).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _jumpToLine(CodeController ctrl, int lineNumber) {
    ctrl.selection = TextSelection.collapsed(
      offset: lineStartOffset(ctrl.text, lineNumber),
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
      bindings: _shortcutBindings,
      child: Focus(
        focusNode: _editorFocus,
        descendantsAreFocusable: !_showQuickFind,
        onKeyEvent: (_, event) =>
            _handleQuickFindKey(event) || _handleNativeSearchTypeahead(event)
            ? KeyEventResult.handled
            : KeyEventResult.ignored,
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
            ),
            if (widget.isLargeFile) const _LargeFileBanner(),
            ..._searchBarSection(),
            Expanded(
              child: Stack(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildEditorColumn(colors, language)),
                      ..._outlineSection(),
                    ],
                  ),
                  ..._quickFindHintSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _searchBarSection() {
    if (!widget.codeController.searchController.shouldShow) return const [];
    return [
      SearchReplaceBar(
        controller: widget.codeController,
        replaceController: _replaceCtrl,
        replaceFocus: _replaceFocus,
        showReplace: _showReplace,
        onToggleReplace: () => setState(() => _showReplace = !_showReplace),
        onReplace: _replaceCurrentMatch,
        onReplaceAll: _replaceAllMatches,
      ),
    ];
  }

  List<Widget> _outlineSection() {
    if (!_showOutline) return const [];
    return [
      _SymbolOutline(
        content: widget.codeController.text,
        filePath: widget.tab.filePath,
        onJumpToLine: (line) => _jumpToLine(widget.codeController, line),
      ),
    ];
  }

  List<Widget> _quickFindHintSection() {
    if (!_showQuickFind) return const [];
    return [
      Positioned(
        top: 8,
        left: 24,
        child: _QuickFindHint(
          query: _quickFindQuery,
          matchCount: _quickFindOffsets.length,
          currentMatch: _quickFindCurrent,
        ),
      ),
    ];
  }

  Widget _buildEditorColumn(AppColorScheme colors, String language) {
    return Column(
      children: [
        Expanded(
          child: ValueListenableBuilder<double>(
            valueListenable: widget.fontSizeNotifier,
            builder: (context, fontSize, _) =>
                _buildCodeScrollArea(context, colors, fontSize),
          ),
        ),
        _EditorStatusBar(controller: widget.codeController, language: language),
      ],
    );
  }

  Widget _buildCodeScrollArea(
    BuildContext context,
    AppColorScheme colors,
    double fontSize,
  ) {
    final lineHeight = fontSize * 1.5;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis == Axis.vertical) {
          _codeScrollOffset.value = n.metrics.pixels;
        }
        return false;
      },
      child: RepaintBoundary(
        child: Stack(
          children: [
            _buildCodeField(context, colors, fontSize),
            // Git gutter overlay — 3px strip at left edge of gutter.
            ..._gitGutterSection(lineHeight),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeField(
    BuildContext context,
    AppColorScheme colors,
    double fontSize,
  ) {
    return CodeTheme(
      data: CodeThemeData(styles: _buildDarkTheme(colors)),
      child: CodeField(
        focusNode: _codeFocus,
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
          textStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
            fontFamily: 'monospace',
          ),
          background: colors.surfaceElevated,
        ),
      ),
    );
  }

  List<Widget> _gitGutterSection(double lineHeight) {
    if (_gitMarkers.isEmpty) return const [];
    return [
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: 3,
        child: ValueListenableBuilder<double>(
          valueListenable: _codeScrollOffset,
          builder: (context, scrollOffset, _) {
            return _GitGutterPainter(
              markers: _gitMarkers,
              lineHeight: lineHeight,
              scrollOffset: scrollOffset,
            );
          },
        ),
      ),
    ];
  }

  static Map<String, TextStyle> _buildDarkTheme(AppColorScheme colors) => {
    'root': TextStyle(
      color: colors.textPrimary,
      backgroundColor: Colors.transparent,
    ),
    'comment': TextStyle(color: colors.textMuted, fontStyle: FontStyle.italic),
    'keyword': TextStyle(color: colors.primaryLight),
    'built_in': TextStyle(color: colors.accentOrange),
    'type': TextStyle(color: colors.accentOrange),
    'literal': TextStyle(color: colors.accentBlue),
    'number': TextStyle(color: colors.accentOrange),
    'regexp': TextStyle(color: colors.accentGreen),
    'string': TextStyle(color: colors.accentGreen),
    'subst': TextStyle(color: colors.textPrimary),
    'symbol': TextStyle(color: colors.accentBlue),
    'class': TextStyle(color: colors.accentOrange),
    'function': TextStyle(color: colors.accentBlue),
    'title': TextStyle(color: colors.accentBlue),
    'params': TextStyle(color: colors.textPrimary),
    'formula': TextStyle(color: colors.accentGreen),
    'comment-doc': TextStyle(
      color: colors.textMuted,
      fontStyle: FontStyle.italic,
    ),
    'meta': TextStyle(color: colors.accentBlue),
    'tag': TextStyle(color: colors.accentRed),
    'name': TextStyle(color: colors.accentRed),
    'attr': TextStyle(color: colors.accentOrange),
    'attribute': TextStyle(color: colors.accentOrange),
    'variable': TextStyle(color: colors.accentRed),
    'bullet': TextStyle(color: colors.accentBlue),
    'code': TextStyle(color: colors.accentGreen),
    'emphasis': const TextStyle(fontStyle: FontStyle.italic),
    'strong': const TextStyle(fontWeight: FontWeight.bold),
    'link': TextStyle(
      color: colors.accentBlue,
      decoration: TextDecoration.underline,
    ),
    'section': TextStyle(color: colors.accentRed, fontWeight: FontWeight.bold),
    'selector-tag': TextStyle(color: colors.accentRed),
    'selector-id': TextStyle(color: colors.accentBlue),
    'selector-class': TextStyle(color: colors.accentOrange),
    'addition': TextStyle(color: colors.diffAddText),
    'deletion': TextStyle(color: colors.diffRemoveText),
  };
}

// ── Git gutter types & painter ────────────────────────────────────────────────

class _GitGutterPainter extends StatelessWidget {
  const _GitGutterPainter({
    required this.markers,
    required this.lineHeight,
    required this.scrollOffset,
  });

  final Map<int, GutterMarkerType> markers;
  final double lineHeight;
  final double scrollOffset;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (_, constraints) => CustomPaint(
        size: Size(3, constraints.maxHeight),
        painter: _GutterPaint(
          markers: markers,
          lineHeight: lineHeight,
          scrollOffset: scrollOffset,
          addedColor: colors.diffAddText,
          removedColor: colors.diffRemoveText,
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
    required this.addedColor,
    required this.removedColor,
  });

  final Map<int, GutterMarkerType> markers;
  final double lineHeight;
  final double scrollOffset;
  final Color addedColor;
  final Color removedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final addedPaint = Paint()..color = addedColor;
    final removedPaint = Paint()..color = removedColor;

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
        entry.value == GutterMarkerType.added ? addedPaint : removedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GutterPaint old) =>
      old.scrollOffset != scrollOffset ||
      old.markers != markers ||
      old.lineHeight != lineHeight;
}

/// Test seam that constructs the private [_GutterPaint] so unit tests can
/// exercise [CustomPainter.paint] without building the full widget tree.
@visibleForTesting
CustomPainter createGutterPainterForTest({
  required Map<int, GutterMarkerType> markers,
  required double lineHeight,
  required double scrollOffset,
  required Color addedColor,
  required Color removedColor,
}) =>
    _GutterPaint(
      markers: markers,
      lineHeight: lineHeight,
      scrollOffset: scrollOffset,
      addedColor: addedColor,
      removedColor: removedColor,
    );

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
  });
  final String language;
  final bool wordWrap;
  final bool showOutline;
  final VoidCallback onToggleWordWrap;
  final VoidCallback onFormat;
  final VoidCallback onToggleOutline;
  final VoidCallback onGoToLine;

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
            child: Caption(language, fontSize: 10),
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
            color: active ? colors.primaryLight : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

// ── Quick Find hint ──────────────────────────────────────────────────────────

class _QuickFindHint extends StatelessWidget {
  const _QuickFindHint({
    required this.query,
    required this.matchCount,
    required this.currentMatch,
  });

  final String query;
  final int matchCount;
  final int currentMatch;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasQuery = query.isNotEmpty;
    final status = !hasQuery
        ? ''
        : matchCount == 0
        ? '  no matches'
        : '  ${currentMatch + 1}/$matchCount';
    return DecoratedBox(
      key: const Key('editor-quick-find-hint'),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'Search for: $query$status',
          style: TextStyle(
            color: matchCount == 0 && hasQuery
                ? colors.statusError
                : colors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
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
    if (l != _line || c != _col) {
      setState(() {
        _line = l;
        _col = c;
      });
    }
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
          Caption('Ln $_line, Col $_col', fontSize: 10),
          _SBar(),
          const Caption('UTF-8', fontSize: 10),
          _SBar(),
          const Caption('LF', fontSize: 10),
          _SBar(),
          Caption(widget.language, fontSize: 10),
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
      color: context.appColors.border,
    );
  }
}

// ── Symbol outline ───────────────────────────────────────────────────────────

class _OutlineItem extends StatelessWidget {
  const _OutlineItem({required this.symbol, required this.onTap});
  final OutlineSymbol symbol;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: () => onTap(symbol.line),
      child: Padding(
        padding: EdgeInsets.only(
          left: symbol.isClass ? 8 : 20,
          right: 8,
          top: 3,
          bottom: 3,
        ),
        child: Row(
          children: [
            Icon(
              symbol.isClass ? Icons.category_outlined : Icons.functions,
              size: 11,
              color: symbol.isClass
                  ? context.appColors.accentOrange
                  : context.appColors.accentBlue,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                symbol.name,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${symbol.line}',
              style: TextStyle(color: colors.textMuted, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
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
    final symbols = parseOutlineSymbols(content, filePath);
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
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Outline',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            child: symbols.isEmpty
                ? const Center(child: Caption('No symbols'))
                : ListView.builder(
                    itemCount: symbols.length,
                    itemBuilder: (_, i) =>
                        _OutlineItem(symbol: symbols[i], onTap: onJumpToLine),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DiffEmptyState extends StatelessWidget {
  const _DiffEmptyState({required this.filePath});
  final String filePath;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.difference_outlined,
            size: 32,
            color: colors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            'No diff available',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Caption(
            filePath.replaceFirst('diff:', ''),
            textAlign: TextAlign.center,
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
      return _DiffEmptyState(filePath: tab.filePath);
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
              style: TextStyle(
                color: colors.textMuted,
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
    final colors = context.appColors;
    Color bg;
    Color textColor;
    String prefix;

    switch (line.type) {
      case DiffLineType.add:
        bg = colors.diffAddBg;
        textColor = colors.diffAddText;
        prefix = '+';
      case DiffLineType.remove:
        bg = colors.diffRemoveBg;
        textColor = colors.diffRemoveText;
        prefix = '-';
      default:
        bg = Colors.transparent;
        textColor = colors.textSecondary;
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
              '${line.oldLineNum ?? ''}',
              style: TextStyle(
                color: colors.textMuted,
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
              '${line.newLineNum ?? ''}',
              style: TextStyle(
                color: colors.textMuted,
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
