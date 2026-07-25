import 'package:js_widget_runtime/js_widget_runtime.dart';

import 'package:yoloit/core/cli/handlers/ui_handler.dart';
import 'package:yoloit/core/remote/yoloitd_models.dart';
import 'package:yoloit/core/remote/yoloitd_panel_catalog.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_plugin_base.dart';
import 'package:yoloit/features/board/widgets/app_cli_utils.dart';

class RemotePanelActionResult {
  const RemotePanelActionResult({
    this.ok = true,
    this.message,
    this.data = const <String, dynamic>{},
    this.stateUpdate = const <String, dynamic>{},
  });

  final bool ok;
  final String? message;
  final Map<String, dynamic> data;
  final Map<String, dynamic> stateUpdate;

  Map<String, dynamic> toJson({RemotePanel? panel}) => <String, dynamic>{
    'ok': ok,
    if (message != null) 'message': message,
    if (data.isNotEmpty) 'data': data,
    if (stateUpdate.isNotEmpty) 'stateUpdate': stateUpdate,
    if (panel != null) 'panel': panel.toJson(),
  };
}

RemotePanelActionResult handleRemotePanelAction(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  if (action == 'get') {
    return RemotePanelActionResult(data: _content(panel));
  }

  return switch (panel.type) {
    'board.note.markdown' => _note(panel, action, args),
    'board.sticky' => _sticky(panel, action, args),
    'board.shape' => _shape(panel, action, args),
    'board.kanban' => _kanban(panel, action, args),
    'board.checklist' => _checklist(panel, action, args),
    'board.code.snippet' => _code(panel, action, args),
    'board.webpage' => _webpage(panel, action, args),
    'board.playlist' => _playlist(panel, action, args),
    'board.files' => _files(panel, action, args),
    'board.file.preview' => _filePreview(panel, action, args),
    'board.filetree' => _fileTree(panel, action, args),
    'board.terminal' => _terminal(panel, action, args),
    'board.timer' => _timer(panel, action, args),
    'board.chat' => _chat(panel, action, args),
    'board.setup_guide' => _setupGuide(panel, action, args),
    'board.run' || 'board.run_configs' => _run(panel, action, args),
    'board.table' => _table(panel, action, args),
    'board.calendar' => _calendar(panel, action, args),
    'board.chart' => _chart(panel, action, args),
    'board.ui' => _uiView(panel, action, args),
    'board.diff.preview' => _diffPreview(panel, action, args),
    'board.yolo_assistant' => _yoloAssistant(panel, action, args),
    'board.widget.custom' => _customWidget(panel, action, args),
    _ => _generic(panel, action, args),
  };
}

Map<String, dynamic> remotePanelActionHelp(RemotePanel panel) {
  final descriptor = yoloitdPanelDescriptorFor(panel.type);
  return <String, dynamic>{
    'actions': descriptor?.actions ?? const <String>['get', 'set'],
    if (descriptor != null) 'capabilities': descriptor.toJson()['capabilities'],
  };
}

Map<String, dynamic> _content(RemotePanel panel) {
  return switch (panel.type) {
    'board.note.markdown' => {
      'markdown': panel.state['markdown'] ?? '',
      'autoHeight': panel.state['autoHeight'] ?? false,
    },
    'board.sticky' => {
      'text': panel.state['text'] ?? '',
      'color': panel.state['color'] ?? '#FEF08A',
      'textColor': panel.state['textColor'] ?? '#1F2937',
      'fontSize': panel.state['fontSize'] ?? 18,
    },
    'board.shape' => {
      'shape': panel.state['shape'] ?? 'rectangle',
      'text': panel.state['text'] ?? '',
      'fillColor': panel.state['fillColor'] ?? '#00000000',
      'strokeColor': panel.state['strokeColor'] ?? '#93C5FD',
      'textColor': panel.state['textColor'] ?? '#E2E8F0',
      'strokeWidth': panel.state['strokeWidth'] ?? 3,
      'textHAlign': panel.state['textHAlign'] ?? 'center',
      'textVAlign': panel.state['textVAlign'] ?? 'center',
      'textOrientation': panel.state['textOrientation'] ?? 'horizontal',
    },
    'board.kanban' => {'columns': _columns(panel), 'cards': _cards(panel)},
    'board.checklist' => {'items': _items(panel)},
    'board.code.snippet' => {
      'language': panel.state['language'] ?? 'plaintext',
      'code': panel.state['code'] ?? '',
    },
    'board.webpage' => {
      'url': panel.state['url'] ?? '',
      'title': panel.state['title'] ?? '',
      'favicon': panel.state['favicon'] ?? '',
    },
    'board.playlist' => {
      'tracks': _maps(panel.state['tracks']),
      'currentIndex': _int(panel.state['currentIndex'], fallback: -1),
      'playing': panel.state['playing'] ?? false,
    },
    'board.files' => {
      'selectedPath': panel.state['selectedPath'] ?? '',
      'files': _maps(panel.state['files']),
    },
    'board.file.preview' => {
      'path': panel.state['path'] ?? panel.state['filePath'] ?? '',
      'filePath': panel.state['filePath'] ?? panel.state['path'] ?? '',
    },
    'board.filetree' => {
      'rootPath': panel.state['rootPath'] ?? '',
      'expandedDirs': _strings(panel.state['expandedDirs']),
      'selectedFile': panel.state['selectedFile'] ?? '',
    },
    'board.terminal' => {'config': _map(panel.state['config'])},
    'board.timer' => {
      'duration': _int(panel.state['duration'], fallback: 300),
      'remaining': _int(panel.state['remaining'], fallback: 300),
      'isRunning': panel.state['isRunning'] ?? false,
      'isPaused': panel.state['isPaused'] ?? false,
      'completed': panel.state['completed'] ?? false,
      'label': panel.state['label'] ?? '',
    },
    'board.chat' => {
      'config': _map(panel.state['config']),
      'messages': _maps(panel.state['messages']),
      'configured': panel.state['configured'] ?? false,
    },
    'board.ui' => () {
      final tree =
          UiViewPluginBase.treeFromState(panel.state) ??
          UiViewPluginBase.defaultTree();
      final storage = UiViewBindings.storageFromState(panel.state);
      final resolved = UiViewBindings.applyTree(tree, storage);
      return <String, dynamic>{
        'tree': tree,
        'resolvedTree': resolved,
        'storage': storage,
        'scripts': UiViewBindings.scriptsFromState(panel.state),
        'text': AppCliUtils.extractTextLines(resolved),
        if (panel.state['_lastEvent'] != null)
          'lastEvent': panel.state['_lastEvent'],
      };
    }(),
    _ => Map<String, dynamic>.from(panel.state),
  };
}

RemotePanelActionResult _note(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  switch (action) {
    case 'set':
      final text = args['text'] ?? args['markdown'];
      if (text == null) return _missing('text or markdown');
      return RemotePanelActionResult(
        stateUpdate: {'markdown': text.toString()},
      );
    case 'append':
      final text = args['text'];
      if (text == null) return _missing('text');
      final current = panel.state['markdown'] as String? ?? '';
      return RemotePanelActionResult(
        stateUpdate: {
          'markdown': current.isEmpty ? text.toString() : '$current\n$text',
        },
      );
    case 'wrap':
      return const RemotePanelActionResult(stateUpdate: {'autoHeight': true});
    case 'nowrap':
      return const RemotePanelActionResult(stateUpdate: {'autoHeight': false});
  }
  return _unknown(action);
}

RemotePanelActionResult _sticky(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  switch (action) {
    case 'set':
      final update = _pick(args, ['text', 'color', 'textColor', 'fontSize']);
      return update.isEmpty
          ? _missing('sticky fields')
          : RemotePanelActionResult(stateUpdate: update);
    case 'append':
      final text = args['text'];
      if (text == null) return _missing('text');
      final current = panel.state['text'] as String? ?? '';
      return RemotePanelActionResult(
        stateUpdate: {
          'text': current.trim().isEmpty ? text.toString() : '$current\n$text',
        },
      );
    case 'color':
      final color = args['color'] ?? args['fillColor'];
      final textColor = args['textColor'];
      if (color == null && textColor == null && args['fontSize'] == null) {
        return _missing('color, textColor, or fontSize');
      }
      return RemotePanelActionResult(
        stateUpdate: {
          'color?': color,
          'textColor?': textColor,
          if (args['fontSize'] != null) 'fontSize': args['fontSize'],
        },
      );
  }
  return _unknown(action);
}

RemotePanelActionResult _shape(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  if (action != 'set') return _unknown(action);
  final update = _pick(args, [
    'shape',
    'text',
    'fillColor',
    'strokeColor',
    'textColor',
    'strokeWidth',
    'fontSize',
    'textHAlign',
    'textVAlign',
    'textOrientation',
  ]);
  return update.isEmpty
      ? _missing('shape fields')
      : RemotePanelActionResult(stateUpdate: update);
}

RemotePanelActionResult _kanban(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  final columns = _columns(panel);
  final cards = _cards(panel);
  switch (action) {
    case 'columns':
      return RemotePanelActionResult(data: {'columns': columns});
    case 'cards':
      return RemotePanelActionResult(
        data: {'columns': columns, 'cards': cards},
      );
    case 'add-column':
      final name = args['name']?.toString().trim();
      if (name == null || name.isEmpty) return _missing('name');
      columns.add(name);
      return RemotePanelActionResult(
        stateUpdate: {'columns': columns},
        data: {'columnIndex': columns.length - 1},
      );
    case 'rename-column':
      final idx = _columnIndex(columns, args['columnId'] ?? args['column']);
      final name = args['name']?.toString().trim();
      if (idx < 0 || name == null || name.isEmpty) {
        return _missing('columnId/name');
      }
      columns[idx] = name;
      return RemotePanelActionResult(stateUpdate: {'columns': columns});
    case 'remove-column':
      final idx = _columnIndex(columns, args['columnId'] ?? args['column']);
      if (idx < 0) return _notFound('column');
      columns.removeAt(idx);
      final kept = <Map<String, dynamic>>[];
      for (final card in cards) {
        final old = _int(
          card['columnIndex'],
          fallback: _columnIndex(columns, card['column']),
        );
        if (old == idx) continue;
        kept.add(
          {...card, 'columnIndex': old > idx ? old - 1 : old}..remove('column'),
        );
      }
      return RemotePanelActionResult(
        stateUpdate: {'columns': columns, 'cards': kept},
      );
    case 'add-card':
      final colIndex = _columnIndex(
        columns,
        args['columnId'] ?? args['column'],
      );
      final title = args['title']?.toString().trim();
      if (colIndex < 0 || title == null || title.isEmpty) {
        return _missing('columnId/title');
      }
      final cardId = args['id']?.toString() ?? _timestampId('card');
      cards.add({
        'id': cardId,
        'title': title,
        'description': args['description']?.toString() ?? '',
        'columnIndex': colIndex,
        if (args['color'] != null) 'color': args['color'],
      });
      return RemotePanelActionResult(
        stateUpdate: {'cards': cards},
        data: {'cardId': cardId},
      );
    case 'move-card':
      final cardId = args['cardId']?.toString();
      final to = _columnIndex(
        columns,
        args['to'] ?? args['columnId'] ?? args['column'],
      );
      final index = cards.indexWhere((card) => card['id'] == cardId);
      if (cardId == null || index < 0 || to < 0) return _missing('cardId/to');
      cards[index] = {...cards[index], 'columnIndex': to}..remove('column');
      return RemotePanelActionResult(stateUpdate: {'cards': cards});
    case 'remove-card':
      final cardId = args['cardId']?.toString();
      if (cardId == null) return _missing('cardId');
      cards.removeWhere((card) => card['id'] == cardId);
      return RemotePanelActionResult(stateUpdate: {'cards': cards});
    case 'update-card':
      final cardId = args['cardId']?.toString();
      final index = cards.indexWhere((card) => card['id'] == cardId);
      if (cardId == null || index < 0) return _notFound('card');
      cards[index] = {
        ...cards[index],
        ..._pick(args, ['title', 'description', 'color']),
      };
      return RemotePanelActionResult(stateUpdate: {'cards': cards});
    case 'paste':
      final text = args['text']?.toString();
      if (text == null || text.trim().isEmpty) return _missing('text');
      final lines = text.trim().split('\n');
      final title = lines.first.trim();
      final description = lines.skip(1).join('\n').trim();
      final columnIndex = _int(args['columnIndex'], fallback: 0)
          .clamp(0, columns.length - 1);
      cards.add({
        'id': _timestampId('card'),
        'title': title.length > 120 ? '${title.substring(0, 120)}…' : title,
        'description': description,
        'columnIndex': columnIndex,
      });
      return RemotePanelActionResult(
        stateUpdate: {'cards': cards},
        data: {'columnIndex': columnIndex},
      );
  }
  return _unknown(action);
}

RemotePanelActionResult _checklist(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  final items = _items(panel);
  switch (action) {
    case 'items':
      return RemotePanelActionResult(data: {'items': items});
    case 'add':
      final text = args['text']?.toString();
      if (text == null) return _missing('text');
      items.add({
        'id': args['id']?.toString() ?? _timestampId('item'),
        'text': text,
        'done': false,
      });
      return RemotePanelActionResult(stateUpdate: {'items': items});
    case 'check':
    case 'uncheck':
      final index = _itemIndex(items, args);
      if (index < 0) return _notFound('item');
      items[index] = {...items[index], 'done': action == 'check'};
      return RemotePanelActionResult(stateUpdate: {'items': items});
    case 'remove':
      final index = _itemIndex(items, args);
      if (index < 0) return _notFound('item');
      items.removeAt(index);
      return RemotePanelActionResult(stateUpdate: {'items': items});
    case 'rename':
      final index = _itemIndex(items, args);
      final text = (args['newText'] ?? args['text'])?.toString();
      if (index < 0 || text == null) return _missing('index/id/text');
      items[index] = {...items[index], 'text': text};
      return RemotePanelActionResult(stateUpdate: {'items': items});
  }
  return _unknown(action);
}

RemotePanelActionResult _code(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  if (action != 'set') return _unknown(action);
  final code = args['code'];
  if (code == null) return _missing('code');
  return RemotePanelActionResult(
    stateUpdate: {
      'code': code.toString(),
      if (args['language'] != null) 'language': args['language'],
    },
  );
}

RemotePanelActionResult _webpage(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  if (action != 'open') return _unknown(action);
  final url = args['url']?.toString();
  if (url == null || url.isEmpty) return _missing('url');
  return RemotePanelActionResult(
    stateUpdate: {
      'url': url,
      if (args['title'] != null) 'title': args['title'],
    },
  );
}

RemotePanelActionResult _playlist(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  final tracks = _maps(panel.state['tracks']);
  switch (action) {
    case 'list':
      return RemotePanelActionResult(data: _content(panel));
    case 'add':
      final path = args['path'] ?? args['url'];
      if (path == null) return _missing('path or url');
      tracks.add({
        'path': path.toString(),
        'title': args['title']?.toString() ?? path.toString().split('/').last,
      });
      return RemotePanelActionResult(stateUpdate: {'tracks': tracks});
    case 'remove':
      final index = _int(args['index'], fallback: -1);
      if (index < 0 || index >= tracks.length) return _notFound('track');
      tracks.removeAt(index);
      return RemotePanelActionResult(
        stateUpdate: {
          'tracks': tracks,
          'currentIndex': tracks.isEmpty ? -1 : 0,
        },
      );
    case 'play':
      if (tracks.isEmpty) return _notFound('track');
      final index = _int(
        args['index'],
        fallback: _int(panel.state['currentIndex'], fallback: 0),
      ).clamp(0, tracks.length - 1);
      return RemotePanelActionResult(
        stateUpdate: {'currentIndex': index, 'playing': true},
      );
    case 'pause':
      return const RemotePanelActionResult(stateUpdate: {'playing': false});
    case 'stop':
      return const RemotePanelActionResult(
        stateUpdate: {'playing': false, 'currentIndex': 0},
      );
    case 'next':
    case 'prev':
      if (tracks.isEmpty) return _notFound('track');
      final current = _int(panel.state['currentIndex'], fallback: 0);
      final next =
          action == 'next'
              ? (current + 1) % tracks.length
              : (current > 0 ? current - 1 : tracks.length - 1);
      return RemotePanelActionResult(
        stateUpdate: {'currentIndex': next, 'playing': true},
      );
  }
  return _unknown(action);
}

RemotePanelActionResult _files(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  final files = _maps(panel.state['files']);
  switch (action) {
    case 'open':
      final path = args['path']?.toString();
      if (path == null) return _missing('path');
      return RemotePanelActionResult(stateUpdate: {'selectedPath': path});
    case 'add':
      final path = args['path']?.toString();
      if (path == null) return _missing('path');
      files.add({
        'id': args['id']?.toString() ?? _timestampId('file'),
        'path': path,
        'name': args['name']?.toString() ?? path.split('/').last,
      });
      return RemotePanelActionResult(stateUpdate: {'files': files});
    case 'remove':
      final id = args['id']?.toString();
      final path = args['path']?.toString();
      files.removeWhere((file) => file['id'] == id || file['path'] == path);
      return RemotePanelActionResult(stateUpdate: {'files': files});
    case 'clear':
      return const RemotePanelActionResult(
        stateUpdate: {'files': <Map<String, dynamic>>[]},
      );
  }
  return _unknown(action);
}

RemotePanelActionResult _filePreview(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  if (action != 'open') return _unknown(action);
  final path = args['path']?.toString();
  if (path == null) return _missing('path');
  return RemotePanelActionResult(
    stateUpdate: {
      'path': path,
      'filePath': path,
      if (args['title'] != null) 'title': args['title'],
    },
  );
}

RemotePanelActionResult _fileTree(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  final expanded = _strings(panel.state['expandedDirs']);
  switch (action) {
    case 'list':
      return RemotePanelActionResult(data: _content(panel));
    case 'open':
      final path = args['path']?.toString();
      if (path == null) return _missing('path');
      return RemotePanelActionResult(stateUpdate: {'selectedFile': path});
    case 'expand':
      final dir = args['dir']?.toString();
      if (dir == null) return _missing('dir');
      if (!expanded.contains(dir)) expanded.add(dir);
      return RemotePanelActionResult(stateUpdate: {'expandedDirs': expanded});
    case 'collapse':
      final dir = args['dir']?.toString();
      if (dir == null) return _missing('dir');
      expanded.remove(dir);
      return RemotePanelActionResult(stateUpdate: {'expandedDirs': expanded});
    case 'set-root':
      final path = args['path']?.toString();
      if (path == null) return _missing('path');
      return RemotePanelActionResult(
        stateUpdate: {
          'rootPath': path,
          'expandedDirs': <String>[],
          'selectedFile': '',
        },
      );
    case 'refresh':
      return RemotePanelActionResult(
        stateUpdate: {'_refreshAt': DateTime.now().toUtc().toIso8601String()},
      );
  }
  return _unknown(action);
}

RemotePanelActionResult _terminal(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  final config = _map(panel.state['config']);
  switch (action) {
    case 'config':
      return RemotePanelActionResult(data: {'config': config});
    case 'set-dir':
      final dir = args['dir'] ?? args['path'];
      if (dir == null) return _missing('dir');
      return RemotePanelActionResult(
        stateUpdate: {
          'config': {...config, 'workingDir': dir.toString()},
        },
      );
    case 'set-session':
      final id = args['sessionId']?.toString();
      if (id == null) return _missing('sessionId');
      return RemotePanelActionResult(
        stateUpdate: {
          'config': {...config, 'sessionId': id},
        },
      );
  }
  return _unknown(action);
}

RemotePanelActionResult _timer(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  switch (action) {
    case 'status':
      return RemotePanelActionResult(data: _content(panel));
    case 'set':
      final duration = _duration(args['duration'] ?? panel.state['duration']);
      return RemotePanelActionResult(
        stateUpdate: {
          'duration': duration,
          'remaining': duration,
          'isRunning': false,
          'isPaused': false,
          'completed': false,
          if (args['label'] != null) 'label': args['label'],
        },
      );
    case 'start':
      final duration = _duration(args['duration'] ?? panel.state['duration']);
      return RemotePanelActionResult(
        stateUpdate: {
          'duration': duration,
          'remaining': duration,
          'isRunning': true,
          'isPaused': false,
          'completed': false,
          'lastTick': DateTime.now().millisecondsSinceEpoch,
          if (args['label'] != null) 'label': args['label'],
        },
      );
    case 'pause':
      return const RemotePanelActionResult(
        stateUpdate: {'isRunning': false, 'isPaused': true},
      );
    case 'resume':
      return RemotePanelActionResult(
        stateUpdate: {
          'isRunning': true,
          'isPaused': false,
          'lastTick': DateTime.now().millisecondsSinceEpoch,
        },
      );
    case 'reset':
      final duration = _duration(panel.state['duration']);
      return RemotePanelActionResult(
        stateUpdate: {
          'remaining': duration,
          'isRunning': false,
          'isPaused': false,
          'completed': false,
        },
      );
  }
  return _unknown(action);
}

RemotePanelActionResult _chat(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  final messages = _maps(panel.state['messages']);
  switch (action) {
    case 'messages':
      return RemotePanelActionResult(
        data: {'messages': messages, 'total': messages.length},
      );
    case 'send':
      final text = args['text'] ?? args['message'];
      if (text == null) return _missing('text');
      messages.add({
        'role': 'user',
        'content': text.toString(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      return RemotePanelActionResult(
        stateUpdate: {'messages': messages, 'configured': true},
      );
    case 'config':
      final config = {
        ..._map(panel.state['config']),
        ..._map(args['config']),
        ..._pick(args, ['provider', 'model', 'workingDir', 'sessionName']),
      };
      return RemotePanelActionResult(
        stateUpdate: {'config': config, 'configured': true},
        data: {'config': config},
      );
    case 'clear':
      return const RemotePanelActionResult(
        stateUpdate: {'messages': <Map<String, dynamic>>[]},
      );
    case 'status':
      return RemotePanelActionResult(
        data: {'messageCount': messages.length, 'isProcessing': false},
      );
  }
  return _unknown(action);
}

RemotePanelActionResult _setupGuide(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  final selected = _strings(panel.state['selectedPackageIds']);
  switch (action) {
    case 'select':
      final id = args['packageId']?.toString();
      if (id == null) return _missing('packageId');
      if (!selected.contains(id)) selected.add(id);
      return RemotePanelActionResult(
        stateUpdate: {'selectedPackageIds': selected},
      );
    case 'unselect':
      final id = args['packageId']?.toString();
      if (id == null) return _missing('packageId');
      selected.remove(id);
      return RemotePanelActionResult(
        stateUpdate: {'selectedPackageIds': selected},
      );
    case 'set-selected':
      return RemotePanelActionResult(
        stateUpdate: {'selectedPackageIds': _strings(args['packageIds'])},
      );
  }
  return _unknown(action);
}

RemotePanelActionResult _run(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  switch (action) {
    case 'get':
      return RemotePanelActionResult(
        data: Map<String, dynamic>.from(panel.state),
      );
    case 'set-group':
      final group = args['group']?.toString();
      if (group == null) return _missing('group');
      return RemotePanelActionResult(stateUpdate: {'group': group});
    case 'select-session':
      final id = args['sessionId']?.toString();
      if (id == null) return _missing('sessionId');
      return RemotePanelActionResult(stateUpdate: {'activeSessionId': id});
    case 'clear-session':
      return const RemotePanelActionResult(
        stateUpdate: {'activeSessionId': null},
      );
  }
  return _unknown(action);
}

RemotePanelActionResult _table(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  final columns = _tableColumns(panel);
  final rows = _tableRows(panel);
  switch (action) {
    case 'get':
      return RemotePanelActionResult(
        data: {
          'tableId': _tableEffectiveId(panel),
          'columns': columns,
          'rows': rows,
        },
      );
    case 'set':
      final newColumns = _maps(args['columns']);
      final newRows =
          _maps(args['rows']).map((row) => _normalizeTableRowInput(row)).toList();
      if (newColumns.isEmpty) {
        return _missing('columns');
      }
      return RemotePanelActionResult(
        stateUpdate: {
          'columns': newColumns,
          'rows': newRows,
        },
      );
    case 'set-id':
      final tableId = _string(args['tableId'] ?? args['id']);
      if (tableId == null || tableId.isEmpty) {
        return _missing('tableId');
      }
      return RemotePanelActionResult(
        stateUpdate: {
          ...panel.state,
          'tableId': tableId,
        },
      );
    case 'add-column':
      final id = _string(args['id'] ?? args['columnId']);
      if (id == null || id.isEmpty) {
        return _missing('id');
      }
      if (columns.any((column) => column['id'] == id)) {
        return RemotePanelActionResult(
          ok: false,
          message: 'Column already exists: $id',
        );
      }
      final title = _string(args['title'] ?? args['name']) ?? id;
      final type = _string(args['type']) ?? 'text';
      final newColumn = <String, dynamic>{
        'id': id,
        'title': title,
        'type': type,
        if (args['options'] is List) 'options': _strings(args['options']),
      };
      final defaultValue = _tableDefaultCellValue(type);
      final updatedRows =
          rows
              .map(
                (row) => <String, dynamic>{
                  ...row,
                  id: defaultValue,
                },
              )
              .toList();
      return RemotePanelActionResult(
        stateUpdate: {
          'columns': [...columns, newColumn],
          'rows': updatedRows,
        },
      );
    case 'rename-column':
      final id = _string(args['id'] ?? args['columnId']);
      final title = _string(args['title'] ?? args['name']);
      if (id == null || id.isEmpty || title == null || title.isEmpty) {
        return _missing('id/title');
      }
      final index = columns.indexWhere((column) => column['id'] == id);
      if (index < 0) return _notFound('Column');
      columns[index] = {...columns[index], 'title': title};
      return RemotePanelActionResult(stateUpdate: {'columns': columns});
    case 'remove-column':
      final id = _string(args['id'] ?? args['columnId']);
      if (id == null || id.isEmpty) return _missing('id');
      final index = columns.indexWhere((column) => column['id'] == id);
      if (index < 0) return _notFound('Column');
      columns.removeAt(index);
      final updatedRows =
          rows
              .map((row) => <String, dynamic>{...row}..remove(id))
              .toList();
      return RemotePanelActionResult(
        stateUpdate: {'columns': columns, 'rows': updatedRows},
      );
    case 'add-row':
      final cellInput = _normalizeTableCellInput(args, columns);
      final cells = <String, dynamic>{
        for (final column in columns)
          column['id'] as String:
              _tableCastCellValue(cellInput[column['id']], column['type']),
      };
      final newRow = <String, dynamic>{
        'id': 'r-${DateTime.now().millisecondsSinceEpoch}',
        ...cells,
      };
      return RemotePanelActionResult(
        stateUpdate: {'rows': [...rows, newRow]},
        data: {'rowId': newRow['id']},
      );
    case 'update-row':
      final rowId = _string(args['id'] ?? args['rowId']);
      if (rowId == null || rowId.isEmpty) return _missing('id');
      final index = rows.indexWhere((row) => row['id'] == rowId);
      if (index < 0) return _notFound('Row');
      final cellInput = _normalizeTableCellInput(args, columns);
      final updatedCells = Map<String, dynamic>.from(rows[index]);
      for (final column in columns) {
        final columnId = column['id'] as String;
        if (cellInput.containsKey(columnId)) {
          updatedCells[columnId] = _tableCastCellValue(
            cellInput[columnId],
            column['type'],
          );
        }
      }
      rows[index] = updatedCells;
      return RemotePanelActionResult(stateUpdate: {'rows': rows});
    case 'remove-row':
      final rowId = _string(args['id'] ?? args['rowId']);
      if (rowId == null || rowId.isEmpty) return _missing('id');
      rows.removeWhere((row) => row['id'] == rowId);
      return RemotePanelActionResult(stateUpdate: {'rows': rows});
    case 'clear':
      return const RemotePanelActionResult(
        stateUpdate: {'rows': <Map<String, dynamic>>[]},
      );
  }
  return _unknown(action);
}

List<Map<String, dynamic>> _tableColumns(RemotePanel panel) => _maps(
  panel.state['columns'],
).toList();

List<Map<String, dynamic>> _tableRows(RemotePanel panel) => _maps(
  panel.state['rows'],
).toList();

String _tableEffectiveId(RemotePanel panel) {
  final custom = (panel.state['tableId'] as String?)?.trim() ?? '';
  return custom.isEmpty ? panel.id : custom;
}

Map<String, dynamic> _tableCellInput(Map<String, dynamic> args) {
  final cells = args['cells'] ?? args['row'];
  if (cells is Map) return Map<String, dynamic>.from(cells);
  return args;
}

/// Normalizes cell input for `add-row` / `update-row` so values keyed by
/// column title are mapped to the matching column id. If both id and title
/// reference the same column, the id key wins.
Map<String, dynamic> _normalizeTableCellInput(
  Map<String, dynamic> args,
  List<Map<String, dynamic>> columns,
) {
  final input = _tableCellInput(args);
  final columnIds =
      columns.map((column) => (column['id'] as String?)?.trim() ?? '').toSet();
  final titleToId = <String, String>{
    for (final column in columns)
      if (column['title'] != null)
        column['title'].toString().toLowerCase().trim():
            (column['id'] as String?)?.trim() ?? '',
  };
  final normalized = <String, dynamic>{};
  for (final entry in input.entries) {
    final key = entry.key.toString();
    if (columnIds.contains(key)) {
      normalized[key] = entry.value;
      continue;
    }
    final idFromTitle = titleToId[key.toLowerCase().trim()];
    if (idFromTitle != null && idFromTitle.isNotEmpty) {
      normalized[idFromTitle] = entry.value;
    } else {
      normalized[key] = entry.value;
    }
  }
  return normalized;
}

Map<String, dynamic> _normalizeTableRowInput(Map<String, dynamic> row) {
  // `table:set` rows may be either `{id, cells: {col: value}}` (tool shape)
  // or `{id, col: value}` (legacy shape). Normalize to the top-level shape.
  final cells = row['cells'];
  if (cells is Map) {
    return <String, dynamic>{
      'id': row['id'],
      ...Map<String, dynamic>.from(
        cells.map((k, v) => MapEntry(k.toString(), v)),
      ),
    };
  }
  return row;
}

dynamic _tableDefaultCellValue(String? type) {
  switch (type) {
    case 'number':
      return 0;
    case 'date':
      return DateTime.now().toUtc().toIso8601String().split('T').first;
    case 'select':
    case 'text':
    default:
      return '';
  }
}

dynamic _tableCastCellValue(dynamic value, dynamic type) {
  if (value == null) return _tableDefaultCellValue(type?.toString());
  switch (type?.toString()) {
    case 'number':
      if (value is num) return value;
      return double.tryParse(value.toString()) ?? 0;
    case 'date':
    case 'select':
    case 'text':
    default:
      return value.toString();
  }
}

RemotePanelActionResult _calendar(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  final events = _maps(panel.state['events']);
  switch (action) {
    case 'events':
      return RemotePanelActionResult(
        data: {'events': events, 'count': events.length},
      );
    case 'create-event':
    case 'add-event':
      final title = _string(args['title']);
      if (title == null || title.isEmpty) return _missing('title');
      final start = DateTime.tryParse(args['start']?.toString() ?? '');
      if (start == null) return _missing('start');
      final event = <String, dynamic>{
        'id': _timestampId('ev'),
        'title': title,
        'start': start.toUtc().toIso8601String(),
        'end': _parseOptionalDate(args['end'])?.toUtc().toIso8601String(),
        'allDay': args['allDay'] == true ||
            args['allDay']?.toString().toLowerCase() == 'true',
        'description': _string(args['description']) ?? '',
        'color': _string(args['color']) ?? '',
        'meetingUrl': _string(args['meetingUrl'] ?? args['url']) ?? '',
      };
      events.add(event);
      return RemotePanelActionResult(
        stateUpdate: {'events': events, 'eventCount': events.length},
        data: {'event': event},
      );
    case 'update-event':
      final eventId = _string(args['eventId'] ?? args['id']);
      if (eventId == null || eventId.isEmpty) return _missing('eventId');
      final index = events.indexWhere((event) => event['id'] == eventId);
      if (index < 0) return _notFound('Event');
      final existing = events[index];
      events[index] = <String, dynamic>{
        ...existing,
        if (args.containsKey('title')) 'title': _string(args['title']) ?? '',
        if (args.containsKey('start'))
          'start':
              _parseOptionalDate(args['start'])?.toUtc().toIso8601String() ??
              existing['start'],
        if (args.containsKey('end'))
          'end': _parseOptionalDate(args['end'])?.toUtc().toIso8601String(),
        if (args.containsKey('allDay'))
          'allDay': args['allDay'] == true ||
              args['allDay']?.toString().toLowerCase() == 'true',
        if (args.containsKey('description'))
          'description': _string(args['description']) ?? '',
        if (args.containsKey('color')) 'color': _string(args['color']) ?? '',
        if (args.containsKey('meetingUrl') || args.containsKey('url'))
          'meetingUrl': _string(args['meetingUrl'] ?? args['url']) ?? '',
      };
      return RemotePanelActionResult(
        stateUpdate: {'events': events, 'eventCount': events.length},
        data: {'event': events[index]},
      );
    case 'delete-event':
      final eventId = _string(args['eventId'] ?? args['id']);
      if (eventId == null || eventId.isEmpty) return _missing('eventId');
      events.removeWhere((event) => event['id'] == eventId);
      return RemotePanelActionResult(
        stateUpdate: {'events': events, 'eventCount': events.length},
      );
    case 'set-view':
      final view = _string(args['view']);
      const allowed = {'month', 'week', 'workWeek', 'day', 'threeDay', 'list'};
      if (view == null || !allowed.contains(view)) {
        return RemotePanelActionResult(
          ok: false,
          message: 'Invalid view. Allowed: ${allowed.join(', ')}',
        );
      }
      return RemotePanelActionResult(
        stateUpdate: {...panel.state, 'view': view},
      );
    case 'focus-date':
      final date = _parseOptionalDate(args['date'] ?? args['focusedDate']);
      if (date == null) return _missing('date');
      return RemotePanelActionResult(
        stateUpdate: {
          ...panel.state,
          'focusedDate': _dateOnly(date).toUtc().toIso8601String(),
        },
      );
    case 'scroll-to-time':
      final hour = int.tryParse(args['hour']?.toString() ?? '');
      if (hour == null || hour < 0 || hour > 23) {
        return _missing('hour (0-23)');
      }
      return RemotePanelActionResult(
        stateUpdate: {...panel.state, 'scrollHour': hour},
      );
  }
  return _unknown(action);
}

DateTime? _parseOptionalDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

RemotePanelActionResult _chart(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  switch (action) {
    case 'get':
      return RemotePanelActionResult(
        data: {
          'type': panel.state['type'] ?? 'line',
          'data': panel.state['data'] ?? const <Map<String, dynamic>>[],
          'xKey': panel.state['xKey'] ?? 'month',
          'yKey': panel.state['yKey'] ?? 'sales',
          'groupKey': panel.state['groupKey'],
          'tablePanelId': panel.state['tablePanelId'],
          'animated': panel.state['animated'] ?? true,
        },
      );
    case 'set-data':
      final data = _maps(args['data'] ?? args['json']);
      return RemotePanelActionResult(
        stateUpdate: {...panel.state, 'data': data},
      );
    case 'set-type':
      final type = _string(args['type']);
      const allowed = {'line', 'bar', 'pie', 'scatter', 'radar', 'area'};
      if (type == null || !allowed.contains(type)) {
        return RemotePanelActionResult(
          ok: false,
          message: 'Invalid type. Allowed: ${allowed.join(', ')}',
        );
      }
      return RemotePanelActionResult(
        stateUpdate: {...panel.state, 'type': type},
      );
    case 'set-options':
      final next = Map<String, dynamic>.from(panel.state);
      final xKey = _string(args['xKey'] ?? args['x']);
      final yKey = _string(args['yKey'] ?? args['y']);
      final groupKey = _string(args['groupKey'] ?? args['group']);
      if (xKey != null) next['xKey'] = xKey;
      if (yKey != null) next['yKey'] = yKey;
      if (groupKey != null) {
        next['groupKey'] = groupKey.isEmpty ? null : groupKey;
      }
      if (args['animated'] is bool) next['animated'] = args['animated'];
      return RemotePanelActionResult(stateUpdate: next);
    case 'link-table':
      final tablePanelId = _string(args['tablePanelId'] ?? args['table']);
      if (tablePanelId == null || tablePanelId.isEmpty) {
        return _missing('tablePanelId');
      }
      return RemotePanelActionResult(
        stateUpdate: {...panel.state, 'tablePanelId': tablePanelId},
      );
    case 'unlink-table':
      return RemotePanelActionResult(
        stateUpdate: {...panel.state, 'tablePanelId': null},
      );
    case 'refresh':
      return RemotePanelActionResult(
        message: 'Refresh requires board context; state unchanged',
        data: {'tablePanelId': panel.state['tablePanelId']},
      );
  }
  return _unknown(action);
}

RemotePanelActionResult _uiView(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  switch (action) {
    case 'get':
      final tree =
          UiViewPluginBase.treeFromState(panel.state) ??
          UiViewPluginBase.defaultTree();
      final storage = UiViewBindings.storageFromState(panel.state);
      final resolved = UiViewBindings.applyTree(tree, storage);
      return RemotePanelActionResult(
        data: <String, dynamic>{
          'tree': tree,
          'resolvedTree': resolved,
          'storage': storage,
          'scripts': UiViewBindings.scriptsFromState(panel.state),
          'text': AppCliUtils.extractTextLines(resolved),
          if (panel.state['_lastEvent'] != null)
            'lastEvent': panel.state['_lastEvent'],
        },
      );
    case 'render':
      final tree = parseUiTree(args['tree'] ?? args['json']);
      if (tree == null) {
        return const RemotePanelActionResult(
          ok: false,
          message: 'Missing or invalid "tree" (must be a JSON object)',
        );
      }
      return RemotePanelActionResult(
        message: 'UI tree rendered',
        stateUpdate: <String, dynamic>{
          'tree': tree,
          '_storage': UiViewBindings.seedFieldsFromTree(
            tree,
            UiViewBindings.storageFromState(panel.state),
          ),
          '_lastEvent': null,
        },
      );
    case 'set-state':
      final patch = parseUiStatePatch(args['state'] ?? args['storage']);
      if (patch == null) {
        return const RemotePanelActionResult(
          ok: false,
          message: 'Missing or invalid "state" object',
        );
      }
      final current = UiViewBindings.storageFromState(panel.state);
      return RemotePanelActionResult(
        message: 'UI storage updated',
        stateUpdate: <String, dynamic>{
          '_storage': <String, dynamic>{...current, ...patch},
        },
      );
    case 'set-scripts':
      final patch = parseUiScriptsPatch(args['scripts'] ?? args['_scripts']);
      if (patch == null) {
        return const RemotePanelActionResult(
          ok: false,
          message: 'Missing or invalid "scripts" object',
        );
      }
      final currentScripts = UiViewBindings.scriptsFromState(panel.state);
      return RemotePanelActionResult(
        message: 'UI scripts updated',
        stateUpdate: <String, dynamic>{
          '_scripts': <String, dynamic>{...currentScripts, ...patch},
        },
      );
  }
  return _unknown(action);
}

RemotePanelActionResult _diffPreview(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  switch (action) {
    case 'open':
      final path = args['path'] ?? args['filePath'];
      if (path == null) return _missing('path');
      return RemotePanelActionResult(
        stateUpdate: {
          'filePath': path.toString(),
          if (args['title'] != null) 'title': args['title'],
        },
      );
    case 'set-root':
      final root = args['rootPath'] ?? args['path'];
      if (root == null) return _missing('rootPath');
      return RemotePanelActionResult(
        stateUpdate: {'rootPath': root.toString()},
      );
  }
  return _unknown(action);
}

RemotePanelActionResult _yoloAssistant(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  switch (action) {
    case 'get':
      return RemotePanelActionResult(
        data: Map<String, dynamic>.from(panel.state),
      );
    case 'set-mode':
      final mode = args['mode']?.toString();
      if (mode == null) return _missing('mode');
      return RemotePanelActionResult(stateUpdate: {'mode': mode});
    case 'set-status':
      final status = args['status']?.toString();
      if (status == null) return _missing('status');
      return RemotePanelActionResult(stateUpdate: {'assistantStatus': status});
    case 'clear':
      return const RemotePanelActionResult(
        stateUpdate: {
          'messages': <Map<String, dynamic>>[],
          'voiceDraft': '',
          'voiceResponse': '',
        },
      );
  }
  return _unknown(action);
}

RemotePanelActionResult _customWidget(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  switch (action) {
    case 'get':
      return RemotePanelActionResult(
        data: Map<String, dynamic>.from(panel.state),
      );
    case 'set-widget':
      final widgetId = args['widgetId']?.toString();
      if (widgetId == null) return _missing('widgetId');
      return RemotePanelActionResult(stateUpdate: {'widgetId': widgetId});
    case 'set-config':
      return RemotePanelActionResult(
        stateUpdate: {
          'config': {..._map(panel.state['config']), ..._map(args['config'])},
        },
      );
    case 'set':
      final update = Map<String, dynamic>.from(args)..remove('action');
      return RemotePanelActionResult(stateUpdate: update);
  }
  return _unknown(action);
}

RemotePanelActionResult _generic(
  RemotePanel panel,
  String action,
  Map<String, dynamic> args,
) {
  if (action == 'set') {
    final update = Map<String, dynamic>.from(args)..remove('action');
    return RemotePanelActionResult(stateUpdate: update);
  }
  return _unknown(action);
}

RemotePanelActionResult _missing(String field) =>
    RemotePanelActionResult(ok: false, message: 'Missing "$field"');
RemotePanelActionResult _notFound(String entity) =>
    RemotePanelActionResult(ok: false, message: '$entity not found');
RemotePanelActionResult _unknown(String action) =>
    RemotePanelActionResult(ok: false, message: 'Unknown action: $action');

Map<String, dynamic> _pick(Map<String, dynamic> args, List<String> keys) =>
    <String, dynamic>{
      for (final key in keys)
        if (args.containsKey(key)) key: args[key],
    };

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? value) =>
    (value as List? ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
List<String> _strings(Object? value) =>
    (value as List? ?? const <Object?>[])
        .map((entry) => entry.toString())
        .toList();

List<String> _columns(RemotePanel panel) {
  final columns = panel.state['columns'];
  if (columns is List) return columns.map((entry) => entry.toString()).toList();
  return <String>['Todo', 'Doing', 'Done'];
}

List<Map<String, dynamic>> _cards(RemotePanel panel) =>
    _maps(panel.state['cards']);
List<Map<String, dynamic>> _items(RemotePanel panel) =>
    _maps(panel.state['items']);

int _columnIndex(List<String> columns, Object? value) {
  if (value is num) return value.toInt();
  final text = value?.toString();
  if (text == null) return -1;
  final parsed = int.tryParse(text);
  if (parsed != null) return parsed;
  return columns.indexWhere(
    (column) => column.toLowerCase() == text.toLowerCase(),
  );
}

int _itemIndex(List<Map<String, dynamic>> items, Map<String, dynamic> args) {
  if (args['index'] is num) return (args['index'] as num).toInt();
  final id = args['id']?.toString();
  if (id != null) {
    final index = items.indexWhere((item) => item['id'] == id);
    if (index >= 0) return index;
  }
  final text = args['text']?.toString();
  if (text != null) return items.indexWhere((item) => item['text'] == text);
  return -1;
}

int _int(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int _duration(Object? value) => _int(value, fallback: 300).clamp(1, 86400);

String _timestampId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

String? _string(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
