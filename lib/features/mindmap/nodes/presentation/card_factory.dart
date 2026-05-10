import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

import 'package:yoloit/features/collaboration/ui/guest_terminal_view.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/presentation.dart';

/// Callback bundle for events that web guests can send back to the host.
class CardEventCallbacks {
  const CardEventCallbacks({
    this.onTerminalInput,
    this.onSessionStart,
    this.onRunStart,
    this.onRunStop,
    this.onRunRestart,
    this.onAddFolder,
    this.onCreateSession,
    this.onFileSelect,
    this.onTreeToggle,
    this.onTreeSelect,
    this.onEditorSwitchTab,
    this.onEditorSave,
    this.onEditorContentUpdate,
  });
  final void Function(String nodeId, String data)? onTerminalInput;
  final void Function(String nodeId)? onSessionStart;
  final void Function(String nodeId)? onRunStart;
  final void Function(String nodeId)? onRunStop;
  final void Function(String nodeId)? onRunRestart;
  final void Function(String nodeId)? onAddFolder;
  final void Function(String nodeId)? onCreateSession;
  final void Function(String nodeId, String path)? onFileSelect;
  final void Function(String nodeId, String path)? onTreeToggle;
  final void Function(String nodeId, String path)? onTreeSelect;
  final void Function(String nodeId, int tabIndex)? onEditorSwitchTab;
  final void Function(String nodeId)? onEditorSave;
  final void Function(String nodeId, String content)? onEditorContentUpdate;
}

/// Maps a `nodeContent` JSON map to the matching presentation card widget.
///
/// This is the single bridge between WebSocket data and the shared
/// presentation widgets — used by the web guest canvas.
Widget buildCardFromContent(
  String nodeId,
  Map<String, dynamic> content,
  CardEventCallbacks callbacks,
) {
  final type = (content['type'] as String?) ?? _typeFromId(nodeId);

  return switch (type) {
    'agent' => AgentCard(
        props: AgentCardProps.fromJson(content),
        // Live xterm view backed by the guest registry — raw PTY bytes arrive
        // over WebSocket and are piped straight into xterm.dart so rendering
        // (colors, box-drawing, scrollback, cursor) matches the native client.
        body: AgentCardProps.fromJson(content).isIdle
            ? null
            : GuestTerminalView(
                nodeId: nodeId,
                onInput: callbacks.onTerminalInput != null
                    ? (data) => callbacks.onTerminalInput!(nodeId, data)
                    : null,
              ),
        onTerminalInput: callbacks.onTerminalInput != null
            ? (data) => callbacks.onTerminalInput!(nodeId, data)
            : null,
        onSessionStart: callbacks.onSessionStart != null
            ? () => callbacks.onSessionStart!(nodeId)
            : null,
      ),
    'workspace' => WorkspaceCard(
        props: WorkspaceCardProps.fromJson(content),
        onAddFolder: callbacks.onAddFolder != null
            ? () => callbacks.onAddFolder!(nodeId)
            : null,
        onCreateSession: callbacks.onCreateSession != null
            ? () => callbacks.onCreateSession!(nodeId)
            : null,
      ),
    'repo' => RepoCard(props: RepoCardProps.fromJson(content)),
    'branch' => BranchCard(props: BranchCardProps.fromJson(content)),
    'run' => RunCard(
        props: RunCardProps.fromJson(content),
        onStart: callbacks.onRunStart != null
            ? () => callbacks.onRunStart!(nodeId)
            : null,
        onStop: callbacks.onRunStop != null
            ? () => callbacks.onRunStop!(nodeId)
            : null,
        onRestart: callbacks.onRunRestart != null
            ? () => callbacks.onRunRestart!(nodeId)
            : null,
      ),
    'editor' => EditorCard(
        props: EditorCardProps.fromJson(content),
        onSwitchTab: callbacks.onEditorSwitchTab != null
            ? (idx) => callbacks.onEditorSwitchTab!(nodeId, idx)
            : null,
        onSave: callbacks.onEditorSave != null
            ? () => callbacks.onEditorSave!(nodeId)
            : null,
        onContentUpdate: callbacks.onEditorContentUpdate != null
            ? (text) => callbacks.onEditorContentUpdate!(nodeId, text)
            : null,
      ),
    'files' => FilesCard(
        props: FilesCardProps.fromJson(content),
        onFileSelect: callbacks.onFileSelect != null
            ? (path) => callbacks.onFileSelect!(nodeId, path)
            : null,
      ),
    'tree' => FileTreeCard(
        props: FileTreeCardProps.fromJson(content),
        onToggle: callbacks.onTreeToggle != null
            ? (path) => callbacks.onTreeToggle!(nodeId, path)
            : null,
        onSelect: callbacks.onTreeSelect != null
            ? (path) => callbacks.onTreeSelect!(nodeId, path)
            : null,
      ),
    'diff' => DiffCard(props: DiffCardProps.fromJson(content)),
    'session' => SessionCard(props: SessionCardProps.fromJson(content)),
    _ => _FallbackCard(nodeId: nodeId, content: content),
  };
}

String _typeFromId(String id) {
  final i = id.indexOf(':');
  return i < 0 ? 'node' : id.substring(0, i);
}

class _FallbackCard extends StatelessWidget {
  const _FallbackCard({required this.nodeId, required this.content});
  final String nodeId;
  final Map<String, dynamic> content;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(nodeId,
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface,
                  fontFamily: 'monospace')),
          const SizedBox(height: 4),
          for (final e in content.entries.where((e) => e.value is String))
            Text('${e.key}: ${e.value}',
                style: TextStyle(
                    fontSize: 10, color: Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }
}
