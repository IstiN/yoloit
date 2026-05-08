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
  Size get defaultSize => const Size(560, 380);

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

class _KanbanContent extends StatefulWidget {
  const _KanbanContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_KanbanContent> createState() => _KanbanContentState();
}

class _KanbanContentState extends State<_KanbanContent> {
  static const Color _accent = Color(0xFF6366F1);

  List<String> get _columns =>
      (widget.panel.state['columns'] as List?)
          ?.map((e) => e.toString())
          .toList() ??
      ['Backlog', 'Todo', 'In Progress', 'Done'];

  List<Map<String, dynamic>> get _cards =>
      (widget.panel.state['cards'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList() ??
      [];

  // per-column "adding" state
  late final List<bool> _adding;
  late final List<TextEditingController> _addCtrl;

  @override
  void initState() {
    super.initState();
    final cols = _columns;
    _adding = List.filled(cols.length, false);
    _addCtrl = List.generate(cols.length, (_) => TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _addCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  void _save(List<Map<String, dynamic>> newCards) {
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'cards': newCards,
    });
  }

  void _addCard(int colIndex) {
    final title = _addCtrl[colIndex].text.trim();
    if (title.isEmpty) {
      setState(() => _adding[colIndex] = false);
      return;
    }
    final newCards = List<Map<String, dynamic>>.from(_cards)
      ..add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'title': title,
        'description': '',
        'columnIndex': colIndex,
      });
    _addCtrl[colIndex].clear();
    setState(() => _adding[colIndex] = false);
    _save(newCards);
  }

  void _moveCard(String id, int delta) {
    final cols = _columns;
    final cards = _cards;
    final idx = cards.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    final colIndex = (cards[idx]['columnIndex'] as int? ?? 0) + delta;
    if (colIndex < 0 || colIndex >= cols.length) return;
    final updated = List<Map<String, dynamic>>.from(cards);
    updated[idx] = {...updated[idx], 'columnIndex': colIndex};
    _save(updated);
  }

  void _deleteCard(String id) {
    _save(_cards.where((c) => c['id'] != id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final columns = _columns;
    final cards = _cards;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(columns.length, (ci) {
          final colCards = cards.where((c) => (c['columnIndex'] as int?) == ci).toList();
          return Container(
            width: 160,
            margin: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Column header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          columns[ci],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF6366F1),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${colCards.length}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6366F1)),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.add, size: 14, color: Color(0xFF6366F1)),
                          onPressed: () => setState(() {
                            _adding[ci] = true;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Cards
                ...colCards.map((card) => _CardTile(
                  card: card,
                  colIndex: ci,
                  totalCols: columns.length,
                  onMoveLeft: () => _moveCard(card['id'] as String, -1),
                  onMoveRight: () => _moveCard(card['id'] as String, 1),
                  onDelete: () => _deleteCard(card['id'] as String),
                )),
                // Inline add field
                if (_adding[ci])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: TextField(
                      controller: _addCtrl[ci],
                      autofocus: true,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Card title…',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.check, size: 14),
                          onPressed: () => _addCard(ci),
                        ),
                      ),
                      onSubmitted: (_) => _addCard(ci),
                      onEditingComplete: () => _addCard(ci),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.colIndex,
    required this.totalCols,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onDelete,
  });

  final Map<String, dynamic> card;
  final int colIndex;
  final int totalCols;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = card['title'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (colIndex > 0)
                _tinyBtn(Icons.chevron_left, onMoveLeft)
              else
                const SizedBox(width: 20),
              _tinyBtn(Icons.close, onDelete, color: Colors.redAccent),
              if (colIndex < totalCols - 1)
                _tinyBtn(Icons.chevron_right, onMoveRight)
              else
                const SizedBox(width: 20),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tinyBtn(IconData icon, VoidCallback onTap, {Color? color}) {
    return SizedBox(
      width: 20,
      height: 20,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 13, color: color ?? const Color(0xFF94A3B8)),
        onPressed: onTap,
      ),
    );
  }
}
