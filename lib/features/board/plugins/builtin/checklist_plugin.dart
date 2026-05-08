import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

class ChecklistPlugin extends BoardPanelPlugin {
  const ChecklistPlugin();

  static const String kTypeId = 'board.checklist';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Checklist';

  @override
  IconData get icon => Icons.checklist_outlined;

  @override
  Color get accentColor => const Color(0xFFF59E0B);

  @override
  Size get defaultSize => const Size(320, 320);

  @override
  Map<String, dynamic> get initialState => {
    'items': <Map<String, dynamic>>[],
    'title': '',
  };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _ChecklistContent(panel: panel, renderContext: renderContext);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ChecklistContent extends StatefulWidget {
  const _ChecklistContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_ChecklistContent> createState() => _ChecklistContentState();
}

class _ChecklistContentState extends State<_ChecklistContent> {
  static const Color _accent = Color(0xFFF59E0B);

  final TextEditingController _addCtrl = TextEditingController();

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _items =>
      (widget.panel.state['items'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList() ??
      [];

  void _save(List<Map<String, dynamic>> items) {
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'items': items,
    });
  }

  void _addItem() {
    final text = _addCtrl.text.trim();
    if (text.isEmpty) return;
    _addCtrl.clear();
    final newItems = List<Map<String, dynamic>>.from(_items)
      ..add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'text': text,
        'done': false,
      });
    _save(newItems);
  }

  void _toggle(String id) {
    final items = _items.map((item) {
      if (item['id'] == id) {
        return {...item, 'done': !(item['done'] as bool? ?? false)};
      }
      return item;
    }).toList();
    _save(items);
  }

  void _delete(String id) {
    _save(_items.where((i) => i['id'] != id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final done = items.where((i) => i['done'] == true).length;
    final total = items.length;
    final progress = total == 0 ? 0.0 : done / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Progress header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$done/$total done',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                  if (total > 0)
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: _accent.withOpacity(0.15),
                valueColor: const AlwaysStoppedAnimation(_accent),
                minHeight: 4,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5),
        // Items list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final id = item['id'] as String;
              final text = item['text'] as String? ?? '';
              final isDone = item['done'] as bool? ?? false;

              return _ChecklistItem(
                text: text,
                isDone: isDone,
                onToggle: () => _toggle(id),
                onDelete: () => _delete(id),
              );
            },
          ),
        ),
        const Divider(height: 1, thickness: 0.5),
        // Add item row
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _addCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Add item…',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 2),
                    ),
                  ),
                  onSubmitted: (_) => _addItem(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                onPressed: _addItem,
                icon: const Icon(Icons.add, size: 16),
                style: IconButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(34, 34),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChecklistItem extends StatefulWidget {
  const _ChecklistItem({
    required this.text,
    required this.isDone,
    required this.onToggle,
    required this.onDelete,
  });

  final String text;
  final bool isDone;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  State<_ChecklistItem> createState() => _ChecklistItemState();
}

class _ChecklistItemState extends State<_ChecklistItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: _hovered ? Colors.white.withOpacity(0.04) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: widget.isDone,
                onChanged: (_) => widget.onToggle(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                activeColor: const Color(0xFFF59E0B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.text,
                style: TextStyle(
                  fontSize: 13,
                  decoration: widget.isDone ? TextDecoration.lineThrough : null,
                  color: widget.isDone
                      ? const Color(0xFF64748B)
                      : null,
                ),
              ),
            ),
            if (_hovered)
              SizedBox(
                width: 22,
                height: 22,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close, size: 13, color: Color(0xFF94A3B8)),
                  onPressed: widget.onDelete,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
