import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide TableRow;
import 'package:yaml/yaml.dart';
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/core/utils/color_utils.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_catalog.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_executor_base.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_executor_shared.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/plugins/builtin/plugin_type_ids.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_plugin_base.dart';
import 'package:yoloit/features/board/services/board_operation_applier.dart';
import 'package:yoloit/features/calendar/data/calendar_event_storage.dart';
import 'package:yoloit/features/calendar/model/calendar_event.dart';
import 'package:yoloit/features/table/model/table_models.dart';

part 'yoloit_tool_executor_web_handlers.dart';

/// Handler for a single CLI command dispatched by
/// [YoloitWebToolExecutor.invoke].
typedef _WebToolHandler =
    FutureOr<String> Function(
      BoardCubit cubit,
      Map<String, Object?> normalized,
      String command,
      ChatRuntimeContext? runtimeContext,
    );

/// Web-safe implementation of [YoloitToolExecutor].
///
/// Instead of shelling out to the `yoloit` CLI, this executor mutates the
/// current board directly via the [BoardCubit] supplied through
/// [ChatRuntimeContext.boardCubit].
class YoloitWebToolExecutor implements YoloitToolExecutor {
  /// In-memory clipboard for panel copy/paste/duplicate inside the browser.
  static String? _clipboardPayload;

  /// Dispatch table mapping each supported CLI command to its handler.
  ///
  /// Multi-command aliases (e.g. `note:add` / `note:append`) point at the
  /// same handler; commands that differ only by a flag (e.g. `note:wrap` /
  /// `note:nowrap`) use small closures binding that flag.
  late final Map<String, _WebToolHandler> _handlers = <String, _WebToolHandler>{
    // Notes / content
    'note:create': (c, a, cmd, ctx) => _handleNoteCreate(c, a),
    'note': (c, a, cmd, ctx) => _handleNoteSet(c, a),
    'note:add': (c, a, cmd, ctx) => _handleNoteAppend(c, a, cmd),
    'note:append': (c, a, cmd, ctx) => _handleNoteAppend(c, a, cmd),
    'note:wrap': (c, a, cmd, ctx) => _handleNoteWrap(c, a, true),
    'note:nowrap': (c, a, cmd, ctx) => _handleNoteWrap(c, a, false),
    'note:get': (c, a, cmd, ctx) => _handlePanelGet(c, a, cmd),
    'code:get': (c, a, cmd, ctx) => _handlePanelGet(c, a, cmd),
    'shape:get': (c, a, cmd, ctx) => _handlePanelGet(c, a, cmd),
    'sticky:get': (c, a, cmd, ctx) => _handlePanelGet(c, a, cmd),
    'sticky:set': (c, a, cmd, ctx) => _handleStickySet(c, a),
    'sticky:append': (c, a, cmd, ctx) => _handleStickyAppend(c, a),
    'sticky:color': (c, a, cmd, ctx) => _handleStickyColor(c, a),
    'shape:set': (c, a, cmd, ctx) => _handleShapeSet(c, a),
    'code:set': (c, a, cmd, ctx) => _handleCodeSet(c, a),

    // Panels
    'panel': (c, a, cmd, ctx) => _handlePanelGet(c, a, cmd),
    'panel:help': (c, a, cmd, ctx) => _handlePanelGet(c, a, cmd),
    'panels': (c, a, cmd, ctx) => _handlePanelsList(c),
    'panel:create': (c, a, cmd, ctx) => _handlePanelCreate(c, a),
    'panel:rename': (c, a, cmd, ctx) => _handlePanelRename(c, a),
    'panel:move': (c, a, cmd, ctx) => _handlePanelMove(c, a),
    'panel:resize': (c, a, cmd, ctx) => _handlePanelResize(c, a),
    'panel:z': (c, a, cmd, ctx) => _handlePanelZ(c, a),
    'panel:delete': (c, a, cmd, ctx) => _handlePanelDelete(c, a),
    'panel:focus': (c, a, cmd, ctx) => _handlePanelFocus(c, a),
    'panel:color': (c, a, cmd, ctx) => _handlePanelColor(c, a),
    'panel:hide': (c, a, cmd, ctx) => _handlePanelHideShow(c, a, hidden: true),
    'panel:show': (c, a, cmd, ctx) => _handlePanelHideShow(c, a, hidden: false),
    'panel:types': (c, a, cmd, ctx) => _handlePanelTypes(c),
    'panel:copy': (c, a, cmd, ctx) => _handlePanelCopy(c, a),
    'panel:paste': (c, a, cmd, ctx) => _handlePanelPaste(c),
    'panel:duplicate': (c, a, cmd, ctx) => _handlePanelDuplicate(c, a),
    'panel:screenshot': (c, a, cmd, ctx) => _handlePanelScreenshotUnsupported(cmd),

    // Sticky / shape / frame
    'sticky:create': (c, a, cmd, ctx) => _handleStickyCreate(c, a),
    'shape:create': (c, a, cmd, ctx) => _handleShapeCreate(c, a),
    'frame:create': (c, a, cmd, ctx) => _handleFrameCreate(c, a),

    // Kanban
    'kanban:add-card': (c, a, cmd, ctx) => _handleKanbanAddCard(c, a),
    'kanban:cards': (c, a, cmd, ctx) => _handleKanbanCards(c, a),
    'kanban:columns': (c, a, cmd, ctx) => _handleKanbanColumns(c, a),
    'kanban:move-card': (c, a, cmd, ctx) => _handleKanbanMoveCard(c, a),
    'kanban:update-card': (c, a, cmd, ctx) => _handleKanbanUpdateCard(c, a),
    'kanban:remove-card': (c, a, cmd, ctx) => _handleKanbanRemoveCard(c, a),
    'kanban:add-column': (c, a, cmd, ctx) => _handleKanbanAddColumn(c, a),
    'kanban:rename-column': (c, a, cmd, ctx) => _handleKanbanRenameColumn(c, a),
    'kanban:remove-column': (c, a, cmd, ctx) => _handleKanbanRemoveColumn(c, a),
    'kanban:paste': (c, a, cmd, ctx) => _handleKanbanPaste(c, a),

    // Checklist
    'checklist:add': (c, a, cmd, ctx) => _handleChecklistAdd(c, a),
    'checklist:items': (c, a, cmd, ctx) => _handleChecklistItems(c, a),
    'checklist:check': (c, a, cmd, ctx) => _handleChecklistToggle(c, a, checked: true),
    'checklist:uncheck': (c, a, cmd, ctx) => _handleChecklistToggle(c, a, checked: false),
    'checklist:remove': (c, a, cmd, ctx) => _handleChecklistRemove(c, a),
    'checklist:rename': (c, a, cmd, ctx) => _handleChecklistRename(c, a),
    'checklist:new': (c, a, cmd, ctx) => _handleChecklistNew(c, a),

    // Calendar
    'calendar:create': (c, a, cmd, ctx) => _handleCalendarCreate(c, a),
    'calendar:events': (c, a, cmd, ctx) => _handleCalendarEvents(c, a),
    'calendar:add-event': (c, a, cmd, ctx) => _handleCalendarAddEvent(c, a),
    'calendar:delete-event': (c, a, cmd, ctx) => _handleCalendarDeleteEvent(c, a),
    'calendar:update-event': (c, a, cmd, ctx) => _handleCalendarUpdateEvent(c, a),
    'calendar:set-view': (c, a, cmd, ctx) => _handleCalendarSetView(c, a),
    'calendar:focus-date': (c, a, cmd, ctx) => _handleCalendarFocusDate(c, a),
    'calendar:scroll-to-time': (c, a, cmd, ctx) => _handleCalendarScrollToTime(c, a),
    'calendar:scroll-to-event': (c, a, cmd, ctx) => _handleCalendarScrollToEvent(c, a),
    'calendar:show-event': (c, a, cmd, ctx) => _handleCalendarShowEvent(c, a),

    // Timer
    'timer:create': (c, a, cmd, ctx) => _handleTimerCreate(c, a),
    'timer:status': (c, a, cmd, ctx) => _handleTimerStatus(c, a),
    'timer:set': (c, a, cmd, ctx) => _handleTimerSet(c, a),
    'timer:start': (c, a, cmd, ctx) => _handleTimerStart(c, a),
    'timer:pause': (c, a, cmd, ctx) => _handleTimerPause(c, a),
    'timer:resume': (c, a, cmd, ctx) => _handleTimerResume(c, a),
    'timer:reset': (c, a, cmd, ctx) => _handleTimerReset(c, a),

    // Table
    'table:create': (c, a, cmd, ctx) => _handleTableCreate(c, a),
    'table:set': (c, a, cmd, ctx) => _handleTableSet(c, a),
    'table:add-row': (c, a, cmd, ctx) => _handleTableAddRow(c, a),
    'table:update-row': (c, a, cmd, ctx) => _handleTableUpdateRow(c, a),
    'table:remove-row': (c, a, cmd, ctx) => _handleTableRemoveRow(c, a),
    'table:add-column': (c, a, cmd, ctx) => _handleTableAddColumn(c, a),
    'table:remove-column': (c, a, cmd, ctx) => _handleTableRemoveColumn(c, a),
    'table:clear': (c, a, cmd, ctx) => _handleTableClear(c, a),

    // Chart
    'chart:create': (c, a, cmd, ctx) => _handleChartCreate(c, a),
    'chart:get': (c, a, cmd, ctx) => _handleChartGet(c, a),
    'chart:set-data': (c, a, cmd, ctx) => _handleChartSetData(c, a),
    'chart:set-type': (c, a, cmd, ctx) => _handleChartSetType(c, a),
    'chart:link-table': (c, a, cmd, ctx) => _handleChartLinkTable(c, a),
    'chart:refresh': (c, a, cmd, ctx) => _handleChartRefresh(c, a),

    // Webpage
    'web:open': (c, a, cmd, ctx) => _handleWebOpen(c, a),
    'web:get': (c, a, cmd, ctx) => _handleWebGet(c, a, cmd),
    'web:title': (c, a, cmd, ctx) => _handleWebGet(c, a, cmd),
    'web:url': (c, a, cmd, ctx) => _handleWebGet(c, a, cmd),
    'web:exec': (c, a, cmd, ctx) => _handleWebUnsupported(c, a, cmd),
    'web:content': (c, a, cmd, ctx) => _handleWebUnsupported(c, a, cmd),
    'web:scroll': (c, a, cmd, ctx) => _handleWebUnsupported(c, a, cmd),
    'web:click': (c, a, cmd, ctx) => _handleWebUnsupported(c, a, cmd),

    // UI
    'ui:create': (c, a, cmd, ctx) => _handleUiCreate(c, a),
    'ui:render': (c, a, cmd, ctx) => _handleUiRender(c, a),
    'ui:get': (c, a, cmd, ctx) => _handleUiGet(c, a),
    'ui:set-state': (c, a, cmd, ctx) => _handleUiSetState(c, a),
    'ui:set-scripts': (c, a, cmd, ctx) => _handleUiSetScripts(c, a),
    'ui:edit': (c, a, cmd, ctx) => _handleUiEdit(c, a),

    // Board
    'boards': (c, a, cmd, ctx) => _handleBoardsList(c),
    'board': (c, a, cmd, ctx) => _handleBoardDetails(c, a, cmd),
    'board:current': (c, a, cmd, ctx) => _handleBoardDetails(c, a, cmd),
    'board:create': (c, a, cmd, ctx) => _handleBoardCreate(c, a),
    'board:rename': (c, a, cmd, ctx) => _handleBoardRename(c, a),
    'board:delete': (c, a, cmd, ctx) => _handleBoardDelete(c, a),
    'board:archive': (c, a, cmd, ctx) => _handleBoardArchive(c, a, archive: true),
    'board:unarchive': (c, a, cmd, ctx) => _handleBoardArchive(c, a, archive: false),
    'board:focus': (c, a, cmd, ctx) => _handleBoardFocus(c, a),
    'board:use': (c, a, cmd, ctx) => _handleBoardFocus(c, a),
    'board:undo': (c, a, cmd, ctx) => _handleBoardUndo(c, a),
    'board:redo': (c, a, cmd, ctx) => _handleBoardRedo(c, a),
    'board:zoom': (c, a, cmd, ctx) => _handleBoardZoom(c, a),
    'board:fit': (c, a, cmd, ctx) => _handleBoardFit(c, a),
    'board:translate': (c, a, cmd, ctx) => _handleBoardTranslate(c, a),
    'board:arrange': (c, a, cmd, ctx) => _handleBoardArrange(c, a),
    'board:grid': (c, a, cmd, ctx) => _handleBoardGrid(c, a),
    'board:snapshot': (c, a, cmd, ctx) => _handleBoardSnapshot(c, a),
    'board:diagram': (c, a, cmd, ctx) => _handleBoardDiagram(c, a),
    'board:svg': (c, a, cmd, ctx) => _handleBoardSvg(c, a),
    'board:apply': (c, a, cmd, ctx) => _handleBoardApply(c, a),

    // Selection
    'select': (c, a, cmd, ctx) => _handleSelect(c, a),

    // Drawings
    'draw:list': (c, a, cmd, ctx) => _handleDrawList(c, a),
    'draw:add': (c, a, cmd, ctx) => _handleDrawAdd(c, a),
    'draw:remove': (c, a, cmd, ctx) => _handleDrawRemove(c, a),
    'draw:clear': (c, a, cmd, ctx) => _handleDrawClear(c, a),
    'draw:svg': (c, a, cmd, ctx) => _handleDrawSvg(c, a),
    'draw:export': (c, a, cmd, ctx) => _handleDrawExport(c, a),

    // Links
    'link:create': (c, a, cmd, ctx) => _handleLinkCreate(c, a),
    'links': (c, a, cmd, ctx) => _handleLinksList(c, a),
    'link:delete': (c, a, cmd, ctx) => _handleLinkDelete(c, a),
    'link:style': (c, a, cmd, ctx) => _handleLinkStyle(c, a),
    'link:color': (c, a, cmd, ctx) => _handleLinkColor(c, a),

    // Groups
    'groups': (c, a, cmd, ctx) => _handleGroupsList(c, a),
    'group:create': (c, a, cmd, ctx) => _handleGroupCreate(c, a),
    'group:delete': (c, a, cmd, ctx) => _handleGroupDelete(c, a),
    'group:rename': (c, a, cmd, ctx) => _handleGroupRename(c, a),
    'group:color': (c, a, cmd, ctx) => _handleGroupColor(c, a),
    'group:add': (c, a, cmd, ctx) => _handleGroupAdd(c, a),
    'group:remove': (c, a, cmd, ctx) => _handleGroupRemove(c, a),
    'group:collapse': (c, a, cmd, ctx) => _handleGroupCollapseExpand(c, a, true),
    'group:expand': (c, a, cmd, ctx) => _handleGroupCollapseExpand(c, a, false),
    'group:move': (c, a, cmd, ctx) => _handleGroupMove(c, a),
    'group:cycle-focus': (c, a, cmd, ctx) => _handleGroupCycleFocus(c, a),

    // YoLo chat
    'yolochat:send': (c, a, cmd, ctx) => _handleYolochatSend(c, a, ctx),
    'yolochat:messages': (c, a, cmd, ctx) => _handleYolochatMessages(c, a),
    'yolochat:clear': (c, a, cmd, ctx) => _handleYolochatClear(c, a),
    'yolochat:status': (c, a, cmd, ctx) => _handleYolochatStatus(c, a),
    'yolochat:stop': (c, a, cmd, ctx) => _handleYolochatStop(c, a),
    'yolochat:sessions': (c, a, cmd, ctx) => _handleYolochatSessions(c),
    'yolochat:config': (c, a, cmd, ctx) => _handleYolochatConfig(c, a),

    // Themes
    'theme': (c, a, cmd, ctx) => _handleTheme(c),
    'theme:presets': (c, a, cmd, ctx) => _handleThemePresets(c),
    'theme:set': (c, a, cmd, ctx) => _handleThemeSet(c, a),
    'theme:brightness': (c, a, cmd, ctx) => _handleThemeBrightness(c, a),
    'theme:color': (c, a, cmd, ctx) => _handleThemeColor(c, a),
    'theme:reset-color': (c, a, cmd, ctx) => _handleThemeResetColor(c, a),
    'theme:reset-all': (c, a, cmd, ctx) => _handleThemeResetAll(c),
    'theme:save': (c, a, cmd, ctx) => _handleThemeSave(c, a),
    'theme:export': (c, a, cmd, ctx) => _handleThemeExport(c),
    'theme:colors': (c, a, cmd, ctx) => _handleThemeColors(c),
    'theme:slots': (c, a, cmd, ctx) => _handleThemeSlots(c),
    'theme:import': (c, a, cmd, ctx) => _handleThemeImportUnsupported(cmd),
    'theme:delete': (c, a, cmd, ctx) => _handleThemeDelete(c, a),

    // Help / search
    'help': (c, a, cmd, ctx) => _handleHelp(a),
    'search': (c, a, cmd, ctx) => _handleSearch(c, a),
  };

  @override
  Future<String> invoke(
    String functionName,
    Map<String, Object?> arguments, {
    ChatRuntimeContext? runtimeContext,
    bool argumentsPreNormalized = false,
  }) async {
    final resolved = resolveToolCall(functionName);
    if (resolved.response != null) return resolved.response!;
    final tool = resolved.tool!;

    final normalized =
        argumentsPreNormalized
            ? Map<String, Object?>.from(arguments)
            : YoloitCliToolArgumentNormalizer.normalize(
              functionName: functionName,
              arguments: Map<String, Object?>.from(arguments),
              userMessage: '',
              runtimeContext: runtimeContext,
            );

    final cubit = runtimeContext?.boardCubit;
    if (cubit == null) {
      return jsonEncode(
        <String, Object?>{
          'ok': false,
          'error': 'No board context available in the browser',
        },
      );
    }

    final command = tool.command;
    final handler = _handlers[command];
    try {
      if (handler != null) {
        return await handler(cubit, normalized, command, runtimeContext);
      }
    } on Exception catch (e) {
      return jsonEncode(
        <String, Object?>{'ok': false, 'error': '$e', 'command': command},
      );
    }

    return jsonEncode(
      <String, Object?>{
        'ok': false,
        'error': '$command is not available in the browser',
      },
    );
  }

  String _handlePanelScreenshotUnsupported(String command) {
    return _error(
      'Panel screenshots are not available in the browser',
      command: command,
    );
  }

  String _handleThemeImportUnsupported(String command) {
    return _error(
      'Theme import requires a file path and is not available in the browser',
      command: command,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  BoardPanelInstance? _findPanel(BoardCubit cubit, Object? hint) {
    final board = cubit.state.activeBoard;
    if (board == null || hint == null) return null;
    final text = '$hint'.trim().toLowerCase();
    if (text.isEmpty) return null;
    for (final panel in board.panels) {
      if (panel.id.toLowerCase() == text ||
          panel.title.trim().toLowerCase() == text) {
        return panel;
      }
    }
    return null;
  }

  BoardPanelInstance? _findPanelByType(
    BoardCubit cubit,
    String type, {
    Object? hint,
  }) {
    final byHint = _findPanel(cubit, hint);
    if (byHint != null && byHint.type == type) return byHint;
    final board = cubit.state.activeBoard;
    if (board == null) return null;
    for (final panel in board.panels) {
      if (panel.type == type) return panel;
    }
    return null;
  }

  BoardDocument? _findBoard(BoardCubit cubit, Object? hint) {
    if (hint == null) return null;
    final text = '$hint'.trim().toLowerCase();
    if (text.isEmpty) return null;
    for (final board in cubit.state.boards) {
      if (board.id.toLowerCase() == text ||
          board.name.trim().toLowerCase() == text) {
        return board;
      }
    }
    return null;
  }

  T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) predicate) {
    for (final item in items) {
      if (predicate(item)) return item;
    }
    return null;
  }

  BoardDocument _requireActiveBoard(BoardCubit cubit) {
    final board = cubit.state.activeBoard;
    if (board == null) throw Exception('No active board');
    return board;
  }

  String _nextId(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  int _findEntryIndex(
    List<Map<String, dynamic>> entries,
    Object? hint, {
    required String textKey,
    String? idKey,
  }) {
    if (hint == null) return -1;
    final text = '$hint'.trim();
    if (text.isEmpty) return -1;
    final lower = text.toLowerCase();
    final asIndex = int.tryParse(text);
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (asIndex != null && i == asIndex) return i;
      final entryText = '${entry[textKey] ?? ''}'.trim();
      final entryId = idKey == null ? '' : '${entry[idKey] ?? ''}'.trim();
      if (entryText.toLowerCase() == lower ||
          entryId.toLowerCase() == lower ||
          entryText.toLowerCase().contains(lower)) {
        return i;
      }
    }
    return -1;
  }

  String _ok(String command, {Map<String, Object?>? extra}) {
    return jsonEncode(
      <String, Object?>{'ok': true, 'executed': true, 'command': command, ...?extra},
    );
  }

  String _dataOk(String command, Map<String, Object?> data) {
    return jsonEncode(
      <String, Object?>{'ok': true, 'command': command, ...data},
    );
  }

  String _error(String message, {String? command}) {
    return jsonEncode(
      <String, Object?>{
        'ok': false,
        'error': message,
        ...? (command != null ? <String, Object?>{'command': command} : null),
      },
    );
  }

  String _panelNotFoundError(String type) {
    final name = type.split('.').last;
    final display = name.isEmpty ? type : '${name[0].toUpperCase()}${name.substring(1)}';
    return _error('$display panel not found');
  }

  Future<String> _withPanel(
    BoardCubit cubit,
    String type,
    Map<String, Object?> args,
    Future<String> Function(BoardPanelInstance panel) action, {
    Object? hint,
  }) async {
    final panel = _findPanelByType(cubit, type, hint: hint ?? args['panel'] ?? args['p']);
    if (panel == null) return _panelNotFoundError(type);
    return action(panel);
  }

  Future<String> _withAnyPanel(
    BoardCubit cubit,
    Map<String, Object?> args,
    Future<String> Function(BoardPanelInstance panel) action,
  ) async {
    final panel = _findPanel(cubit, args['panel'] ?? args['p']);
    if (panel == null) return _error('Panel not found');
    return action(panel);
  }

  Future<void> _updatePanelState(
    BoardCubit cubit,
    BoardPanelInstance panel,
    Map<String, dynamic> updates,
  ) async {
    await cubit.updatePanel(
      panel.id,
      (p) => p.copyWith(state: <String, dynamic>{...p.state, ...updates}),
    );
  }

  List<Map<String, dynamic>> _stateList(BoardPanelInstance panel, String key) {
    return (panel.state[key] as List?)
            ?.cast<Map<String, dynamic>>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        <Map<String, dynamic>>[];
  }

  List<String> _stateStringList(BoardPanelInstance panel, String key) {
    return (panel.state[key] as List?)?.cast<String>().toList() ??
        <String>[];
  }

  Future<void> _setStateList(
    BoardCubit cubit,
    BoardPanelInstance panel,
    String key,
    List<Object?> value,
  ) async {
    await cubit.updatePanel(
      panel.id,
      (p) => p.copyWith(state: <String, dynamic>{...p.state, key: value}),
    );
  }

  String? _stringArg(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  int? _intArg(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  double? _doubleArg(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  bool? _boolArg(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is bool) return value;
    if (value is String) {
      final lower = value.trim().toLowerCase();
      if (lower == 'true' || lower == 'yes' || lower == '1') return true;
      if (lower == 'false' || lower == 'no' || lower == '0') return false;
    }
    return null;
  }

  List<dynamic> _parseJsonList(Object? value) {
    if (value is List) return value;
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded;
      } on FormatException {
        return <dynamic>[];
      }
    }
    return <dynamic>[];
  }

  Map<String, dynamic> _parseJsonMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }

  Set<String> _resolvePanelIds(BoardCubit cubit, Object? panelsArg) {
    final ids = <String>{};
    if (panelsArg != null) {
      final text = '$panelsArg'.trim();
      if (text.isNotEmpty) {
        for (final part in text.split(',')) {
          final trimmed = part.trim();
          if (trimmed.isEmpty) continue;
          final panel = _findPanel(cubit, trimmed);
          if (panel != null) {
            ids.add(panel.id);
          } else {
            ids.add(trimmed);
          }
        }
      }
    }
    return ids;
  }

  // ── Notes / content ───────────────────────────────────────────────────────

  Future<String> _handleNoteCreate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final title = '${args['title'] ?? ''}'.trim();
    final markdown = '${args['content'] ?? args['text'] ?? args['tx'] ?? ''}';
    await cubit.createMarkdownNote(
      title: title.isEmpty ? 'Note' : title,
      markdown: markdown,
    );
    return _ok('note:create');
  }

  Future<String> _handleNoteSet(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final text = '${args['text'] ?? args['tx'] ?? ''}';
    final panel = _findPanelByType(cubit, kMarkdownNotePluginTypeId, hint: args['panel'] ?? args['p']);
    if (panel == null) {
      await cubit.createMarkdownNote(title: 'Note', markdown: text);
      return _ok('note');
    }
    await cubit.updateMarkdownNote(panel.id, title: panel.title, markdown: text);
    return _ok('note');
  }

  Future<String> _handleNoteAppend(
    BoardCubit cubit,
    Map<String, Object?> args,
    String command,
  ) async {
    final text = '${args['text'] ?? args['tx'] ?? ''}';
    if (text.isEmpty) return _error('Missing text to append');
    return _withPanel(cubit, kMarkdownNotePluginTypeId, args, (panel) async {
      final current = '${panel.state['markdown'] ?? ''}';
      final updated = current.isEmpty ? text : '$current\n$text';
      await cubit.updateMarkdownNote(panel.id, title: panel.title, markdown: updated);
      return _ok(command);
    });
  }

  Future<String> _handleNoteWrap(
    BoardCubit cubit,
    Map<String, Object?> args,
    bool wrap,
  ) async {
    return _withPanel(cubit, kMarkdownNotePluginTypeId, args, (panel) async {
      await _updatePanelState(cubit, panel, {'autoHeight': wrap});
      return _ok(wrap ? 'note:wrap' : 'note:nowrap');
    });
  }

  Future<String> _handleStickySet(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final text = '${args['text'] ?? args['tx'] ?? ''}';
    return _withPanel(cubit, kStickyNotePluginTypeId, args, (panel) async {
      await _updatePanelState(cubit, panel, {'text': text});
      return _ok('sticky:set');
    });
  }

  Future<String> _handleStickyAppend(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final text = '${args['text'] ?? args['tx'] ?? ''}';
    if (text.isEmpty) return _error('Missing text to append');
    return _withPanel(cubit, kStickyNotePluginTypeId, args, (panel) async {
      final current = '${panel.state['text'] ?? ''}';
      final updated = current.isEmpty ? text : '$current\n$text';
      await _updatePanelState(cubit, panel, {'text': updated});
      return _ok('sticky:append');
    });
  }

  Future<String> _handleStickyColor(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final color = parseColor('${args['color'] ?? ''}');
    return _withPanel(cubit, kStickyNotePluginTypeId, args, (panel) async {
      final updates = <String, dynamic>{};
      if (color != null) updates['color'] = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      if (updates.isEmpty) return _error('Missing or invalid color');
      await _updatePanelState(cubit, panel, updates);
      return _ok('sticky:color');
    });
  }

  Future<String> _handleShapeSet(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kShapePluginTypeId, args, (panel) async {
      final updates = <String, dynamic>{};
      final text = _stringArg(args, 'text') ?? _stringArg(args, 'tx');
      if (text != null) updates['text'] = text;
      final fill = parseColor('${args['fill'] ?? ''}');
      if (fill != null) updates['fillColor'] = '#${fill.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      final stroke = parseColor('${args['stroke'] ?? ''}');
      if (stroke != null) updates['strokeColor'] = '#${stroke.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      final strokeWidth = _intArg(args, 'stroke_width') ?? _intArg(args, 'sw');
      if (strokeWidth != null) updates['strokeWidth'] = strokeWidth;
      if (updates.isEmpty) return _error('No properties to update');
      await _updatePanelState(cubit, panel, updates);
      return _ok('shape:set');
    });
  }

  Future<String> _handleCodeSet(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final code = '${args['code'] ?? ''}';
    return _withPanel(cubit, kCodeSnippetPluginTypeId, args, (panel) async {
      await _updatePanelState(cubit, panel, {'code': code});
      return _ok('code:set');
    });
  }

  Future<String> _handlePanelGet(
    BoardCubit cubit,
    Map<String, Object?> args,
    String command,
  ) async {
    final panel = _findPanel(cubit, args['panel'] ?? args['p']);
    if (panel == null) return _error('Panel not found');
    final payload = <String, Object?>{
      'id': panel.id,
      'type': panel.type,
      'title': panel.title,
      'state': panel.state,
      if (command == 'panel:help') 'actions': <Map<String, Object?>>[],
    };
    return _dataOk(command, payload);
  }

  Future<String> _handlePanelsList(BoardCubit cubit) async {
    final board = cubit.state.activeBoard;
    if (board == null) return _error('No active board');
    final panels =
        board.panels.map((p) {
          return <String, Object?>{'id': p.id, 'type': p.type, 'title': p.title};
        }).toList();
    return _dataOk('panels', <String, Object?>{'panels': panels});
  }

  Future<String> _handlePanelCreate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final type = '${args['type'] ?? ''}'.trim();
    final title = '${args['title'] ?? ''}'.trim();
    if (type.isEmpty) return _error('Missing panel type');
    await cubit.createGenericPanel(type, title: title.isEmpty ? null : title);
    return _ok('panel:create', extra: <String, Object?>{'type': type});
  }

  Future<String> _handlePanelRename(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withAnyPanel(cubit, args, (panel) async {
      final title = '${args['new_title'] ?? args['new'] ?? ''}'.trim();
      if (title.isEmpty) return _error('Missing new title');
      await cubit.updatePanelTitle(panel.id, title);
      return _ok('panel:rename');
    });
  }

  Future<String> _handlePanelMove(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final x = _doubleArg(args, 'x');
    final y = _doubleArg(args, 'y');
    if (x == null || y == null) return _error('Missing x or y');
    return _withAnyPanel(cubit, args, (panel) async {
      final delta = Offset(x - panel.bounds.x, y - panel.bounds.y);
      await cubit.movePanel(panel.id, delta);
      return _ok('panel:move');
    });
  }

  Future<String> _handlePanelResize(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withAnyPanel(cubit, args, (panel) async {
      final preset = '${args['width'] ?? args['w'] ?? ''}'.trim().toLowerCase();
      final (width, height) = switch (preset) {
        'small' => (420.0, 300.0),
        'medium' => (720.0, 480.0),
        'desktop' => (1200.0, 800.0),
        'large' => (1400.0, 900.0),
        'mobile' => (390.0, 844.0),
        'tablet' => (768.0, 1024.0),
        _ => (
          _doubleArg(args, 'width') ?? _doubleArg(args, 'w') ?? panel.bounds.width,
          _doubleArg(args, 'height') ?? _doubleArg(args, 'h') ?? panel.bounds.height,
        ),
      };
      await cubit.resizePanel(panel.id, width: width, height: height);
      return _ok('panel:resize');
    });
  }

  Future<String> _handlePanelZ(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    return _withAnyPanel(cubit, args, (panel) async {
      final value = '${args['front_or_back_or_zindex'] ?? args['z'] ?? ''}'.trim().toLowerCase();
      final maxZ = board.panels.fold<int>(0, (v, p) => p.zIndex > v ? p.zIndex : v);
      final newZ = switch (value) {
        'front' => maxZ + 1,
        'back' => 0,
        _ => int.tryParse(value),
      };
      if (newZ == null) return _error('Invalid z value');
      await cubit.updatePanel(panel.id, (p) => p.copyWith(zIndex: newZ));
      return _ok('panel:z');
    });
  }

  Future<String> _handlePanelDelete(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withAnyPanel(cubit, args, (panel) async {
      await cubit.removePanel(panel.id);
      return _ok('panel:delete');
    });
  }

  Future<String> _handlePanelFocus(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final panel = _findPanel(cubit, args['panel'] ?? args['p']);
    if (panel == null) return _error('Panel not found');
    await cubit.focusPanel(panel.id);
    return _ok('panel:focus');
  }

  Future<String> _handlePanelColor(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final colorText = '${args['color'] ?? args['cl'] ?? ''}'.trim();
    final color = colorText.toLowerCase() == 'clear' ? null : parseColor(colorText);
    return _withAnyPanel(cubit, args, (panel) async {
      await cubit.updatePanelColor(panel.id, color: color);
      return _ok('panel:color');
    });
  }

  Future<String> _handlePanelHideShow(
    BoardCubit cubit,
    Map<String, Object?> args, {
    required bool hidden,
  }) async {
    return _withAnyPanel(cubit, args, (panel) async {
      await cubit.updatePanel(panel.id, (p) => p.copyWith(hidden: hidden));
      return _ok(hidden ? 'panel:hide' : 'panel:show');
    });
  }

  Future<String> _handlePanelTypes(BoardCubit cubit) async {
    return _dataOk(
      'panel:types',
      <String, Object?>{
        'types': const <String>[
          kMarkdownNotePluginTypeId,
          kStickyNotePluginTypeId,
          kShapePluginTypeId,
          kKanbanPluginTypeId,
          kCodeSnippetPluginTypeId,
          kChecklistPluginTypeId,
          kCalendarPluginTypeId,
          kTablePluginTypeId,
          kChartPluginTypeId,
          kTimerPluginTypeId,
          kWebpagePluginTypeId,
          kUiViewPluginTypeId,
          kChatPluginTypeId,
        ],
      },
    );
  }

  Future<String> _handlePanelCopy(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = cubit.state.activeBoard;
    if (board == null) return _error('No active board');
    var ids = _resolvePanelIds(cubit, args['panels'] ?? args['ps']);
    if (ids.isEmpty) ids = cubit.state.selectedPanelIds;
    if (ids.isEmpty) return _error('No panels selected');
    final panels = board.panels.where((p) => ids.contains(p.id)).toList();
    if (panels.isEmpty) return _error('Selected panels not found');
    final links = board.links
        .where((l) => ids.contains(l.fromPanelId) && ids.contains(l.toPanelId))
        .toList();
    _clipboardPayload = jsonEncode(<String, dynamic>{
      'version': 1,
      'kind': 'yoloit/panels',
      'panels': panels.map((p) => p.toJson()).toList(),
      'links': links.map((l) => l.toJson()).toList(),
    });
    return _ok('panel:copy', extra: <String, Object?>{'ids': ids.toList()});
  }

  Future<String> _handlePanelPaste(BoardCubit cubit) async {
    final board = cubit.state.activeBoard;
    if (board == null) return _error('No active board');
    final payload = _clipboardPayload;
    if (payload == null || payload.isEmpty) return _error('Clipboard is empty');
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    if (decoded['kind'] != 'yoloit/panels') return _error('Clipboard does not contain panels');
    final rawPanels = _parseJsonList(decoded['panels']);
    final rawLinks = _parseJsonList(decoded['links']);
    if (rawPanels.isEmpty) return _error('No panels to paste');
    final idMap = <String, String>{};
    var maxZ = board.panels.fold<int>(0, (v, p) => p.zIndex > v ? p.zIndex : v);
    final newPanels = rawPanels.map((raw) {
      final json = Map<String, dynamic>.from(raw as Map);
      final oldId = json['id'] as String;
      final newId = _nextId('panel');
      idMap[oldId] = newId;
      final bounds = BoardPanelBounds.fromJson(Map<String, dynamic>.from(json['bounds'] as Map));
      final newBounds = bounds.copyWith(
        x: bounds.x + 40,
        y: bounds.y + 40,
      );
      maxZ++;
      return BoardPanelInstance.fromJson({
        ...json,
        'id': newId,
        'bounds': newBounds.toJson(),
        'zIndex': maxZ,
      });
    }).toList();
    final newLinks = rawLinks.map((raw) {
      final json = Map<String, dynamic>.from(raw as Map);
      final newFrom = idMap[json['fromPanelId'] as String];
      final newTo = idMap[json['toPanelId'] as String];
      if (newFrom == null || newTo == null) return null;
      return BoardPanelLink.fromJson({
        ...json,
        'id': _nextId('link'),
        'fromPanelId': newFrom,
        'toPanelId': newTo,
      });
    }).whereType<BoardPanelLink>().toList();
    for (final panel in newPanels) {
      await cubit.addPanel(panel);
    }
    for (final link in newLinks) {
      await cubit.upsertLink(link);
    }
    cubit.selectPanels(newPanels.map((p) => p.id).toSet());
    return _ok('panel:paste', extra: <String, Object?>{'ids': newPanels.map((p) => p.id).toList()});
  }

  Future<String> _handlePanelDuplicate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final copyResult = await _handlePanelCopy(cubit, args);
    final copyDecoded = jsonDecode(copyResult) as Map<String, dynamic>;
    if (copyDecoded['ok'] != true) return copyResult;
    return _handlePanelPaste(cubit);
  }

  Future<String> _handleStickyCreate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final title = '${args['title'] ?? ''}'.trim();
    final text = '${args['text'] ?? args['tx'] ?? ''}';
    final color = parseColor('${args['color'] ?? ''}');
    final panelState = <String, dynamic>{
      'text': text,
      if (color != null)
        'color':
            '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    };
    await cubit.createGenericPanel(
      kStickyNotePluginTypeId,
      title: title.isEmpty ? 'Sticky' : title,
      panelState: panelState,
    );
    return _ok('sticky:create');
  }

  Future<String> _handleShapeCreate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final title = '${args['title'] ?? ''}'.trim();
    final shape = '${args['shape'] ?? ''}'.trim().toLowerCase();
    if (shape.isEmpty) return _error('Missing shape');
    final text = _stringArg(args, 'text') ?? _stringArg(args, 'tx') ?? '';
    final fill = parseColor('${args['fill'] ?? ''}');
    final stroke = parseColor('${args['stroke'] ?? ''}');
    final panelState = <String, dynamic>{
      'shape': shape,
      'text': text,
      if (fill != null)
        'fillColor':
            '#${fill.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
      if (stroke != null)
        'strokeColor':
            '#${stroke.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    };
    await cubit.createGenericPanel(
      kShapePluginTypeId,
      title: title.isEmpty ? 'Shape' : title,
      panelState: panelState,
    );
    return _ok('shape:create');
  }

  Future<String> _handleFrameCreate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final title = '${args['title'] ?? ''}'.trim();
    await cubit.createGenericPanel(
      kShapePluginTypeId,
      title: title.isEmpty ? 'Frame' : title,
      panelState: <String, dynamic>{'shape': 'frame'},
    );
    return _ok('frame:create');
  }

}

/// Creates the web-safe tool executor.
YoloitToolExecutor createPlatformToolExecutor() => YoloitWebToolExecutor();
