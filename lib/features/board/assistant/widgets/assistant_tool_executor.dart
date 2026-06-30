import 'dart:convert';

import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

/// Wraps the base CLI tool executor with assistant-specific pre/post processing
/// (note retargeting, panel creation guard, focus after create).
class AssistantToolExecutor implements YoloitToolExecutor {
  AssistantToolExecutor({
    required this.delegate,
    required this.assistantPanelId,
    required this.assistantPanelTitle,
    this.targetPanelId,
    required this.onFocusPanel,
  });

  final YoloitToolExecutor delegate;
  final String assistantPanelId;
  final String assistantPanelTitle;
  final String? targetPanelId;
  final Future<void> Function(Map<String, Object?> focusArgs) onFocusPanel;

  // Mutable per-message state — set before each sendMessage call.
  String? lastTargetNotePanelId;
  String userMessage = '';
  void Function(
    String toolCommand,
    Map<String, Object?> arguments,
    String result,
    bool success,
  )?
  onToolCompleted;

  @override
  Future<String> invoke(
    String functionName,
    Map<String, Object?> arguments, {
    ChatRuntimeContext? runtimeContext,
    bool argumentsPreNormalized = false,
  }) async {
    final tool = YoloitCliToolCatalog.byFunctionName(functionName);
    final toolCommand = tool?.command ?? functionName;
    final mutableArgs = Map<String, Object?>.from(arguments);

    // Default panel-argument tools to the focus panel when the user did not
    // name one explicitly.
    _retargetToFocusPanelIfNeeded(toolCommand, mutableArgs);

    await _retargetPanelLookupToRealNoteIfNeeded(
      toolCommand,
      mutableArgs,
      runtimeContext,
    );

    // Retarget note tools to last known note panel.
    _retargetNoteToolIfNeeded(toolCommand, mutableArgs);

    // Guard: if note tool points to assistant panel, retarget to a real note panel.
    await _ensureNoteToolHasRealPanel(toolCommand, mutableArgs, runtimeContext);

    final result = await delegate.invoke(
      functionName,
      mutableArgs,
      runtimeContext: runtimeContext,
      argumentsPreNormalized: argumentsPreNormalized,
    );

    final success = _toolResultSucceeded(result);
    onToolCompleted?.call(toolCommand, mutableArgs, result, success);

    // Auto-focus newly created panels.
    if (toolCommand == 'panel:create' && success && runtimeContext != null) {
      final created = _createdPanelFromResult(result);
      if (created != null) {
        final board =
            '${mutableArgs['board'] ?? runtimeContext.boardId ?? runtimeContext.boardName ?? ''}'
                .trim();
        if (board.isNotEmpty) {
          await onFocusPanel({'board': board, 'panel': created.id});
        }
      }
    }

    return result;
  }

  void _retargetToFocusPanelIfNeeded(
    String toolCommand,
    Map<String, Object?> arguments,
  ) {
    final focusId = targetPanelId?.trim();
    if (focusId == null || focusId.isEmpty) return;
    // Board-level and create commands should not be defaulted to a focus panel.
    if (toolCommand.startsWith('board') || toolCommand == 'panel:create') return;
    final panel = '${arguments['panel'] ?? ''}'.trim();
    if (panel.isNotEmpty) return;
    arguments['panel'] = focusId;
  }

  void _retargetNoteToolIfNeeded(
    String toolCommand,
    Map<String, Object?> arguments,
  ) {
    if (toolCommand != 'note' && !toolCommand.startsWith('note:')) return;
    if (toolCommand == 'note:create') return;
    final lastPanelId = lastTargetNotePanelId?.trim();
    if (lastPanelId == null || lastPanelId.isEmpty) return;
    final panel = '${arguments['panel'] ?? ''}'.trim();
    final shouldRetarget =
        panel.isEmpty ||
        panel == assistantPanelId ||
        panel == assistantPanelTitle ||
        _mentionsPreviousNote(userMessage);
    if (shouldRetarget) {
      arguments['panel'] = lastPanelId;
    }
  }

  Future<void> _ensureNoteToolHasRealPanel(
    String toolCommand,
    Map<String, Object?> arguments,
    ChatRuntimeContext? runtimeContext,
  ) async {
    if (toolCommand != 'note' && !toolCommand.startsWith('note:')) return;
    if (toolCommand == 'note:create') return;
    final panel = '${arguments['panel'] ?? ''}'.trim();
    if (panel.isEmpty ||
        panel == assistantPanelId ||
        panel == assistantPanelTitle) {
      final lastPanelId = lastTargetNotePanelId?.trim();
      if (lastPanelId != null && lastPanelId.isNotEmpty) {
        arguments['panel'] = lastPanelId;
        return;
      }
      final resolved = await _resolveNoteTarget(runtimeContext);
      if (resolved != null) {
        arguments['panel'] = resolved.panelId;
        arguments['board'] = resolved.boardId;
      }
    }
  }

  Future<void> _retargetPanelLookupToRealNoteIfNeeded(
    String toolCommand,
    Map<String, Object?> arguments,
    ChatRuntimeContext? runtimeContext,
  ) async {
    final isPanelLookup =
        toolCommand == 'panel' || toolCommand == 'panel:focus';
    if (!isPanelLookup || !_looksLikeNoteLookupIntent(userMessage)) return;
    final panel = '${arguments['panel'] ?? ''}'.trim();
    if (panel.isNotEmpty &&
        panel != assistantPanelId &&
        panel != assistantPanelTitle) {
      return;
    }
    final resolved = await _resolveNoteTarget(runtimeContext);
    if (resolved == null) return;
    arguments['board'] = resolved.boardId;
    arguments['panel'] = resolved.panelId;
  }

  bool _looksLikeNoteLookupIntent(String msg) {
    final text = msg.toLowerCase();
    return text.contains('замет') ||
        text.contains('note') ||
        text.contains('mermaid') ||
        text.contains('diagram') ||
        text.contains('диаграм') ||
        text.contains('покажи') ||
        text.contains('show');
  }

  Future<({String boardId, String panelId})?> _resolveNoteTarget(
    ChatRuntimeContext? runtimeContext,
  ) async {
    final tokens = _searchTokens(userMessage);
    final hintedBoardId = (runtimeContext?.boardId ?? '').trim();
    try {
      final boardsRaw = await delegate.invoke(
        'yoloit_boards',
        const <String, Object?>{},
        runtimeContext: runtimeContext,
      );
      final boardsDecoded = jsonDecode(boardsRaw);
      if (boardsDecoded is! Map) return null;
      final boards = boardsDecoded['boards'];
      if (boards is! List) return null;

      ({String boardId, String panelId, int score, num zIndex})? best;
      for (final b in boards) {
        if (b is! Map) continue;
        final boardMap = Map<String, Object?>.from(b.cast<String, Object?>());
        final boardId = '${boardMap['id'] ?? ''}'.trim();
        if (boardId.isEmpty) continue;
        final panelsRaw = await delegate.invoke('yoloit_panels', {
          'id_or_name': boardId,
        }, runtimeContext: runtimeContext);
        final panelsDecoded = jsonDecode(panelsRaw);
        if (panelsDecoded is! Map) continue;
        final panels = panelsDecoded['panels'];
        if (panels is! List) continue;
        for (final p in panels) {
          if (p is! Map) continue;
          final panel = Map<String, Object?>.from(p.cast<String, Object?>());
          if (panel['type'] != 'board.note.markdown' ||
              panel['hidden'] == true) {
            continue;
          }
          final panelId = '${panel['id'] ?? ''}'.trim();
          if (panelId.isEmpty) continue;
          final title = '${panel['title'] ?? ''}'.toLowerCase();
          final zIndex = (panel['zIndex'] as num?) ?? 0;
          var score = 0;
          if (boardId == hintedBoardId) score += 2;
          if (title.contains('mermaid') ||
              title.contains('diagram') ||
              title.contains('диаграм')) {
            score += 3;
          }
          for (final token in tokens) {
            if (token.length < 3) continue;
            if (title.contains(token)) score += 2;
          }

          if (score < 4 && tokens.isNotEmpty) {
            try {
              final detailsRaw = await delegate.invoke('yoloit_panel', {
                'board': boardId,
                'panel': panelId,
              }, runtimeContext: runtimeContext);
              final details = jsonDecode(detailsRaw);
              if (details is Map) {
                final markdown =
                    '${(details['state'] as Map?)?['markdown'] ?? (details['content'] as Map?)?['markdown'] ?? ''}'
                        .toLowerCase();
                for (final token in tokens) {
                  if (token.length < 3) continue;
                  if (markdown.contains(token)) score += 2;
                }
              }
            } catch (_) {}
          }

          if (best == null ||
              score > best.score ||
              (score == best.score && zIndex > best.zIndex)) {
            best = (
              boardId: boardId,
              panelId: panelId,
              score: score,
              zIndex: zIndex,
            );
          }
        }
      }
      if (best == null) return null;
      return (boardId: best.boardId, panelId: best.panelId);
    } catch (_) {
      return null;
    }
  }

  Set<String> _searchTokens(String text) {
    final lower = text.toLowerCase();
    final parts = lower.split(RegExp(r'[^a-zа-я0-9_]+'));
    const skip = {
      'сделай',
      'покажи',
      'найди',
      'фокус',
      'focus',
      'show',
      'note',
      'заметку',
      'заметка',
      'на',
      'борде',
      'with',
      'for',
      'the',
      'and',
    };
    return parts.where((p) => p.isNotEmpty && !skip.contains(p)).toSet();
  }

  bool _mentionsPreviousNote(String msg) {
    final text = msg.toLowerCase();
    return text.contains('в нее') ||
        text.contains('в неё') ||
        text.contains('туда') ||
        text.contains('заметк') ||
        text.contains('note');
  }

  bool _toolResultSucceeded(String result) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map && decoded['ok'] is bool) {
        return decoded['ok'] as bool;
      }
    } catch (_) {}
    return true;
  }

  ({String id, String title})? _createdPanelFromResult(String result) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is! Map) return null;
      final stdout = decoded['stdout'];
      final payload = stdout is String ? jsonDecode(stdout) : decoded;
      if (payload is! Map) return null;
      final panel = payload['panel'];
      if (panel is! Map) return null;
      final id = '${panel['id'] ?? ''}'.trim();
      final title = '${panel['title'] ?? id}'.trim();
      if (id.isEmpty) return null;
      return (id: id, title: title.isEmpty ? id : title);
    } catch (_) {
      return null;
    }
  }
}
