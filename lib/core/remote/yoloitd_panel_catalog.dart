const List<String> _portableLocalPlatforms = <String>[
  'macos',
  'linux',
  'windows',
  'ios',
];

const List<String> _hostLocalPlatforms = <String>['macos', 'linux', 'windows'];

class RemotePanelTypeDescriptor {
  const RemotePanelTypeDescriptor({
    required this.type,
    required this.displayName,
    required this.defaultWidth,
    required this.defaultHeight,
    required this.actions,
    List<String>? localPlatforms,
    this.remotePlatforms = const <String>['macos', 'linux', 'windows', 'ios'],
    this.requiresNativeHost = false,
    this.supportsRemoteState = true,
    this.supportsHeadlessPreview = true,
  }) : localPlatforms =
           localPlatforms ??
           (requiresNativeHost ? _hostLocalPlatforms : _portableLocalPlatforms);

  final String type;
  final String displayName;
  final double defaultWidth;
  final double defaultHeight;
  final List<String> actions;

  /// Platforms where this panel can run using the local device/runtime.
  final List<String> localPlatforms;

  /// Platforms where this panel is available through a remote yoloitd host.
  final List<String> remotePlatforms;

  /// True for panels whose live behavior needs host processes, filesystem,
  /// terminals, WebView, or native players. iOS can still use them remotely.
  final bool requiresNativeHost;

  /// Whether the daemon can persist and mutate this panel's declarative state.
  final bool supportsRemoteState;

  /// Whether overview/offscreen rendering may use the real Flutter widget.
  final bool supportsHeadlessPreview;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type,
    'displayName': displayName,
    'defaultSize': <String, dynamic>{
      'width': defaultWidth,
      'height': defaultHeight,
    },
    'actions': actions,
    'capabilities': <String, dynamic>{
      'localPlatforms': localPlatforms,
      'remotePlatforms': remotePlatforms,
      'requiresNativeHost': requiresNativeHost,
      'supportsRemoteState': supportsRemoteState,
      'supportsHeadlessPreview': supportsHeadlessPreview,
    },
  };

  bool isAvailableOn(String platform, {required bool remote}) {
    final normalized = platform.trim().toLowerCase();
    final allowed = remote ? remotePlatforms : localPlatforms;
    return allowed.contains(normalized);
  }
}

const List<RemotePanelTypeDescriptor>
yoloitdPanelDescriptors = <RemotePanelTypeDescriptor>[
  RemotePanelTypeDescriptor(
    type: 'board.note.markdown',
    displayName: 'Markdown Note',
    defaultWidth: 360,
    defaultHeight: 220,
    actions: <String>['get', 'set', 'append', 'wrap', 'nowrap'],
  ),
  RemotePanelTypeDescriptor(
    type: 'board.sticky',
    displayName: 'Sticky Note',
    defaultWidth: 260,
    defaultHeight: 220,
    actions: <String>['get', 'set', 'append', 'color'],
  ),
  RemotePanelTypeDescriptor(
    type: 'board.shape',
    displayName: 'Shape / Frame',
    defaultWidth: 300,
    defaultHeight: 220,
    actions: <String>['get', 'set'],
  ),
  RemotePanelTypeDescriptor(
    type: 'board.kanban',
    displayName: 'Kanban Board',
    defaultWidth: 640,
    defaultHeight: 420,
    actions: <String>[
      'columns',
      'cards',
      'add-column',
      'rename-column',
      'remove-column',
      'add-card',
      'move-card',
      'remove-card',
      'update-card',
    ],
  ),
  RemotePanelTypeDescriptor(
    type: 'board.webpage',
    displayName: 'Webpage',
    defaultWidth: 700,
    defaultHeight: 500,
    actions: <String>['get', 'open'],
    requiresNativeHost: true,
    supportsHeadlessPreview: false,
  ),
  RemotePanelTypeDescriptor(
    type: 'board.code.snippet',
    displayName: 'Code Snippet',
    defaultWidth: 480,
    defaultHeight: 300,
    actions: <String>['get', 'set'],
  ),
  RemotePanelTypeDescriptor(
    type: 'board.checklist',
    displayName: 'Checklist',
    defaultWidth: 320,
    defaultHeight: 320,
    actions: <String>['items', 'add', 'check', 'uncheck', 'remove', 'rename'],
  ),
  RemotePanelTypeDescriptor(
    type: 'board.files',
    displayName: 'Files',
    defaultWidth: 360,
    defaultHeight: 320,
    actions: <String>['get', 'open', 'add', 'remove', 'clear'],
    requiresNativeHost: true,
  ),
  RemotePanelTypeDescriptor(
    type: 'board.file.preview',
    displayName: 'File Preview',
    defaultWidth: 460,
    defaultHeight: 380,
    actions: <String>['get', 'open'],
    requiresNativeHost: true,
  ),
  RemotePanelTypeDescriptor(
    type: 'board.playlist',
    displayName: 'Playlist',
    defaultWidth: 380,
    defaultHeight: 480,
    actions: <String>[
      'list',
      'add',
      'remove',
      'play',
      'pause',
      'stop',
      'next',
      'prev',
    ],
    requiresNativeHost: true,
    supportsHeadlessPreview: false,
  ),
  RemotePanelTypeDescriptor(
    type: 'board.run',
    displayName: 'Run',
    defaultWidth: 560,
    defaultHeight: 360,
    actions: <String>['get', 'set-group', 'select-session', 'clear-session'],
    requiresNativeHost: true,
    supportsHeadlessPreview: false,
  ),
  RemotePanelTypeDescriptor(
    type: 'board.run_configs',
    displayName: 'Run Configs',
    defaultWidth: 600,
    defaultHeight: 400,
    actions: <String>['get', 'set-group', 'select-session', 'clear-session'],
    requiresNativeHost: true,
    supportsHeadlessPreview: false,
  ),
  RemotePanelTypeDescriptor(
    type: 'board.setup_guide',
    displayName: 'Setup Guide',
    defaultWidth: 560,
    defaultHeight: 520,
    actions: <String>['get', 'select', 'unselect', 'set-selected'],
    requiresNativeHost: true,
  ),
  RemotePanelTypeDescriptor(
    type: 'board.chat',
    displayName: 'AI Chat',
    defaultWidth: 420,
    defaultHeight: 500,
    actions: <String>['messages', 'send', 'config', 'clear', 'status'],
    requiresNativeHost: true,
  ),
  RemotePanelTypeDescriptor(
    type: 'board.terminal',
    displayName: 'Terminal',
    defaultWidth: 520,
    defaultHeight: 360,
    actions: <String>['config', 'set-dir', 'set-session'],
    requiresNativeHost: true,
    supportsHeadlessPreview: false,
  ),
  RemotePanelTypeDescriptor(
    type: 'board.filetree',
    displayName: 'File Tree',
    defaultWidth: 320,
    defaultHeight: 500,
    actions: <String>[
      'list',
      'open',
      'expand',
      'collapse',
      'set-root',
      'refresh',
    ],
    requiresNativeHost: true,
  ),
  RemotePanelTypeDescriptor(
    type: 'board.diff.preview',
    displayName: 'Diff Preview',
    defaultWidth: 600,
    defaultHeight: 500,
    actions: <String>['get', 'open', 'set-root'],
    requiresNativeHost: true,
  ),
  RemotePanelTypeDescriptor(
    type: 'board.yolo_assistant',
    displayName: 'YoLo Assistant',
    defaultWidth: 420,
    defaultHeight: 560,
    actions: <String>['get', 'set-mode', 'set-status', 'clear'],
    requiresNativeHost: true,
  ),
  RemotePanelTypeDescriptor(
    type: 'board.widget.custom',
    displayName: 'Custom Widget',
    defaultWidth: 360,
    defaultHeight: 420,
    actions: <String>['get', 'set-widget', 'set-config', 'set'],
  ),
  RemotePanelTypeDescriptor(
    type: 'board.timer',
    displayName: 'Timer',
    defaultWidth: 300,
    defaultHeight: 360,
    actions: <String>['status', 'set', 'start', 'pause', 'resume', 'reset'],
  ),
  RemotePanelTypeDescriptor(
    type: 'board.calendar',
    displayName: 'Calendar',
    defaultWidth: 720,
    defaultHeight: 520,
    actions: <String>[
      'events',
      'create-event',
      'update-event',
      'delete-event',
      'set-view',
    ],
  ),
  RemotePanelTypeDescriptor(
    type: 'board.table',
    displayName: 'Table',
    defaultWidth: 520,
    defaultHeight: 360,
    actions: <String>[
      'get',
      'set',
      'add-column',
      'rename-column',
      'remove-column',
      'add-row',
      'update-row',
      'remove-row',
      'clear',
    ],
  ),
  RemotePanelTypeDescriptor(
    type: 'board.chart',
    displayName: 'Chart',
    defaultWidth: 560,
    defaultHeight: 400,
    actions: <String>[
      'get',
      'set-data',
      'set-type',
      'set-options',
      'link-table',
      'refresh',
    ],
  ),
  RemotePanelTypeDescriptor(
    type: 'board.ui',
    displayName: 'UI View',
    defaultWidth: 420,
    defaultHeight: 320,
    actions: <String>['get', 'render', 'set-state', 'set-scripts'],
  ),
];

final List<Map<String, dynamic>> yoloitdPanelTypes = yoloitdPanelDescriptors
    .map((descriptor) => descriptor.toJson())
    .toList(growable: false);

RemotePanelTypeDescriptor? yoloitdPanelDescriptorFor(String type) {
  for (final descriptor in yoloitdPanelDescriptors) {
    if (descriptor.type == type) return descriptor;
  }
  return null;
}

bool yoloitdPanelTypeAvailableOn(
  String type, {
  required String platform,
  required bool remote,
}) {
  final descriptor = yoloitdPanelDescriptorFor(type);
  if (descriptor == null) return false;
  return descriptor.isAvailableOn(platform, remote: remote);
}
