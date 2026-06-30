
enum YoloitCliToolParamKind { string, number, boolean }
enum YoloitCliRuntimeDefault { board, panel }

class YoloitCliToolParam {
  const YoloitCliToolParam({
    required this.key,
    required this.description,
    this.required = false,
    this.flag,
    this.kind = YoloitCliToolParamKind.string,
    this.aliases = const <String>[],
    this.runtimeDefault,
    this.enumValues = const <String>[],
    this.shortKey,
  });

  final String key;
  final String description;
  final bool required;
  final String? flag;
  final YoloitCliToolParamKind kind;
  final List<String> aliases;
  final YoloitCliRuntimeDefault? runtimeDefault;
  final List<String> enumValues;
  final String? shortKey;

  bool get isFlag => flag != null;

  /// Compact key exposed in the LLM tool schema. When a shortKey is defined
  /// it is used; otherwise the param key is exposed in lowercase.
  String get compactKey => shortKey ?? key.toLowerCase();

  /// The lowercase form of [key], used by some model providers as the property
  /// name even when a shortKey is present.
  String get lowerKey => key.toLowerCase();

  /// The canonical key used to look up values after normalization. Accepts
  /// the original key, the short key, the compact schema key, and the raw
  /// lowercase key for providers that normalize property names.
  Iterable<String> get lookupKeys sync* {
    yield key;
    if (shortKey != null) yield shortKey!;
    final compact = compactKey;
    if (compact != key && compact != shortKey) yield compact;
    final lower = lowerKey;
    if (lower != key && lower != shortKey && lower != compact) yield lower;
    yield* aliases;
  }

  Map<String, Object?> toJsonSchema() {
    final type = switch (kind) {
      YoloitCliToolParamKind.string => 'string',
      YoloitCliToolParamKind.number => 'number',
      YoloitCliToolParamKind.boolean => 'boolean',
    };
    return <String, Object?>{
      'type': type,
      'description': description,
      if (enumValues.isNotEmpty) 'enum': enumValues,
    };
  }

  Map<String, Object?> toCompactJsonSchema() {
    final type = switch (kind) {
      YoloitCliToolParamKind.string => 'string',
      YoloitCliToolParamKind.number => 'number',
      YoloitCliToolParamKind.boolean => 'boolean',
    };
    return <String, Object?>{
      'type': type,
      if (enumValues.isNotEmpty) 'enum': enumValues,
    };
  }
}
YoloitCliToolParam toolParam(
  String key,
  String description, {
  bool required = false,
  String? flag,
  YoloitCliToolParamKind kind = YoloitCliToolParamKind.string,
  List<String> aliases = const <String>[],
  YoloitCliRuntimeDefault? runtimeDefault,
  List<String> enumValues = const <String>[],
  String? shortKey,
}) {
  return YoloitCliToolParam(
    key: key,
    description: description,
    required: required,
    flag: flag,
    kind: kind,
    aliases: aliases,
    runtimeDefault: runtimeDefault,
    enumValues: enumValues,
    shortKey: shortKey,
  );
}

YoloitCliToolParam boardParam([String key = 'board']) {
  return toolParam(
    key,
    'Board id or name. Defaults to the current board.',
    required: true,
    aliases: const <String>[
      'board',
      'id_or_name',
      'board_id',
      'board_name',
      'id',
    ],
    runtimeDefault: YoloitCliRuntimeDefault.board,
    shortKey: 'b',
  );
}

YoloitCliToolParam panelParam([String key = 'panel']) {
  return toolParam(
    key,
    'Panel id or title. Defaults to current panel. '
    'For note/checklist/kanban/ui tools, omit to auto-resolve by panel type (not chat).',
    required: true,
    aliases: const <String>['panel_id', 'panel_title', 'id'],
    runtimeDefault: YoloitCliRuntimeDefault.panel,
    shortKey: 'p',
  );
}

/// Panel selector for smart-parse CLI commands (`[board] [panel] <payload>`).
/// Omit panel to let bash auto-resolve the only/first panel of that type.
YoloitCliToolParam optionalPanelParam([String key = 'panel']) {
  return toolParam(
    key,
    'Panel id or title. Omit to auto-resolve the only/first panel of this type.',
    required: false,
    aliases: const <String>['panel_id', 'panel_title', 'id'],
    runtimeDefault: YoloitCliRuntimeDefault.panel,
    shortKey: 'p',
  );
}

YoloitCliToolParam modelIdParam({bool required = true}) {
  return toolParam(
    'model_id',
    'Local model id',
    required: required,
    aliases: const <String>['id'],
    shortKey: 'mid',
  );
}

YoloitCliToolParam boardFlagParam() {
  return toolParam(
    'board',
    'Target board',
    flag: '--board',
    runtimeDefault: YoloitCliRuntimeDefault.board,
    shortKey: 'b',
  );
}

YoloitCliToolParam panelFlagParam() {
  return toolParam(
    'panel',
    'Target panel',
    flag: '--panel',
    runtimeDefault: YoloitCliRuntimeDefault.panel,
    shortKey: 'p',
  );
}

YoloitCliToolParam panelTypeParam() {
  return toolParam(
    'type',
    'Required panel type id. '
        'board.note.markdown = markdown note; '
        'board.kanban = kanban board; '
        'board.run = terminal/run configs; '
        'board.terminal = interactive terminal panel; '
        'board.chat = AI chat panel; '
        'board.checklist = checklist; '
        'board.calendar = calendar with local event storage; '
        'board.webpage = web browser; '
        'board.playlist = media playlist; '
        'board.filetree = FILE TREE BROWSER (use this when user asks for file tree, directory tree, folder browser, or "дерево файлов"); '
        'board.code.snippet = code snippet viewer; '
        'board.files = file attachments panel; '
        'board.file.preview = file/image/video preview; '
        'board.sticky = Miro-style sticky note; '
        'board.shape = geometric shape or frame panel; '
        'board.timer = countdown timer; '
        'board.yolo_assistant = YoLo voice assistant; '
        'board.run_configs = run configurations; '
        'board.table = editable spreadsheet table; '
        'board.chart = animated chart (line/bar/pie/scatter/radar/area) with inline JSON or linked table data; '
        'board.widget.custom = custom JS widget.',
    required: true,
    aliases: const <String>['panel_type', 'kind'],
    enumValues: const <String>[
      'board.note.markdown',
      'board.kanban',
      'board.run',
      'board.terminal',
      'board.chat',
      'board.checklist',
      'board.calendar',
      'board.webpage',
      'board.playlist',
      'board.filetree',
      'board.code.snippet',
      'board.files',
      'board.file.preview',
      'board.sticky',
      'board.shape',
      'board.timer',
      'board.yolo_assistant',
      'board.run_configs',
      'board.table',
      'board.chart',
      'board.ui',
      'board.widget.custom',
    ],
    shortKey: 'tp',
  );
}
