import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

/// Board panel plugin that displays run configurations (like an IDE run panel).
///
/// Left sidebar lists configs with colored status dots; right panel shows
/// terminal-like output for the active configuration.
class RunConfigsPlugin extends BoardPanelPlugin {
  const RunConfigsPlugin();

  static const String kTypeId = 'board.run_configs';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Run Configs';

  @override
  IconData get icon => Icons.play_circle_outline;

  @override
  Color get accentColor => const Color(0xFF22C55E);

  @override
  Size get defaultSize => const Size(600, 400);

  @override
  Map<String, dynamic> get initialState => {
    'configurations': <Map<String, dynamic>>[],
    'activeConfigId': '',
    'output': '',
    'isRunning': false,
  };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _RunConfigsContent(panel: panel, renderContext: renderContext);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Content widget
// ─────────────────────────────────────────────────────────────────────────────

class _RunConfigsContent extends StatefulWidget {
  const _RunConfigsContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_RunConfigsContent> createState() => _RunConfigsContentState();
}

class _RunConfigsContentState extends State<_RunConfigsContent> {
  static const Color _accent = Color(0xFF22C55E);

  // ── State helpers ──────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _configs =>
      (widget.panel.state['configurations'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList() ??
      [];

  String get _activeConfigId =>
      widget.panel.state['activeConfigId'] as String? ?? '';

  String get _output => widget.panel.state['output'] as String? ?? '';

  bool get _isRunning => widget.panel.state['isRunning'] as bool? ?? false;

  void _save(Map<String, dynamic> patch) {
    widget.renderContext.onUpdateState({...widget.panel.state, ...patch});
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _selectConfig(String id) {
    final config = _configs.firstWhere(
      (c) => c['id'] == id,
      orElse: () => <String, dynamic>{},
    );
    if (config.isEmpty) return;
    _save({'activeConfigId': id, 'output': config['output'] ?? ''});
  }

  void _removeConfig(String id) {
    final configs = _configs.where((c) => c['id'] != id).toList();
    final active = _activeConfigId == id ? '' : _activeConfigId;
    _save({
      'configurations': configs,
      'activeConfigId': active,
      if (active.isEmpty) 'output': '',
    });
  }

  void _toggleRun() {
    if (_activeConfigId.isEmpty) return;
    final configs = _configs;
    final idx = configs.indexWhere((c) => c['id'] == _activeConfigId);
    if (idx < 0) return;

    final config = configs[idx];
    final wasRunning = config['status'] == 'running';
    config['status'] = wasRunning ? 'idle' : 'running';
    if (!wasRunning) {
      config['output'] =
          '> ${config['command']}\nStarting in ${config['workingDir'] ?? '.'}\n';
    } else {
      config['output'] = '${config['output'] as String? ?? ''}\n[stopped]\n';
    }
    configs[idx] = config;
    _save({
      'configurations': configs,
      'isRunning': !wasRunning,
      'output': config['output'] as String? ?? '',
    });
  }

  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    final cmdCtrl = TextEditingController();
    final dirCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              title: const Text('Add Configuration'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        hintText: 'e.g. Flutter Run (macOS)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: cmdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Command',
                        hintText: 'e.g. flutter run -d macos',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: dirCtrl,
                      decoration: InputDecoration(
                        labelText: 'Working Directory',
                        hintText: '/path/to/project',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.folder_open, size: 20),
                          tooltip: 'Browse...',
                          onPressed: () async {
                            final picked = await FilePicker.getDirectoryPath(
                              dialogTitle: 'Select working directory',
                            );
                            if (picked != null) {
                              dirCtrl.text = picked;
                              setDialogState(() {});
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    final cmd = cmdCtrl.text.trim();
    if (name.isEmpty || cmd.isEmpty) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final newConfig = <String, dynamic>{
      'id': id,
      'name': name,
      'command': cmd,
      'workingDir': dirCtrl.text.trim(),
      'envVars': <String, String>{},
      'status': 'idle',
      'output': '',
    };
    _save({
      'configurations': [..._configs, newConfig],
      'activeConfigId': id,
      'output': '',
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final configs = _configs;
    final activeId = _activeConfigId;
    final activeConfig =
        configs
            .where((c) => c['id'] == activeId)
            .cast<Map<String, dynamic>?>()
            .firstOrNull;
    final colors = AppColorScheme.of(context);
    final borderColor = colors.border;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final textSecondary = textColor.withValues(alpha: 0.5);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Left sidebar ─────────────────────────────────────────────────
        SizedBox(
          width: 200,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: borderColor, width: 1),
              ),
            ),
            child: Column(
              children: [
                // Sidebar header
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Row(
                    children: [
                      Text(
                        '${configs.length} config${configs.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.5),
                // Config list
                Expanded(
                  child:
                      configs.isEmpty
                          ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.play_circle_outline,
                                  size: 36,
                                  color: _accent.withValues(alpha: 0.35),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'No configurations',
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          )
                          : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: configs.length,
                            itemBuilder: (_, i) {
                              final c = configs[i];
                              final id = c['id'] as String;
                              final name = c['name'] as String? ?? '';
                              final status = c['status'] as String? ?? 'idle';
                              final selected = id == activeId;
                              return _ConfigTile(
                                name: name,
                                status: status,
                                selected: selected,
                                onTap: () => _selectConfig(id),
                                onDelete: () => _removeConfig(id),
                              );
                            },
                          ),
                ),
                // Add button
                const Divider(height: 1, thickness: 0.5),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _showAddDialog,
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text(
                        '+ Add Configuration',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Right panel ──────────────────────────────────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top bar
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: borderColor, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        activeConfig != null
                            ? activeConfig['name'] as String? ?? ''
                            : 'No configuration selected',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (activeConfig != null) ...[
                      IconButton(
                        icon: Icon(
                          _isRunning ? Icons.stop : Icons.play_arrow,
                          size: 18,
                        ),
                        tooltip: _isRunning ? 'Stop' : 'Run',
                        onPressed: _toggleRun,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        color: _isRunning ? const Color(0xFFEF4444) : _accent,
                      ),
                      IconButton(
                        icon: const Icon(Icons.menu, size: 18),
                        tooltip: 'Options',
                        onPressed: () {},
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        color: textSecondary,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Close tab',
                        onPressed:
                            () => _save({'activeConfigId': '', 'output': ''}),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        color: textSecondary,
                      ),
                    ],
                  ],
                ),
              ),
              // Output area
              Expanded(
                child: Container(
                  color: colors.terminalBackground,
                  padding: const EdgeInsets.all(10),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _output.isEmpty
                          ? (activeConfig != null
                              ? 'Ready. Press ▶ to run.'
                              : 'Select a configuration to view output.')
                          : _output,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: colors.terminalPrompt,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Configuration list tile
// ─────────────────────────────────────────────────────────────────────────────

class _ConfigTile extends StatefulWidget {
  const _ConfigTile({
    required this.name,
    required this.status,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final String name;
  final String status;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_ConfigTile> createState() => _ConfigTileState();
}

class _ConfigTileState extends State<_ConfigTile> {
  bool _hovered = false;

  static Color _statusColor(String status) => switch (status) {
    'running' => const Color(0xFF22C55E),
    'success' => const Color(0xFFEAB308),
    'error' => const Color(0xFFEF4444),
    _ => const Color(0xFF64748B),
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final hoverColor = isDark
        ? Colors.white.withValues(alpha: 0.03)
        : Colors.black.withValues(alpha: 0.03);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color:
              widget.selected
                  ? selectColor
                  : _hovered
                  ? hoverColor
                  : Colors.transparent,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _statusColor(widget.status),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.name,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_hovered)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 14),
                  tooltip: 'Remove',
                  onPressed: widget.onDelete,
                  padding: const EdgeInsets.all(2),
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  color: Colors.redAccent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
