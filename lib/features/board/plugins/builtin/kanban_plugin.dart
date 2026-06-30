import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/events/board_event_bus.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/terminal/data/smart_clipboard_paste_service.dart';
import 'package:yoloit/ui/components/dialog/editor_dialog_actions.dart';
import 'package:yoloit/ui/components/editor/markdown_editor_pane.dart';


final _kanbanDefaultColors = AppColorScheme.fromAccent(Colors.indigo);

class KanbanPlugin extends BoardPanelPlugin {
  const KanbanPlugin();

  static const String kTypeId = 'board.kanban';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Kanban Board';

  @override
  IconData get icon => Icons.view_kanban_outlined;

  @override
  Color get accentColor => _kanbanDefaultColors.primary;

  @override
  Size get defaultSize => const Size(640, 420);

  @override
  Map<String, dynamic> get initialState => {
    'columns': ['Backlog', 'Todo', 'In Progress', 'Done'],
    'cards': <Map<String, dynamic>>[],
  };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _KanbanContent(panel: panel, renderContext: renderContext);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data helpers
// ─────────────────────────────────────────────────────────────────────────────

typedef _CardData = Map<String, dynamic>;

class _KanbanContent extends StatefulWidget {
  const _KanbanContent({required this.panel, required this.renderContext});
  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;
  @override
  State<_KanbanContent> createState() => _KanbanContentState();
}

class _KanbanContentState extends State<_KanbanContent> {
  List<Color> _columnColorPalette(AppColorScheme colors) => [
    colors.primary,
    colors.accentBlue,
    colors.accentGreen,
    colors.accentOrange,
    colors.accentRed,
    colors.primaryLight,
    colors.primaryDark,
    colors.textSecondary,
  ];

  // ── State helpers ──────────────────────────────────────────────────────────

  List<String> get _columns =>
      (widget.panel.state['columns'] as List?)
          ?.map((e) => e.toString())
          .toList() ??
      ['Backlog', 'Todo', 'In Progress', 'Done'];

  /// Per-column color stored as hex string keyed by column index.
  Map<String, String> get _columnColors {
    final raw = widget.panel.state['columnColors'];
    if (raw is Map) return Map<String, String>.from(raw);
    return {};
  }

  Color _colColor(int ci) {
    final hex = _columnColors['$ci'];
    if (hex != null && hex.isNotEmpty) {
      final v = int.tryParse(hex, radix: 16);
      if (v != null) return Color(v);
    }
    return context.appColors.primary;
  }

  List<_CardData> get _cards =>
      (widget.panel.state['cards'] as List?)
          ?.whereType<Map<dynamic, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList() ??
      [];

  // ── Local UI state ─────────────────────────────────────────────────────────

  bool _editMode = false;

  // search/filter state
  bool _searchActive = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  // per-column add-card controllers
  final Map<int, TextEditingController> _addCtrl = {};
  final Map<int, bool> _adding = {};

  // column rename
  int? _renamingCol;
  final _renameCtrl = TextEditingController();

  // drag highlight
  int? _dragOverCol;

  // keyboard focus for clipboard paste
  final _focusNode = FocusNode();

  @override
  void dispose() {
    for (final c in _addCtrl.values) {
      c.dispose();
    }
    _renameCtrl.dispose();
    _focusNode.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  void _saveCards(List<_CardData> cards) {
    widget.renderContext.onUpdateState({...widget.panel.state, 'cards': cards});
  }

  void _saveColumns(List<String> cols) {
    // Re-clamp card columnIndex to valid range
    final cards =
        _cards.map((c) {
          final ci = (c['columnIndex'] as int? ?? 0).clamp(0, cols.length - 1);
          return {...c, 'columnIndex': ci};
        }).toList();
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'columns': cols,
      'cards': cards,
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      setState(() => _searchQuery = value.trim().toLowerCase());
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    setState(() => _searchQuery = '');
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _searchActive = false;
      _searchQuery = '';
    });
  }

  Future<void> _pasteFromClipboard({int columnIndex = 0}) async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard is empty')),
        );
      }
      return;
    }
    _addCardFromText(text.trim(), columnIndex: columnIndex);
  }

  void _addCardFromText(String text, {int columnIndex = 0}) {
    final lines = text.split('\n');
    final title = lines.first.trim();
    final description = lines.skip(1).join('\n').trim();
    final cards = List<Map<String, dynamic>>.from(_cards);
    cards.add({
      'id': 'card-${DateTime.now().millisecondsSinceEpoch}',
      'title': title.length > 120 ? '${title.substring(0, 120)}…' : title,
      'description': description,
      'columnIndex': columnIndex.clamp(0, _columns.length - 1),
    });
    _saveCards(cards);
  }

  // ── Column actions ─────────────────────────────────────────────────────────

  void _addColumn() {
    final cols = List<String>.from(_columns)..add('New Column');
    _saveColumns(cols);
  }

  void _deleteColumn(int ci) {
    final cols = List<String>.from(_columns)..removeAt(ci);
    final cards =
        _cards.where((c) => (c['columnIndex'] as int? ?? 0) != ci).map((c) {
          final old = c['columnIndex'] as int? ?? 0;
          return {...c, 'columnIndex': old > ci ? old - 1 : old};
        }).toList();
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'columns': cols,
      'cards': cards,
    });
  }

  void _moveColumn(int from, int to) {
    if (from == to) return;
    final cols = List<String>.from(_columns);
    final col = cols.removeAt(from);
    cols.insert(to, col);
    // Remap card columnIndex values to follow the move.
    final cards =
        _cards.map((c) {
          var ci = c['columnIndex'] as int? ?? 0;
          if (ci == from) {
            ci = to;
          } else if (from < to && ci > from && ci <= to) {
            ci -= 1;
          } else if (from > to && ci >= to && ci < from) {
            ci += 1;
          }
          return {...c, 'columnIndex': ci};
        }).toList();
    // Remap column colors.
    final oldColors = _columnColors;
    final newColors = <String, String>{};
    for (int i = 0; i < cols.length; i++) {
      int oldIdx;
      if (i == to) {
        oldIdx = from;
      } else if (from < to && i >= from && i < to) {
        oldIdx = i + 1;
      } else if (from > to && i > to && i <= from) {
        oldIdx = i - 1;
      } else {
        oldIdx = i;
      }
      final c = oldColors['$oldIdx'];
      if (c != null) newColors['$i'] = c;
    }
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'columns': cols,
      'cards': cards,
      'columnColors': newColors,
    });
  }

  void _setColumnColor(int ci, Color color) {
    final colors = Map<String, String>.from(_columnColors);
    colors['$ci'] = color.toARGB32().toRadixString(16).padLeft(8, '0');
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'columnColors': colors,
    });
  }

  void _renameColumn(int ci, String name) {
    final cols = List<String>.from(_columns);
    cols[ci] = name.trim().isEmpty ? 'Column ${ci + 1}' : name.trim();
    _saveColumns(cols);
    setState(() => _renamingCol = null);
  }

  // ── Card actions ───────────────────────────────────────────────────────────

  void _addCard(int ci) {
    final ctrl = _addCtrl[ci];
    if (ctrl == null) return;
    final title = ctrl.text.trim();
    if (title.isEmpty) {
      setState(() => _adding[ci] = false);
      return;
    }
    final cards = List<_CardData>.from(_cards)..add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': title,
      'description': '',
      'columnIndex': ci,
    });
    ctrl.clear();
    setState(() => _adding[ci] = false);
    _saveCards(cards);
  }

  void _deleteCard(String id) {
    _saveCards(_cards.where((c) => c['id'] != id).toList());
  }

  void _moveCardToColumn(String cardId, int targetCol) {
    final cards = _cards;
    final idx = cards.indexWhere((c) => c['id'] == cardId);
    if (idx == -1) return;
    final updated = List<_CardData>.from(cards);
    updated[idx] = {...updated[idx], 'columnIndex': targetCol};
    _saveCards(updated);
  }

  void _updateCard(String cardId, _CardData patch) {
    final cards = _cards;
    final idx = cards.indexWhere((c) => c['id'] == cardId);
    if (idx == -1) return;
    final updated = List<_CardData>.from(cards);
    updated[idx] = {...updated[idx], ...patch};
    _saveCards(updated);
  }

  Future<void> _editCard(_CardData card, List<String> columns) async {
    final cardId = card['id']?.toString() ?? '';
    if (cardId.isEmpty) return;

    final next = await showDialog<_CardData>(
      context: context,
      builder:
          (dialogContext) => _KanbanCardEditorDialog(
            card: card,
            columns: columns,
            palette: _columnColorPalette(dialogContext.appColors),
          ),
    );
    if (next == null) return;
    _updateCard(cardId, next);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final columns = _columns;
    final query = _searchQuery;
    final cards = query.isEmpty
        ? _cards
        : _cards.where((c) {
            final title = (c['title'] as String? ?? '').toLowerCase();
            final description = (c['description'] as String? ?? '').toLowerCase();
            return title.contains(query) || description.contains(query);
          }).toList();

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        final isCtrl = HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        if (isCtrl &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyV) {
          _pasteFromClipboard();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => _focusNode.requestFocus(),
        behavior: HitTestBehavior.translucent,
        child: Container(
          color: colors.background,
          child: Column(
            children: [
              // ── Top bar with edit toggle and paste ──
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_searchActive) ...[
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          autofocus: true,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Search cards…',
                            hintStyle: TextStyle(
                              fontSize: 11,
                              color: colors.textMuted,
                            ),
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            suffixIcon: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _searchCtrl,
                              builder: (context, value, child) {
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (value.text.isNotEmpty)
                                      Tooltip(
                                        message: 'Clear search',
                                        child: InkWell(
                                          onTap: _clearSearch,
                                          borderRadius: BorderRadius.circular(6),
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.clear,
                                              size: 14,
                                              color: colors.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    Tooltip(
                                      message: 'Close search',
                                      child: InkWell(
                                        onTap: _closeSearch,
                                        borderRadius: BorderRadius.circular(6),
                                        child: Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Icon(
                                            Icons.close,
                                            size: 14,
                                            color: colors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                    ] else if (_editMode) ...[
                      Icon(Icons.tune, size: 12, color: colors.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Edit columns',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _editMode = false),
                        child: Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ] else ...[
                      Tooltip(
                        message: 'Search cards',
                        child: InkWell(
                          onTap: () => setState(() => _searchActive = true),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.search,
                              size: 14,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Edit columns',
                        child: InkWell(
                          onTap: () => setState(() => _editMode = true),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.tune,
                              size: 14,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int ci = 0; ci < columns.length; ci++) ...[
                          _buildColumn(ci, columns, cards),
                          const SizedBox(width: 8),
                        ],
                        // Add column button
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Tooltip(
                            message: 'Add column',
                            child: InkWell(
                              onTap: _addColumn,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  border: Border.all(color: colors.border),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.add,
                                  size: 16,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);
  }

  Widget _buildColumn(int ci, List<String> columns, List<_CardData> allCards) {
    final colCards =
        allCards.where((c) => (c['columnIndex'] as int?) == ci).toList();
    final isDragOver = _dragOverCol == ci;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        setState(() => _dragOverCol = null);
        _moveCardToColumn(details.data, ci);
      },
      onLeave: (_) => setState(() => _dragOverCol = null),
      onMove: (_) => setState(() => _dragOverCol = ci),
      builder: (ctx, candidateData, rejectedData) {
        final colors = ctx.appColors;
        final color = _colColor(ci);
        final isLight = Theme.of(ctx).brightness == Brightness.light;
        final colBg = isLight ? colors.surfaceHighlight : colors.surface;
        final border = colors.border;
        final inputBg = isLight ? colors.surfaceHighlight : colors.background;
        return Container(
          width: 180,
          decoration: BoxDecoration(
            color: isDragOver ? color.withAlpha(20) : colBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDragOver ? color.withAlpha(100) : border,
              width: isDragOver ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Column header ──────────────────────────────────────────
              _buildColumnHeader(ci, columns, colCards.length),
              Divider(height: 1, color: border),
              // ── Cards ──────────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      children: [
                        ...colCards.map(
                          (card) => _buildCard(card, ci, columns.length),
                        ),
                        // Inline add field
                        if (_adding[ci] == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: TextField(
                              controller: _addCtrl.putIfAbsent(
                                ci,
                                () => TextEditingController(),
                              ),
                              autofocus: true,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                hintText: 'Card title…',
                                hintStyle: const TextStyle(fontSize: 12),
                                isDense: true,
                                filled: true,
                                fillColor: inputBg,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: colors.primary),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                    color: colors.primary.withAlpha(100),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: colors.primary),
                                ),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.check, size: 14),
                                  color: colors.primary,
                                  onPressed: () => _addCard(ci),
                                ),
                              ),
                              onSubmitted: (_) => _addCard(ci),
                            ),
                          ),
                        // Drop indicator when dragging over empty column
                        if (isDragOver && colCards.isEmpty)
                          Container(
                            height: 48,
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: colors.primary.withAlpha(15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: colors.primary.withAlpha(80),
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.add,
                                size: 16,
                                color: colors.primary.withAlpha(150),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildColumnHeader(int ci, List<String> columns, int cardCount) {
    final colors = context.appColors;
    final baseColor = _colColor(ci);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final color =
        isLight && baseColor.computeLuminance() > 0.50
            ? Color.lerp(baseColor, colors.textPrimary, 0.45)!
            : (isLight && baseColor.computeLuminance() > 0.40)
            ? Color.lerp(baseColor, colors.textPrimary, 0.25)!
            : baseColor;
    final muted =
        context.appColors.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Move left (edit mode only)
              if (_editMode && ci > 0)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.chevron_left, size: 14, color: color),
                    tooltip: 'Move left',
                    onPressed: () => _moveColumn(ci, ci - 1),
                  ),
                ),
              // Name (editable on double-tap)
              Expanded(
                child:
                    _renamingCol == ci
                        ? TextField(
                          controller: _renameCtrl,
                          autofocus: true,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 2,
                              horizontal: 4,
                            ),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (v) => _renameColumn(ci, v),
                          onEditingComplete:
                              () => _renameColumn(ci, _renameCtrl.text),
                        )
                        : GestureDetector(
                          onDoubleTap: () {
                            _renameCtrl.text = columns[ci];
                            setState(() => _renamingCol = ci);
                          },
                          child: Text(
                            columns[ci],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
              ),
              // Move right (edit mode only)
              if (_editMode && ci < columns.length - 1)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.chevron_right, size: 14, color: color),
                    tooltip: 'Move right',
                    onPressed: () => _moveColumn(ci, ci + 1),
                  ),
                ),
              // Count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withAlpha(isLight ? 45 : 30),
                  border: Border.all(
                    color: color.withAlpha(isLight ? 75 : 45),
                    width: 0.6,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$cardCount',
                  style: TextStyle(fontSize: 10, color: color),
                ),
              ),
              const SizedBox(width: 4),
              // Add card button
              SizedBox(
                width: 20,
                height: 20,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.add, size: 13, color: color),
                  tooltip: 'Add card',
                  onPressed: () {
                    _addCtrl.putIfAbsent(ci, () => TextEditingController());
                    setState(() => _adding[ci] = true);
                  },
                ),
              ),
              // Edit mode toggle (on first column header only, when not in edit mode)
              if (!_editMode && ci == 0)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.tune, size: 13, color: muted),
                    tooltip: 'Edit columns',
                    onPressed: () => setState(() => _editMode = true),
                  ),
                ),
              // Delete column (edit mode only, not the last one)
              if (_editMode && _columns.length > 1)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.remove, size: 13, color: muted),
                    tooltip: 'Delete column',
                    onPressed: () => _deleteColumn(ci),
                  ),
                ),
            ],
          ),
          // ── Color picker row (edit mode only) ──
          if (_editMode)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children:
                    _columnColorPalette(colors).map((c) {
                      final isSelected = c.toARGB32() == color.toARGB32();
                      return GestureDetector(
                        onTap: () => _setColumnColor(ci, c),
                        child: Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.only(right: 3),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  isSelected
                                      ? colors.textPrimary
                                      : Colors.transparent,
                              width: isSelected ? 1.5 : 0,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCard(_CardData card, int ci, int totalCols) {
    final colors = context.appColors;
    final id = card['id'] as String? ?? '';
    final title = card['title'] as String? ?? '';
    final description = card['description'] as String? ?? '';
    final color = _cardColor(card);
    final columns = _columns;

    return Draggable<String>(
      data: id,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 168,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.primary.withAlpha(40),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.primary.withAlpha(150)),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withAlpha(60),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: colors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _CardTile(
          title: title,
          description: description,
          color: color,
          onEdit: () {},
          onDelete: () {},
        ),
      ),
      child: _CardTile(
        title: title,
        description: description,
        color: color,
        onEdit: () => _editCard(card, columns),
        onDelete: () => _deleteCard(id),
        onSendToChat: () => _sendCardToChat(context, card),
      ),
    );
  }

  void _sendCardToChat(BuildContext context, _CardData card) {
    final board = context.read<BoardCubit>().state.activeBoard;
    if (board == null) return;
    final chatPanels =
        board.panels.where((p) => p.type == ChatPanelPlugin.kTypeId).toList();
    if (chatPanels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No chat panels on this board')),
      );
      return;
    }

    final title = card['title']?.toString().trim() ?? '';
    final description = card['description']?.toString().trim() ?? '';
    final cardText = <String>[if (title.isNotEmpty) title, if (description.isNotEmpty) description].join('\n\n');

    if (chatPanels.length == 1) {
      BoardEventBus.instance.emit(
        KanbanCardToChatEvent(chatPanels.first.id, cardText),
      );
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final position = renderBox != null && overlay != null
        ? RelativeRect.fromRect(
            Rect.fromPoints(
              renderBox.localToGlobal(Offset.zero, ancestor: overlay),
              renderBox.localToGlobal(
                renderBox.size.bottomRight(Offset.zero),
                ancestor: overlay,
              ),
            ),
            Offset.zero & overlay.size,
          )
        : RelativeRect.fill;

    showMenu<String>(
      context: context,
      position: position,
      items: [
        for (final panel in chatPanels)
          PopupMenuItem<String>(
            value: panel.id,
            child: Text(panel.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
    ).then((selectedId) {
      if (selectedId == null) return;
      BoardEventBus.instance.emit(
        KanbanCardToChatEvent(selectedId, cardText),
      );
    });
  }

  Color? _cardColor(_CardData card) {
    final raw = card['color']?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final normalized =
        raw.startsWith('#')
            ? raw.substring(1)
            : raw.startsWith('0x')
            ? raw.substring(2)
            : raw;
    final hex = normalized.length == 6 ? 'ff$normalized' : normalized;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card tile widget
// ─────────────────────────────────────────────────────────────────────────────

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.title,
    required this.description,
    required this.color,
    required this.onEdit,
    required this.onDelete,
    this.onSendToChat,
  });

  final String title;
  final String description;
  final Color? color;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSendToChat;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cardBg = isLight ? colors.surfaceHighlight : colors.surfaceElevated;
    final border = colors.border;
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ?? colors.textSecondary;
    final muted =
        context.appColors.textMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onEdit,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color:
              color == null
                  ? cardBg
                  : Color.lerp(cardBg, color, isLight ? 0.12 : 0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color ?? border),
          boxShadow: [
            BoxShadow(
              color: colors.textPrimary.withValues(
                alpha: isLight ? 0.06 : 0.15,
              ),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 1),
              child: Icon(Icons.drag_indicator, size: 12, color: muted),
            ),
            // Title + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: textColor,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (description.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(fontSize: 10, color: muted),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Send to chat
            if (onSendToChat != null)
              SizedBox(
                width: 18,
                height: 18,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Send to chat',
                  icon: Icon(Icons.send_outlined, size: 11, color: muted),
                  onPressed: onSendToChat,
                ),
              ),
            // Delete
            SizedBox(
              width: 18,
              height: 18,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.close, size: 11, color: muted),
                onPressed: onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KanbanCardEditorDialog extends StatefulWidget {
  const _KanbanCardEditorDialog({
    required this.card,
    required this.columns,
    required this.palette,
  });

  final _CardData card;
  final List<String> columns;
  final List<Color> palette;

  @override
  State<_KanbanCardEditorDialog> createState() =>
      _KanbanCardEditorDialogState();
}

class _KanbanCardEditorDialogState extends State<_KanbanCardEditorDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descriptionCtrl;
  late final FocusNode _descriptionFocusNode;
  late int _columnIndex;
  Color? _color;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(
      text: widget.card['title']?.toString() ?? '',
    );
    _descriptionCtrl = TextEditingController(
      text: widget.card['description']?.toString() ?? '',
    );
    _descriptionFocusNode = FocusNode();
    _columnIndex = _readColumnIndex(widget.card);
    _color = _readColor(widget.card['color']);
    if (_titleCtrl.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _descriptionFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleDescriptionPaste() async {
    try {
      final pasted = await SmartClipboardPasteService.instance
          .readInlineTextOrSavedFilePath(allowInlineText: true);
      if (pasted == null || !mounted) return;
      _insertTextAtCursor(_descriptionCtrl, pasted);
    } catch (e) {
      assert(() {
        debugPrint('[KanbanCardEditor] Smart paste error: $e');
        return true;
      }());
    }
  }

  void _insertTextAtCursor(
    TextEditingController controller,
    String insertion,
  ) {
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.start >= 0 ? selection.start : 0;
    final end = selection.end >= 0 ? selection.end : start;
    final newText = text.replaceRange(start, end, insertion);
    final newOffset = start + insertion.length;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }

  int _readColumnIndex(_CardData card) {
    if (widget.columns.isEmpty) return 0;
    final raw = card['columnIndex'];
    final value =
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '') ?? 0;
    return value.clamp(0, widget.columns.length - 1);
  }

  Color? _readColor(Object? rawColor) {
    final raw = rawColor?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final normalized =
        raw.startsWith('#')
            ? raw.substring(1)
            : raw.startsWith('0x')
            ? raw.substring(2)
            : raw;
    final hex = normalized.length == 6 ? 'ff$normalized' : normalized;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value);
  }

  String _colorHex(Color color) =>
      '#${(color.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  void _save() {
    final title = _titleCtrl.text.trim();
    Navigator.of(context).pop(<String, dynamic>{
      'title': title.isEmpty ? 'Untitled card' : title,
      'description': _descriptionCtrl.text.trim(),
      'columnIndex': _columnIndex,
      if (_color == null) 'color': '' else 'color': _colorHex(_color!),
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final size = MediaQuery.sizeOf(context);
    final dialogWidth = (size.width - 96).clamp(640.0, 920.0);
    final dialogHeight = (size.height - 96).clamp(520.0, 820.0);

    return Dialog(
      backgroundColor: colors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.view_kanban_outlined,
                    size: 20,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Edit kanban card',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.divider),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      autofocus: _titleCtrl.text.trim().isEmpty,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      onSubmitted:
                          (_) => _descriptionFocusNode.requestFocus(),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: MarkdownEditorPane(
                        controller: _descriptionCtrl,
                        focusNode: _descriptionFocusNode,
                        hintText:
                            'Details, links, acceptance criteria… (Markdown)',
                        onPaste: _handleDescriptionPaste,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: colors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.columns.isNotEmpty) ...[
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<int>(
                            initialValue: _columnIndex,
                            decoration: const InputDecoration(
                              labelText: 'Column',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (var i = 0; i < widget.columns.length; i++)
                                DropdownMenuItem<int>(
                                  value: i,
                                  child: Text(widget.columns[i]),
                                ),
                            ],
                            onChanged:
                                (value) => setState(
                                  () => _columnIndex = value ?? _columnIndex,
                                ),
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Label color',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _ColorChoice(
                                  label: 'None',
                                  selected: _color == null,
                                  color: colors.surfaceElevated,
                                  onTap: () => setState(() => _color = null),
                                ),
                                for (final color in widget.palette)
                                  _ColorChoice(
                                    color: color,
                                    selected:
                                        _color?.toARGB32() == color.toARGB32(),
                                    onTap: () => setState(() => _color = color),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  EditorDialogActions(
                    onApply: _save,
                    applyLabel: 'Save',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
    this.label,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 28,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 4 : 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? colors.primary : colors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: colors.border),
              ),
            ),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(
                label!,
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
