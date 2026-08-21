part of 'cli_server.dart';

/// Shared context for top-level API route handlers: the matched request plus
/// the resolved board cubit, so each route handler takes one parameter.
class _ApiRouteContext {
  _ApiRouteContext({
    required this.method,
    required this.path,
    required this.request,
    required this.cubit,
  });

  final String method;
  final List<String> path;
  final shelf.Request request;
  final BoardCubit cubit;
}

/// A top-level API route: either a literal `method` + `segments` match, or a
/// custom `matches` predicate for dynamic segments and prefix catch-alls
/// (e.g. `/api/boards/:boardIdOrName/...`).
typedef _ApiRoute = ({
  String? method,
  List<String>? segments,
  bool Function(String method, List<String> path)? matches,
  Future<shelf.Response> Function(_ApiRouteContext ctx) handler,
});

bool _apiRouteMatches(_ApiRoute route, String method, List<String> path) {
  final predicate = route.matches;
  if (predicate != null) return predicate(method, path);
  if (route.method != method) return false;
  final segments = route.segments!;
  if (segments.length != path.length) return false;
  for (var i = 0; i < segments.length; i++) {
    if (segments[i] != path[i]) return false;
  }
  return true;
}

/// Top-level API route handlers and the route table consumed by
/// [CliServer._handleApi].
extension _ApiRoutes on CliServer {
  // GET /api/vmservice → return VM service WebSocket URI for hot reload
  Future<shelf.Response> _vmServiceRoute(_ApiRouteContext ctx) async {
    _writeVmServiceFile(); // refresh
    final f = File(CliServer._vmServiceFilePath);
    final uri = f.existsSync() ? f.readAsStringSync().trim() : '';
    return cliJson({'vmServiceWsUri': uri, 'ok': uri.isNotEmpty});
  }

  // GET /api/catalog → command catalog with humanVariants for router model
  Future<shelf.Response> _catalogRoute(_ApiRouteContext ctx) async {
    final yamlVariants = await YoloitCliToolCatalog.loadYamlVariants();
    return shelf.Response.ok(
      YoloitCliToolCatalog.catalogJson(yamlVariants),
      headers: {'content-type': 'application/json'},
    );
  }

  // /api/yolochat/...
  Future<shelf.Response> _yoloChatRoute(_ApiRouteContext ctx) {
    return _handleYoloChat(
      ctx.method,
      ctx.path.sublist(1),
      ctx.request,
      ctx.cubit,
    );
  }

  // /api/cloud-providers/...
  Future<shelf.Response> _cloudProvidersRoute(_ApiRouteContext ctx) {
    return _handleCloudProviders(ctx.method, ctx.path.sublist(1), ctx.request);
  }

  // /api/voice-settings/...
  Future<shelf.Response> _voiceSettingsRoute(_ApiRouteContext ctx) {
    return _handleVoiceSettings(ctx.method, ctx.path.sublist(1), ctx.request);
  }

  Future<shelf.Response> _agentsRoute(_ApiRouteContext ctx) {
    return _handleAgents(ctx.method, ctx.path.sublist(1), ctx.request);
  }

  // /api/theme/...
  Future<shelf.Response> _themeRoute(_ApiRouteContext ctx) {
    return _handleTheme(ctx.method, ctx.path.sublist(1), ctx.request);
  }

  Future<shelf.Response> _settingsRoute(_ApiRouteContext ctx) {
    return _handleSettings(ctx.method, ctx.path.sublist(1), ctx.request);
  }

  Future<shelf.Response> _drawingsRoute(_ApiRouteContext ctx) {
    return _handleDrawings(
      ctx.method,
      ctx.path.sublist(1),
      ctx.request,
      ctx.cubit,
    );
  }

  Future<shelf.Response> _searchRoute(_ApiRouteContext ctx) {
    return _handleSearch(
      ctx.method,
      ctx.path.sublist(1),
      ctx.request,
      ctx.cubit,
    );
  }

  // GET /api/active-board → active board details (or first board)
  Future<shelf.Response> _activeBoardRoute(_ApiRouteContext ctx) async {
    final cubit = ctx.cubit;
    final board = cubit.state.activeBoard ?? cubit.state.boards.firstOrNull;
    if (board == null) return cliJson({'board': null});
    return cliJson({
      'board': {
        'id': board.id,
        'name': board.name,
        'panelCount': board.panels.length,
        'defaultFolder': board.defaultFolder,
      },
    });
  }

  // GET /api/templates
  Future<shelf.Response> _listTemplatesRoute(_ApiRouteContext ctx) {
    return _listTemplates();
  }

  // GET /api/templates/:id
  Future<shelf.Response> _templateDetailsRoute(_ApiRouteContext ctx) {
    return _templateDetails(ctx.path[1]);
  }

  // POST /api/templates/sync
  Future<shelf.Response> _syncTemplatesRoute(_ApiRouteContext ctx) {
    return _syncTemplates(ctx.request);
  }

  // GET /api/boards
  Future<shelf.Response> _listBoardsRoute(_ApiRouteContext ctx) async {
    return _listBoards(ctx.cubit, ctx.request);
  }

  // POST /api/boards  { name: "...", templateId?, templateParams? }
  Future<shelf.Response> _createBoardRoute(_ApiRouteContext ctx) async {
    final body = await cliReadJsonBody(ctx.request);
    return _createBoard(ctx.cubit, body);
  }

  // /api/boards/:boardIdOrName/...
  Future<shelf.Response> _boardSubRoute(_ApiRouteContext ctx) {
    final board = findBoard(ctx.cubit, ctx.path[1]);
    if (board == null) {
      return Future.value(cliNotFound('Board not found: ${ctx.path[1]}'));
    }

    final sub = ctx.path.sublist(2);
    return _handleBoard(ctx.method, sub, board, ctx.cubit, ctx.request);
  }

  // /api/widgets
  Future<shelf.Response> _widgetsRoute(_ApiRouteContext ctx) {
    return _handleWidgets(ctx.method, ctx.path.sublist(1), ctx.request);
  }

  // /api/apps
  Future<shelf.Response> _appsRoute(_ApiRouteContext ctx) {
    return _handleApps(ctx.method, ctx.path.sublist(1), ctx.request);
  }

  /// Top-level API route table. Order matters and mirrors the original
  /// if-chain: exact method+segment routes and named prefixes come before
  /// the dynamic `boards/:boardIdOrName/...` catch-all, which in turn comes
  /// before the `widgets`/`apps` prefixes.
  List<_ApiRoute> get _apiRoutes => [
    (
      method: 'GET',
      segments: ['vmservice'],
      matches: null,
      handler: _vmServiceRoute,
    ),
    (
      method: 'GET',
      segments: ['catalog'],
      matches: null,
      handler: _catalogRoute,
    ),
    (
      method: null,
      segments: null,
      matches: (method, path) => path.isNotEmpty && path[0] == 'yolochat',
      handler: _yoloChatRoute,
    ),
    (
      method: null,
      segments: null,
      matches: (method, path) =>
          path.isNotEmpty && path[0] == 'cloud-providers',
      handler: _cloudProvidersRoute,
    ),
    (
      method: null,
      segments: null,
      matches: (method, path) => path.isNotEmpty && path[0] == 'voice-settings',
      handler: _voiceSettingsRoute,
    ),
    (
      method: null,
      segments: null,
      matches: (method, path) => path.isNotEmpty && path[0] == 'agents',
      handler: _agentsRoute,
    ),
    (
      method: null,
      segments: null,
      matches: (method, path) => path.isNotEmpty && path[0] == 'theme',
      handler: _themeRoute,
    ),
    (
      method: null,
      segments: null,
      matches: (method, path) => path.isNotEmpty && path[0] == 'settings',
      handler: _settingsRoute,
    ),
    (
      method: null,
      segments: null,
      matches: (method, path) => path.isNotEmpty && path[0] == 'drawings',
      handler: _drawingsRoute,
    ),
    (
      method: null,
      segments: null,
      matches: (method, path) => path.isNotEmpty && path[0] == 'search',
      handler: _searchRoute,
    ),
    (
      method: 'GET',
      segments: ['active-board'],
      matches: null,
      handler: _activeBoardRoute,
    ),
    (
      method: 'GET',
      segments: ['templates'],
      matches: null,
      handler: _listTemplatesRoute,
    ),
    (
      method: null,
      segments: null,
      matches: (method, path) =>
          path.length == 2 && path[0] == 'templates' && method == 'GET',
      handler: _templateDetailsRoute,
    ),
    (
      method: 'POST',
      segments: ['templates'],
      matches: null,
      handler: _syncTemplatesRoute,
    ),
    (
      method: 'GET',
      segments: ['boards'],
      matches: null,
      handler: _listBoardsRoute,
    ),
    (
      method: 'POST',
      segments: ['boards'],
      matches: null,
      handler: _createBoardRoute,
    ),
    (
      method: null,
      segments: null,
      matches: (method, path) => path.length >= 2 && path[0] == 'boards',
      handler: _boardSubRoute,
    ),
    (
      method: null,
      segments: null,
      matches: (method, path) => path.isNotEmpty && path[0] == 'widgets',
      handler: _widgetsRoute,
    ),
    (
      method: null,
      segments: null,
      matches: (method, path) => path.isNotEmpty && path[0] == 'apps',
      handler: _appsRoute,
    ),
  ];
}
