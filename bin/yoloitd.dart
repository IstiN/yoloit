import 'dart:io';

import 'package:yoloit/core/remote/yoloitd_server.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }

  final store = YoloitdStore(
    rootDir: Directory(options.dataDir),
    actorId: options.actorId,
  );
  final server = YoloitdServer(
    store: store,
    host: options.host,
    port: options.port,
    token: options.token,
  );
  await server.start();
  stdout.writeln(
    'yoloitd listening on http://${options.host}:${server.boundPort} '
    'data=${options.dataDir}',
  );

  ProcessSignal.sigint.watch().listen((_) async {
    await server.stop();
    exit(0);
  });
  ProcessSignal.sigterm.watch().listen((_) async {
    await server.stop();
    exit(0);
  });
}

class _Options {
  const _Options({
    required this.host,
    required this.port,
    required this.dataDir,
    required this.actorId,
    this.token,
    this.help = false,
  });

  final String host;
  final int port;
  final String dataDir;
  final String actorId;
  final String? token;
  final bool help;

  static _Options parse(List<String> args) {
    var host = Platform.environment['YOLOITD_HOST'] ?? '127.0.0.1';
    var port =
        int.tryParse(Platform.environment['YOLOITD_PORT'] ?? '') ?? 43110;
    var dataDir =
        Platform.environment['YOLOITD_DATA_DIR'] ??
        '${Platform.environment['HOME'] ?? Directory.current.path}/.local/share/yoloitd';
    var actorId = Platform.environment['YOLOITD_ACTOR'] ?? 'yoloitd';
    var token = Platform.environment['YOLOITD_TOKEN'];
    var help = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String next() {
        if (i + 1 >= args.length) {
          stderr.writeln('Missing value for $arg');
          exit(64);
        }
        return args[++i];
      }

      switch (arg) {
        case '--help':
        case '-h':
          help = true;
        case '--host':
          host = next();
        case '--port':
          port = int.parse(next());
        case '--data-dir':
          dataDir = next();
        case '--actor':
          actorId = next();
        case '--token':
          token = next();
        default:
          stderr.writeln('Unknown argument: $arg');
          stderr.writeln(_usage);
          exit(64);
      }
    }

    return _Options(
      host: host,
      port: port,
      dataDir: dataDir,
      actorId: actorId,
      token: token,
      help: help,
    );
  }
}

const String _usage = '''
YoLoIT headless daemon.

Usage:
  dart run bin/yoloitd.dart [options]

Options:
  --host <host>        Bind host. Default: 127.0.0.1
  --port <port>        Bind port. Default: 43110
  --data-dir <path>    Persistent storage directory.
  --actor <id>         Actor id for history events. Default: yoloitd
  --token <token>      Require Bearer token or ?token= query auth.

Environment:
  YOLOITD_HOST, YOLOITD_PORT, YOLOITD_DATA_DIR, YOLOITD_ACTOR, YOLOITD_TOKEN

Core API:
  GET  /api/boards/:id/panel-types
  POST /api/boards/:id/panels/:panel/action
  POST /api/terminals, /api/terminals/:id/input
  GET  /api/files?path=<remote-directory>
''';
