import 'dart:convert';

import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

/// A scored (board, panel) candidate produced by the target resolvers.
typedef _PanelCandidate = ({
  String boardId,
  String panelId,
  int score,
  num zIndex,
});

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

    await _retargetTerminalToolIfNeeded(
      toolCommand,
      mutableArgs,
      runtimeContext,
    );

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
    if (_isTerminalToolCommand(toolCommand)) return;
    final panel = '${arguments['panel'] ?? ''}'.trim();
    if (panel.isNotEmpty) return;
    arguments['panel'] = focusId;
  }

  bool _isTerminalToolCommand(String toolCommand) {
    return toolCommand == 'terminal:output' ||
        toolCommand == 'terminal:config' ||
        toolCommand == 'terminal:set-dir' ||
        toolCommand == 'terminal:set-session' ||
        toolCommand == 'run:list' ||
        toolCommand == 'run:output' ||
        toolCommand == 'run:input';
  }

  Future<void> _retargetTerminalToolIfNeeded(
    String toolCommand,
    Map<String, Object?> arguments,
    ChatRuntimeContext? runtimeContext,
  ) async {
    if (!_isTerminalToolCommand(toolCommand)) return;
    final panel = '${arguments['panel'] ?? ''}'.trim();
    if (panel.isNotEmpty &&
        panel != assistantPanelId &&
        panel != assistantPanelTitle &&
        await _isTerminalPanelRef(runtimeContext, panel)) {
      return;
    }

    final resolved = await _resolveTerminalTarget(runtimeContext);
    if (resolved == null) return;
    arguments['board'] = resolved.boardId;
    arguments['panel'] = resolved.panelId;
  }

  Future<({String boardId, String panelId})?> _resolveTerminalTarget(
    ChatRuntimeContext? runtimeContext,
  ) async {
    final tokens = _searchTokens(userMessage);
    final hintedBoardId = (runtimeContext?.boardId ?? '').trim();
    try {
      final boardIds = await _listBoardIds(runtimeContext);
      if (boardIds == null) return null;

      _PanelCandidate? best;
      for (final boardId in boardIds) {
        final panels = await _listBoardPanels(runtimeContext, boardId);
        if (panels == null) continue;
        for (final panel in panels) {
          final candidate = _scoreTerminalPanel(
            panel: panel,
            boardId: boardId,
            hintedBoardId: hintedBoardId,
            tokens: tokens,
          );
          if (candidate == null) continue;
          if (_isBetterCandidate(best, candidate)) {
            best = candidate;
          }
        }
      }
      if (best == null) return null;
      return (boardId: best.boardId, panelId: best.panelId);
    } catch (_) {
      return null;
    }
  }

  // Lists all non-empty board ids, or null when the boards payload is malformed.
  Future<List<String>?> _listBoardIds(
    ChatRuntimeContext? runtimeContext,
  ) async {
    final boardsRaw = await delegate.invoke(
      'yoloit_boards',
      const <String, Object?>{},
      runtimeContext: runtimeContext,
    );
    final boardsDecoded = jsonDecode(boardsRaw);
    if (boardsDecoded is! Map) return null;
    final boards = boardsDecoded['boards'];
    if (boards is! List) return null;
    final boardIds = <String>[];
    for (final b in boards) {
      if (b is! Map) continue;
      final boardMap = Map<String, Object?>.from(b.cast<String, Object?>());
      final boardId = '${boardMap['id'] ?? ''}'.trim();
      if (boardId.isEmpty) continue;
      boardIds.add(boardId);
    }
    return boardIds;
  }

  // Lists the panels of one board, or null when the panels payload is malformed.
  Future<List<Map<String, Object?>>?> _listBoardPanels(
    ChatRuntimeContext? runtimeContext,
    String boardId,
  ) async {
    final panelsRaw = await delegate.invoke('yoloit_panels', {
      'id_or_name': boardId,
    }, runtimeContext: runtimeContext);
    final panelsDecoded = jsonDecode(panelsRaw);
    if (panelsDecoded is! Map) return null;
    final panels = panelsDecoded['panels'];
    if (panels is! List) return null;
    return [
      for (final p in panels)
        if (p is Map) Map<String, Object?>.from(p.cast<String, Object?>()),
    ];
  }

  bool _isBetterCandidate(_PanelCandidate? best, _PanelCandidate candidate) {
    return best == null ||
        candidate.score > best.score ||
        (candidate.score == best.score && candidate.zIndex > best.zIndex);
  }

  _PanelCandidate? _scoreTerminalPanel({
    required Map<String, Object?> panel,
    required String boardId,
    required String hintedBoardId,
    required Set<String> tokens,
  }) {
    if (panel['type'] != 'board.terminal' || panel['hidden'] == true) {
      return null;
    }
    final panelId = '${panel['id'] ?? ''}'.trim();
    if (panelId.isEmpty) return null;
    final title = '${panel['title'] ?? ''}'.toLowerCase();
    final zIndex = (panel['zIndex'] as num?) ?? 0;
    var score = 1;
    if (boardId == hintedBoardId) score += 2;
    for (final token in tokens) {
      if (token.length < 3) continue;
      if (title.contains(token)) score += 3;
    }
    return (boardId: boardId, panelId: panelId, score: score, zIndex: zIndex);
  }

  Future<bool> _isTerminalPanelRef(
    ChatRuntimeContext? runtimeContext,
    String panelRef,
  ) async {
    final ref = panelRef.trim().toLowerCase();
    if (ref.isEmpty) return false;
    try {
      final boardsRaw = await delegate.invoke(
        'yoloit_boards',
        const <String, Object?>{},
        runtimeContext: runtimeContext,
      );
      final boardsDecoded = jsonDecode(boardsRaw);
      if (boardsDecoded is! Map) return false;
      final boards = boardsDecoded['boards'];
      if (boards is! List) return false;
      for (final b in boards) {
        if (b is! Map) continue;
        final boardId = '${b['id'] ?? ''}'.trim();
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
          if (p['type'] != 'board.terminal') continue;
          final panelId = '${p['id'] ?? ''}'.trim().toLowerCase();
          final title = '${p['title'] ?? ''}'.trim().toLowerCase();
          if (panelId == ref || title == ref) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
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
      final boardIds = await _listBoardIds(runtimeContext);
      if (boardIds == null) return null;

      _PanelCandidate? best;
      for (final boardId in boardIds) {
        final panels = await _listBoardPanels(runtimeContext, boardId);
        if (panels == null) continue;
        for (final panel in panels) {
          final candidate = await _scoreNotePanel(
            panel: panel,
            boardId: boardId,
            hintedBoardId: hintedBoardId,
            tokens: tokens,
            runtimeContext: runtimeContext,
          );
          if (candidate == null) continue;
          if (_isBetterCandidate(best, candidate)) {
            best = candidate;
          }
        }
      }
      if (best == null) return null;
      return (boardId: best.boardId, panelId: best.panelId);
    } catch (_) {
      return null;
    }
  }

  Future<_PanelCandidate?> _scoreNotePanel({
    required Map<String, Object?> panel,
    required String boardId,
    required String hintedBoardId,
    required Set<String> tokens,
    required ChatRuntimeContext? runtimeContext,
  }) async {
    if (panel['type'] != 'board.note.markdown' || panel['hidden'] == true) {
      return null;
    }
    final panelId = '${panel['id'] ?? ''}'.trim();
    if (panelId.isEmpty) return null;
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
      score += await _markdownTokenScore(
        runtimeContext,
        boardId,
        panelId,
        tokens,
      );
    }

    return (boardId: boardId, panelId: panelId, score: score, zIndex: zIndex);
  }

  // Scores a note panel's markdown content against the search tokens.
  Future<int> _markdownTokenScore(
    ChatRuntimeContext? runtimeContext,
    String boardId,
    String panelId,
    Set<String> tokens,
  ) async {
    var score = 0;
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
    return score;
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
