import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/remote/board_relay_client.dart';
import 'package:yoloit/core/remote/board_share_server.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/settings/ui/sections/remote_section.dart';
import 'package:yoloit/ui/components/input/labeled_text_field.dart';

import '../../../helpers/fake_board_cubit.dart';

/// Fake [BoardCubit] that emulates remote connect/disconnect without I/O.
class _RemoteFakeBoardCubit extends FakeBoardCubit {
  bool failConnect = false;

  @override
  Future<List<BoardDocument>> connectRemoteBoards({
    required String url,
    String? token,
  }) async {
    if (failConnect) throw StateError('unreachable');
    final board = BoardDocument(
      id: 'remote-$url',
      name: 'Remote board',
      panels: const [],
      metadata: {
        'remote': {'url': url, 'boardId': 'rb-1'},
      },
    );
    emit(state.copyWith(boards: [...state.boards, board]));
    return [board];
  }

  @override
  Future<void> disconnectRemoteBoardsForUrl(String url) async {
    emit(
      state.copyWith(
        boards:
            state.boards
                .where((board) => remoteInfoForBoard(board)?.url != url)
                .toList(),
      ),
    );
  }
}

/// Minimal yoloit-hub stub: device creation REST endpoint + relay WebSocket.
class _FakeHub {
  HttpServer? _server;
  final bool failDeviceCreation;
  var deviceRequests = 0;

  _FakeHub({this.failDeviceCreation = false});

  Future<int> start() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        // ignore: close_sinks — closed in stop()
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        break;
      } on SocketException {
        if (attempt == 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    _server!.listen(_handle);
    return _server!.port;
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path == '/api/devices' && request.method == 'POST') {
      await utf8.decoder.bind(request).join();
      deviceRequests++;
      if (failDeviceCreation) {
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'ok': false, 'error': 'boom'}));
      } else {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'ok': true, 'deviceId': 'dev-1', 'key': 'k-1'}));
      }
      await request.response.close();
      return;
    }
    if (request.uri.path == '/api/relay/connect') {
      // ignore: close_sinks — the upgraded socket dies with the test server
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((_) {});
      return;
    }
    request.response.statusCode = 404;
    await request.response.close();
  }

  Future<void> stop() => _server?.close(force: true) ?? Future<void>.value();
}

Future<void> _pumpSection(
  WidgetTester tester,
  _RemoteFakeBoardCubit cubit,
) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        body: BlocProvider<BoardCubit>.value(
          value: cubit,
          child: const SingleChildScrollView(child: RemoteSection()),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _fieldOf(String label) => find.descendant(
  of: find.widgetWithText(LabeledTextField, label),
  matching: find.byType(TextField),
);

/// Waits until [condition] holds or the deadline passes (inside runAsync).
Future<void> _waitFor(bool Function() condition, String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Advances fake time past the 4s SnackBar timer so tests end clean.
///
/// Pumps in steps: a single big pump renders one frame at the end, so the
/// entrance animation and the dismiss timer would not interleave.
Future<void> _flushSnackbars(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  setUp(() {
    // TestWidgetsFlutterBinding installs a mock HttpOverrides that answers
    // every request with an empty 400; these tests run a real loopback hub.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await BoardRelayClient.instance.stop();
    BoardRelayClient.instance.lastError.value = null;
    await BoardShareServer.instance.stop();
  });

  group('RemoteSection — connect card', () {
    testWidgets('renders all three cards with empty state', (tester) async {
      await _pumpSection(tester, _RemoteFakeBoardCubit());

      expect(find.text('Connect to a YoLoIT server'), findsOneWidget);
      expect(find.text('Share this device'), findsOneWidget);
      expect(find.text('Share via yoloit-hub'), findsOneWidget);
      expect(find.text('No remote servers connected.'), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);
    });

    testWidgets('connect without URL shows a validation snackbar', (
      tester,
    ) async {
      await _pumpSection(tester, _RemoteFakeBoardCubit());

      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(find.text('Enter the server URL'), findsOneWidget);
      await _flushSnackbars(tester);
    });

    testWidgets('connect adds remote boards and disconnect removes them', (
      tester,
    ) async {
      final cubit = _RemoteFakeBoardCubit();
      await _pumpSection(tester, cubit);

      await tester.enterText(_fieldOf('Server URL'), 'http://hub.local:43110');
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Connected 1 board from http://hub.local:43110'),
        findsOneWidget,
      );
      await _flushSnackbars(tester);

      // Connected list shows the server with a Disconnect action.
      expect(find.text('Connected servers'), findsOneWidget);
      expect(find.text('http://hub.local:43110'), findsOneWidget);
      expect(find.text('1 board'), findsOneWidget);

      await tester.tap(find.text('Disconnect'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Disconnected from http://hub.local:43110'),
        findsOneWidget,
      );
      expect(find.text('No remote servers connected.'), findsOneWidget);
      await _flushSnackbars(tester);
    });

    testWidgets('connect failure surfaces the error', (tester) async {
      final cubit = _RemoteFakeBoardCubit()..failConnect = true;
      await _pumpSection(tester, cubit);

      await tester.enterText(_fieldOf('Server URL'), 'http://hub.local:43110');
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Connection failed:'), findsOneWidget);
      await _flushSnackbars(tester);
    });
  });

  group('RemoteSection — LAN sharing card', () {
    testWidgets('start and stop sharing toggles the info rows', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') return null;
            return null;
          });

      final cubit = _RemoteFakeBoardCubit();
      await _pumpSection(tester, cubit);

      await tester.runAsync(() async {
        await tester.tap(find.text('Start sharing'));
        await _waitFor(
          () => BoardShareServer.instance.isRunning,
          'share server start',
        );
      });
      await tester.pump();

      // URL / Token rows appear once the server is running.
      expect(find.text('URL'), findsOneWidget);
      expect(find.text('Token'), findsOneWidget);
      expect(find.text('Stop sharing'), findsOneWidget);

      // Copy exercises the clipboard helper + copied-state toggle.
      await tester.tap(find.byTooltip('Copy URL'));
      await tester.pump();
      expect(find.byTooltip('Copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));

      await tester.runAsync(() async {
        await tester.tap(find.text('Stop sharing'));
        await _waitFor(
          () => !BoardShareServer.instance.isRunning,
          'share server stop',
        );
      });
      await tester.pump();

      expect(find.text('Start sharing'), findsOneWidget);
    });
  });

  group('RemoteSection — hub relay card', () {
    testWidgets('relay start without hub URL shows a validation snackbar', (
      tester,
    ) async {
      await _pumpSection(tester, _RemoteFakeBoardCubit());

      await tester.tap(find.text('Start sharing via hub'));
      await tester.pump();

      expect(find.text('Enter the hub URL'), findsOneWidget);
      await _flushSnackbars(tester);
    });

    testWidgets('relay start without device credentials asks for them', (
      tester,
    ) async {
      await _pumpSection(tester, _RemoteFakeBoardCubit());

      await tester.enterText(_fieldOf('Hub URL'), 'http://127.0.0.1:43199');
      await tester.tap(find.text('Start sharing via hub'));
      await tester.pump();

      expect(
        find.text('Enter Device ID and Device key, or provide Hub admin token'),
        findsOneWidget,
      );
      await _flushSnackbars(tester);
    });

    testWidgets('hub admin token field hides manual device fields', (
      tester,
    ) async {
      await _pumpSection(tester, _RemoteFakeBoardCubit());

      expect(find.text('Device ID'), findsOneWidget);
      await tester.enterText(_fieldOf('Hub admin token (optional)'), 'admin');
      await tester.pump();

      expect(find.text('Device ID'), findsNothing);
      expect(find.text('Device key'), findsNothing);
      expect(find.text('Create device & start sharing'), findsOneWidget);
    });

    testWidgets('relay connects through the hub and shows phone share rows', (
      tester,
    ) async {
      final hub = _FakeHub();
      final port = await tester.runAsync(hub.start);
      addTearDown(() async => tester.runAsync(hub.stop));

      await _pumpSection(tester, _RemoteFakeBoardCubit());

      await tester.runAsync(() async {
        await tester.enterText(_fieldOf('Hub URL'), 'http://127.0.0.1:$port');
        await tester.enterText(_fieldOf('Device ID'), 'dev-1');
        await tester.enterText(_fieldOf('Device key'), 'k-1');
        await tester.tap(find.text('Start sharing via hub'));
        await _waitFor(
          () =>
              BoardRelayClient.instance.status.value ==
              BoardRelayStatus.connected,
          'relay connection',
        );
      });
      await tester.pump();

      expect(find.text('Connected to hub'), findsOneWidget);
      expect(find.text('Sharing'), findsOneWidget);
      expect(find.text('Phone URL'), findsOneWidget);
      expect(
        find.text('http://127.0.0.1:$port/api/devices/dev-1/'),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        await tester.tap(find.text('Stop sharing via hub'));
        await _waitFor(
          () =>
              BoardRelayClient.instance.status.value ==
              BoardRelayStatus.disconnected,
          'relay stop',
        );
      });
      await tester.pump();

      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('Start sharing via hub'), findsOneWidget);
    });

    testWidgets('admin token creates the device then starts the relay', (
      tester,
    ) async {
      final hub = _FakeHub();
      final port = await tester.runAsync(hub.start);
      addTearDown(() async => tester.runAsync(hub.stop));

      await _pumpSection(tester, _RemoteFakeBoardCubit());

      await tester.runAsync(() async {
        await tester.enterText(_fieldOf('Hub URL'), 'http://127.0.0.1:$port');
        await tester.enterText(
          _fieldOf('Hub admin token (optional)'),
          'admin-token',
        );
        await tester.pump();
        await tester.tap(find.text('Create device & start sharing'));
        await _waitFor(
          () =>
              BoardRelayClient.instance.status.value ==
              BoardRelayStatus.connected,
          'relay connection after device creation',
        );
      });
      await tester.pump();

      // Hub-created credentials were adopted and the relay is up.
      expect(hub.deviceRequests, 1);
      expect(find.text('Connected to hub'), findsOneWidget);
      expect(
        find.text('http://127.0.0.1:$port/api/devices/dev-1/'),
        findsOneWidget,
      );

      await tester.runAsync(BoardRelayClient.instance.stop);
    });

    testWidgets('failed device creation shows the hub error', (tester) async {
      final hub = _FakeHub(failDeviceCreation: true);
      final port = await tester.runAsync(hub.start);
      addTearDown(() async => tester.runAsync(hub.stop));

      await _pumpSection(tester, _RemoteFakeBoardCubit());

      await tester.runAsync(() async {
        await tester.enterText(_fieldOf('Hub URL'), 'http://127.0.0.1:$port');
        await tester.enterText(_fieldOf('Hub admin token (optional)'), 'bad');
        await tester.pump();
        await tester.tap(find.text('Create device & start sharing'));
        await _waitFor(() => hub.deviceRequests == 1, 'device creation call');
        // Give the client a moment to process the error response.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.textContaining('Device creation failed:'), findsOneWidget);
      await _flushSnackbars(tester);
    });

    testWidgets('device creation http error is reported', (tester) async {
      await _pumpSection(tester, _RemoteFakeBoardCubit());

      await tester.runAsync(() async {
        // Port 1 refuses connections → http.post throws.
        await tester.enterText(_fieldOf('Hub URL'), 'http://127.0.0.1:1');
        await tester.enterText(_fieldOf('Hub admin token (optional)'), 'bad');
        await tester.pump();
        await tester.tap(find.text('Create device & start sharing'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();

      expect(find.textContaining('Device creation failed:'), findsOneWidget);
      await _flushSnackbars(tester);
    });

    testWidgets('relay error line renders and clears', (tester) async {
      await _pumpSection(tester, _RemoteFakeBoardCubit());

      expect(find.text('relay exploded'), findsNothing);
      BoardRelayClient.instance.lastError.value = 'relay exploded';
      await tester.pump();
      expect(find.text('relay exploded'), findsOneWidget);

      BoardRelayClient.instance.lastError.value = null;
      await tester.pump();
      expect(find.text('relay exploded'), findsNothing);
    });
  });
}
