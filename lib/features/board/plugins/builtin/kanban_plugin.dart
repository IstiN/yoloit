import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

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
  Color get accentColor => const Color(0xFF6366F1);

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
  static const Color _accent = Color(0xFF6366F1);
  static const Color _bg = Color(0xFF0B0D12);
  static const Color _colBg = Color(0xFF141821);
  static const Color _border = Color(0xFF2A3040);

  // ── State helpers ──────────────────────────────────────────────────────────

  List<String> get _columns =>
      (widget.panel.state['columns'] as List?)
          ?.map((e) => e.toString())
          .toList() ??
      ['Backlog', 'Todo', 'In Progress', 'Done'];

  List<_CardData> get _cards =>
      (widget.panel.state['cards'] as List?)
          ?.whereType<_CardData>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList() ??
      [];

  // ── Local UI state ─────────────────────────────────────────────────────────

  // per-column add-card controllers
  final Map<int, TextEditingController> _addCtrl = {};
  final Map<int, bool> _adding = {};

  // column rename
  int? _renamingCol;
  final _renameCtrl = TextEditingController();

  // drag highlight
  int? _dragOverCol;

  @override
  void dispose() {
    for (final c in _addCtrl.values) {
      c.dispose();
    }
    _renameCtrl.dispose();
    super.dispose();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  void _saveCards(List<_CardData> cards) {
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'cards': cards,
    });
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

  // ── Column actions ─────────────────────────────────────────────────────────

  void _addColumn() {
    final cols = List<String>.from(_columns)..add('New Column');
    _saveColumns(cols);
  }

  void _deleteColumn(int ci) {
    final cols = List<String>.from(_columns)..removeAt(ci);
    final cards =
        _cards
            .where((c) => (c['columnIndex'] as int? ?? 0) != ci)
            .map((c) {
              final old = c['columnIndex'] as int? ?? 0;
              return {...c, 'columnIndex': old > ci ? old - 1 : old};
            })
            .toList();
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
    final cards = _cards.map((c) {
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
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'columns': cols,
      'cards': cards,
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
    final cards = List<_CardData>.from(_cards)
      ..add({
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final columns = _columns;
    final cards = _cards;

    return Container(
      color: _bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Columns
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
                            border: Border.all(color: _border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.add,
                            size: 16,
                            color: Color(0xFF6366F1),
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
    );
  }

  Widget _buildColumn(
    int ci,
    List<String> columns,
    List<_CardData> allCards,
  ) {
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
        return Container(
          width: 180,
          decoration: BoxDecoration(
            color: isDragOver ? _accent.withAlpha(20) : _colBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDragOver ? _accent.withAlpha(100) : _border,
              width: isDragOver ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Column header ──────────────────────────────────────────
              _buildColumnHeader(ci, columns, colCards.length),
              const Divider(height: 1, color: Color(0xFF2A3040)),
              // ── Cards ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    ...colCards.map((card) => _buildCard(card, ci, columns.length)),
                    // Inline add field
                    if (_adding[ci] == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TextField(
                          controller:
                              _addCtrl.putIfAbsent(
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
                            fillColor: const Color(0xFF0B0D12),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: _accent),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: _accent.withAlpha(100),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: _accent),
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.check, size: 14),
                              color: _accent,
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
                          color: _accent.withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _accent.withAlpha(80),
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.add,
                            size: 16,
                            color: _accent.withAlpha(150),
                          ),
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

  Widget _buildColumnHeader(int ci, List<String> columns, int cardCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // Move left
          if (ci > 0)
            SizedBox(
              width: 20,
              height: 20,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.chevron_left, size: 14, color: Color(0xFF64748B)),
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
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _accent,
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
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _accent,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
          ),
          // Move right
          if (ci < columns.length - 1)
            SizedBox(
              width: 20,
              height: 20,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.chevron_right, size: 14, color: Color(0xFF64748B)),
                tooltip: 'Move right',
                onPressed: () => _moveColumn(ci, ci + 1),
              ),
            ),
          // Count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: _accent.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$cardCount',
              style: const TextStyle(fontSize: 10, color: _accent),
            ),
          ),
          const SizedBox(width: 4),
          // Add card button
          SizedBox(
            width: 20,
            height: 20,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.add, size: 13, color: _accent),
              tooltip: 'Add card',
              onPressed: () {
                _addCtrl.putIfAbsent(ci, () => TextEditingController());
                setState(() => _adding[ci] = true);
              },
            ),
          ),
          // Delete column (only if it's not the last one)
          if (_columns.length > 1)
            SizedBox(
              width: 20,
              height: 20,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.remove, size: 13, color: Color(0xFF64748B)),
                tooltip: 'Delete column',
                onPressed: () => _deleteColumn(ci),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCard(_CardData card, int ci, int totalCols) {
    final id = card['id'] as String? ?? '';
    final title = card['title'] as String? ?? '';

    return Draggable<String>(
      data: id,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 168,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _accent.withAlpha(40),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _accent.withAlpha(150)),
            boxShadow: [
              BoxShadow(
                color: _accent.withAlpha(60),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
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
          onDelete: () {},
        ),
      ),
      child: _CardTile(
        title: title,
        onDelete: () => _deleteCard(id),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card tile widget
// ─────────────────────────────────────────────────────────────────────────────

class _CardTile extends StatelessWidget {
  const _CardTile({required this.title, required this.onDelete});

  final String title;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2433),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A3040)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          const Padding(
            padding: EdgeInsets.only(right: 6, top: 1),
            child: Icon(
              Icons.drag_indicator,
              size: 12,
              color: Color(0xFF4B5563),
            ),
          ),
          // Title
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Color(0xFFE2E8F0),
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Delete
          SizedBox(
            width: 18,
            height: 18,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, size: 11, color: Color(0xFF4B5563)),
              onPressed: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}
