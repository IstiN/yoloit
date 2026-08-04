import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';

void main() {
  group('local directory mode', () {
    late Directory fixture;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('yoloit_picker_test_');
      Directory(p.join(fixture.path, 'sub')).createSync();
      File(p.join(fixture.path, 'alpha.txt')).writeAsStringSync('a');
      File(p.join(fixture.path, 'beta.md')).writeAsStringSync('b');
      File(p.join(fixture.path, 'sub', 'nested.txt')).writeAsStringSync('n');
    });

    tearDown(() {
      try {
        fixture.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup.
      }
    });

    testWidgets('navigates directories, refreshes and confirms path', (
      tester,
    ) async {
      _useLargeSurface(tester);
      Future<String?>? picked;
      await _openPicker(tester, (context) {
        picked = BoardFilePicker.pickDirectory(
          context,
          initialPath: fixture.path,
        );
      });

      expect(_tile(p.join(fixture.path, 'sub')), findsOneWidget);
      expect(_tile(p.join(fixture.path, 'alpha.txt')), findsOneWidget);
      expect(_tile(p.join(fixture.path, 'beta.md')), findsOneWidget);

      // Tapping a file in directory mode is a no-op.
      await tester.tap(_tile(p.join(fixture.path, 'alpha.txt')));
      await _pumpOut(tester);
      expect(_tile(p.join(fixture.path, 'alpha.txt')), findsOneWidget);

      // Drill into the subdirectory, then go back up.
      await _tapIo(tester, _tile(p.join(fixture.path, 'sub')));
      expect(_tile(p.join(fixture.path, 'sub', 'nested.txt')), findsOneWidget);
      expect(_tile(p.join(fixture.path, 'alpha.txt')), findsNothing);

      await _tapIo(tester, find.byTooltip('Parent folder'));
      expect(_tile(p.join(fixture.path, 'alpha.txt')), findsOneWidget);

      await _tapIo(tester, find.byTooltip('Refresh'));
      expect(_tile(p.join(fixture.path, 'beta.md')), findsOneWidget);

      await tester.tap(find.byKey(const Key('board-file-picker-confirm')));
      await _pumpOut(tester);
      expect(await tester.runAsync(() => picked!), fixture.path);
    });

    testWidgets('root chips jump to well-known locations', (tester) async {
      _useLargeSurface(tester);
      final home = Platform.environment['HOME']!;
      Future<String?>? picked;
      await _openPicker(tester, (context) {
        picked = BoardFilePicker.pickDirectory(
          context,
          initialPath: fixture.path,
        );
      });

      await _tapIo(tester, find.widgetWithText(ActionChip, 'Home'));
      expect(find.text(home), findsWidgets);

      await tester.tap(find.byKey(const Key('board-file-picker-confirm')));
      await _pumpOut(tester);
      expect(await tester.runAsync(() => picked!), home);
    });

    testWidgets('falls back to the home directory without an initial path', (
      tester,
    ) async {
      _useLargeSurface(tester);
      final home = Platform.environment['HOME']!;
      Future<String?>? picked;
      await _openPicker(tester, (context) {
        picked = BoardFilePicker.pickDirectory(context);
      });

      await tester.tap(find.byKey(const Key('board-file-picker-confirm')));
      await _pumpOut(tester);
      expect(await tester.runAsync(() => picked!), home);
    });

    testWidgets('search filters entries and the clear button restores them', (
      tester,
    ) async {
      _useLargeSurface(tester);
      await _openPicker(tester, (context) {
        unawaited(
          BoardFilePicker.pickDirectory(context, initialPath: fixture.path),
        );
      });

      await tester.enterText(find.byKey(_searchKey), 'alpha');
      await tester.pump(const Duration(milliseconds: 200));
      await _pumpOut(tester);
      expect(_tile(p.join(fixture.path, 'alpha.txt')), findsOneWidget);
      expect(_tile(p.join(fixture.path, 'beta.md')), findsNothing);
      expect(find.byTooltip('Clear search'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await _pumpOut(tester);
      expect(_tile(p.join(fixture.path, 'beta.md')), findsOneWidget);

      // Path-like queries are not treated as filters.
      await tester.enterText(find.byKey(_searchKey), '/no-such-place');
      await tester.pump(const Duration(milliseconds: 200));
      await _pumpOut(tester);
      expect(_tile(p.join(fixture.path, 'beta.md')), findsOneWidget);

      await tester.enterText(find.byKey(_searchKey), 'zzz-no-match');
      await tester.pump(const Duration(milliseconds: 200));
      await _pumpOut(tester);
      expect(find.text('No matches in this folder.'), findsOneWidget);
    });

    testWidgets('submitting search navigates paths, tilde and ignores text', (
      tester,
    ) async {
      _useLargeSurface(tester);
      final home = Platform.environment['HOME']!;
      await _openPicker(tester, (context) {
        unawaited(
          BoardFilePicker.pickDirectory(context, initialPath: fixture.path),
        );
      });

      // Blank submissions are ignored.
      await _submitSearch(tester, '   ');
      expect(find.text(fixture.path), findsWidgets);

      // Plain text is not a path: no navigation happens.
      await _submitSearch(tester, 'alpha');
      expect(find.text(fixture.path), findsWidgets);

      // '~' resolves through the Home root entry.
      await _submitSearchIo(tester, '~');
      expect(find.text(home), findsWidgets);

      // An absolute path loads that directory.
      await _submitSearchIo(tester, fixture.path);
      expect(_tile(p.join(fixture.path, 'alpha.txt')), findsOneWidget);
    });

    testWidgets('create folder validates input and creates directories', (
      tester,
    ) async {
      _useLargeSurface(tester);
      await _openPicker(tester, (context) {
        unawaited(
          BoardFilePicker.pickDirectory(context, initialPath: fixture.path),
        );
      });

      // Cancel leaves the filesystem untouched.
      await _tapIo(tester, find.byKey(const Key('board-file-picker-new-folder')));
      expect(find.text('New folder'), findsOneWidget);
      await _tapIo(tester, _folderDialogCancel());
      expect(Directory(p.join(fixture.path, 'created')).existsSync(), isFalse);

      // An empty name is rejected silently.
      await _tapIo(tester, find.byKey(const Key('board-file-picker-new-folder')));
      await _tapIo(
        tester,
        find.byKey(const Key('board-file-picker-create-folder-confirm')),
      );
      expect(_tile(p.join(fixture.path, 'alpha.txt')), findsOneWidget);

      // A name with a separator fails and surfaces a snackbar.
      await _tapIo(tester, find.byKey(const Key('board-file-picker-new-folder')));
      await tester.enterText(
        find.byKey(const Key('board-file-picker-new-folder-name')),
        'bad/name',
      );
      await _tapIo(
        tester,
        find.byKey(const Key('board-file-picker-create-folder-confirm')),
      );
      expect(find.textContaining('Could not create folder'), findsOneWidget);

      // A valid name creates the folder and reloads the listing.
      await _tapIo(tester, find.byKey(const Key('board-file-picker-new-folder')));
      await tester.enterText(
        find.byKey(const Key('board-file-picker-new-folder-name')),
        'created',
      );
      await _tapIo(
        tester,
        find.byKey(const Key('board-file-picker-create-folder-confirm')),
      );
      expect(Directory(p.join(fixture.path, 'created')).existsSync(), isTrue);
      expect(_tile(p.join(fixture.path, 'created')), findsOneWidget);
    });

    testWidgets('shows an error when the folder does not exist', (
      tester,
    ) async {
      _useLargeSurface(tester);
      await _openPicker(tester, (context) {
        unawaited(
          BoardFilePicker.pickDirectory(
            context,
            initialPath: p.join(fixture.path, 'missing'),
          ),
        );
      });

      expect(find.textContaining('Could not load folder'), findsOneWidget);
    });

    testWidgets('shows an empty-state message for empty folders', (
      tester,
    ) async {
      _useLargeSurface(tester);
      final empty = Directory(p.join(fixture.path, 'empty'))..createSync();
      await _openPicker(tester, (context) {
        unawaited(
          BoardFilePicker.pickDirectory(context, initialPath: empty.path),
        );
      });

      expect(find.text('No files here yet.'), findsOneWidget);
    });

    testWidgets('cancel returns null', (tester) async {
      _useLargeSurface(tester);
      Future<String?>? picked;
      await _openPicker(tester, (context) {
        picked = BoardFilePicker.pickDirectory(
          context,
          initialPath: fixture.path,
        );
      });

      await tester.tap(find.text('Cancel'));
      await _pumpOut(tester);
      expect(await tester.runAsync(() => picked!), isNull);
    });
  });

  group('remote modes', () {
    setUp(() {
      // flutter_test installs a mock HttpOverrides that answers every request
      // with HTTP 400; the loopback hub fixture needs real sockets.
      HttpOverrides.global = _RealHttpOverrides();
    });

    tearDown(() {
      HttpOverrides.global = null;
    });

    testWidgets('file mode: navigate, switch selection and confirm', (
      tester,
    ) async {
      _useLargeSurface(tester);
      late _RemoteFixture remote;
      await tester.runAsync(() async {
        remote = await _startRemote();
      });
      addTearDown(() => remote.server.close(force: true));

      Future<BoardFileSelection?>? picked;
      await _openPicker(tester, (context) {
        picked = BoardFilePicker.pickFile(context, remoteInfo: remote.info);
      });

      expect(_tile('/remote/docs'), findsOneWidget);
      expect(_tile('/remote/a.txt'), findsOneWidget);
      expect(_tile('/remote/b.txt'), findsOneWidget);

      // Nothing selected: confirm is disabled.
      expect(_confirmButton(tester).onPressed, isNull);

      // Remote directories load through the hub.
      await _tapIo(tester, _tile('/remote/docs'));
      expect(_tile('/remote/docs/inner.txt'), findsOneWidget);
      await _tapIo(tester, find.byTooltip('Parent folder'));
      expect(_tile('/remote/a.txt'), findsOneWidget);

      // Single-selection mode replaces the previous pick.
      await tester.tap(_tile('/remote/a.txt'));
      await _pumpOut(tester);
      expect(_confirmButton(tester).onPressed, isNotNull);
      await tester.tap(_tile('/remote/b.txt'));
      await _pumpOut(tester);

      await tester.tap(find.byKey(const Key('board-file-picker-confirm')));
      await _pumpOut(tester);
      final result = await tester.runAsync(() => picked!);
      expect(result, isNotNull);
      expect(result!.path, '/remote/b.txt');
      expect(result.name, 'b.txt');
    });

    testWidgets('files mode: checkboxes toggle multi-selection', (
      tester,
    ) async {
      _useLargeSurface(tester);
      late _RemoteFixture remote;
      await tester.runAsync(() async {
        remote = await _startRemote();
      });
      addTearDown(() => remote.server.close(force: true));

      Future<List<BoardFileSelection>?>? picked;
      await _openPicker(tester, (context) {
        picked = BoardFilePicker.pickFiles(context, remoteInfo: remote.info);
      });

      await tester.tap(_checkboxOf('/remote/a.txt'));
      await _pumpOut(tester);
      await tester.tap(_tile('/remote/b.txt'));
      await _pumpOut(tester);
      // Toggling again deselects.
      await tester.tap(_checkboxOf('/remote/a.txt'));
      await _pumpOut(tester);

      await tester.tap(find.byKey(const Key('board-file-picker-confirm')));
      await _pumpOut(tester);
      final result = await tester.runAsync(() => picked!);
      expect(result, isNotNull);
      expect(result!.map((s) => s.path), ['/remote/b.txt']);
    });

    testWidgets('create folder goes through the remote hub', (tester) async {
      _useLargeSurface(tester);
      late _RemoteFixture remote;
      await tester.runAsync(() async {
        remote = await _startRemote();
      });
      addTearDown(() => remote.server.close(force: true));

      Future<String?>? picked;
      await _openPicker(tester, (context) {
        picked = BoardFilePicker.pickDirectory(
          context,
          remoteInfo: remote.info,
        );
      });

      await _tapIo(tester, find.byKey(const Key('board-file-picker-new-folder')));
      await tester.enterText(
        find.byKey(const Key('board-file-picker-new-folder-name')),
        'newdir',
      );
      await _tapIo(
        tester,
        find.byKey(const Key('board-file-picker-create-folder-confirm')),
      );

      expect(remote.createdDirs, hasLength(1));
      expect(remote.createdDirs.single['parentPath'], '/remote');
      expect(remote.createdDirs.single['name'], 'newdir');
      expect(_tile('/remote/newdir'), findsOneWidget);

      await tester.tap(find.byKey(const Key('board-file-picker-confirm')));
      await _pumpOut(tester);
      expect(await tester.runAsync(() => picked!), '/remote');
    });
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

const Key _openKey = Key('picker-open');
const Key _searchKey = Key('board-file-picker-search');

Finder _tile(String path) => find.byKey(Key('board-file-picker-entry-$path'));

Finder _checkboxOf(String path) =>
    find.descendant(of: _tile(path), matching: find.byType(Checkbox));

FilledButton _confirmButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const Key('board-file-picker-confirm')),
);

void _useLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The Cancel button of the new-folder prompt (the picker's own Cancel
/// button stays visible underneath it).
Finder _folderDialogCancel() => find.descendant(
  of: find.widgetWithText(AlertDialog, 'New folder'),
  matching: find.text('Cancel'),
);

class _PickerHost extends StatelessWidget {
  const _PickerHost({required this.onOpen});

  final void Function(BuildContext context) onOpen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder:
              (context) => Center(
                child: TextButton(
                  key: _openKey,
                  onPressed: () => onOpen(context),
                  child: const Text('open'),
                ),
              ),
        ),
      ),
    );
  }
}

/// Pumps a handful of short frames so animations and microtasks settle
/// without tripping over persistent animations (e.g. progress spinners).
Future<void> _pumpOut(WidgetTester tester, [int times = 6]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Opens the picker dialog. The dialog's initial directory load uses real
/// dart:io futures, so the tap and the first frames run on the real event
/// loop via [WidgetTester.runAsync].
Future<void> _openPicker(
  WidgetTester tester,
  void Function(BuildContext context) onOpen,
) async {
  await tester.pumpWidget(_PickerHost(onOpen: onOpen));
  await tester.runAsync(() async {
    await tester.tap(find.byKey(_openKey));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pump();
  });
  await _pumpOut(tester);
}

/// Taps [finder] on the real event loop so interactions that trigger
/// filesystem or HTTP loads complete, then pumps the resulting frames.
Future<void> _tapIo(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pump();
  });
  await _pumpOut(tester);
}

/// Submits the search field with a value that does not trigger a load.
Future<void> _submitSearch(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(_searchKey), value);
  await tester.showKeyboard(find.byKey(_searchKey));
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await _pumpOut(tester);
}

/// Submits the search field with a value that loads a new directory.
Future<void> _submitSearchIo(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(_searchKey), value);
  await tester.showKeyboard(find.byKey(_searchKey));
  await tester.runAsync(() async {
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pump();
  });
  await _pumpOut(tester);
}

// ── Remote fixture ──────────────────────────────────────────────────────────

/// Restores the default (real) [HttpClient] behavior inside widget tests.
class _RealHttpOverrides extends HttpOverrides {}

class _RemoteFixture {
  _RemoteFixture(this.server);

  final HttpServer server;
  final Map<String, Map<String, dynamic>> listings =
      <String, Map<String, dynamic>>{};
  final List<Map<String, dynamic>> createdDirs = <Map<String, dynamic>>[];

  RemoteBoardInfo get info => (
    url: 'http://127.0.0.1:${server.port}',
    token: null,
    boardId: 'b1',
    revision: null,
  );
}

Map<String, dynamic> _remoteEntry(String name, String path, bool isDirectory) =>
    <String, dynamic>{'name': name, 'path': path, 'isDirectory': isDirectory};

Map<String, dynamic> _remoteListing({
  required String path,
  required String? parent,
  required List<Map<String, dynamic>> entries,
}) => <String, dynamic>{
  'path': path,
  'parent': parent,
  'roots': <Map<String, dynamic>>[_remoteEntry('Remote root', '/remote', true)],
  'entries': entries,
};

Future<_RemoteFixture> _startRemote() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final fixture = _RemoteFixture(server);
  final root = _remoteListing(
    path: '/remote',
    parent: null,
    entries: <Map<String, dynamic>>[
      _remoteEntry('docs', '/remote/docs', true),
      _remoteEntry('a.txt', '/remote/a.txt', false),
      _remoteEntry('b.txt', '/remote/b.txt', false),
    ],
  );
  fixture.listings[''] = root;
  fixture.listings['/remote'] = root;
  fixture.listings['/remote/docs'] = _remoteListing(
    path: '/remote/docs',
    parent: '/remote',
    entries: <Map<String, dynamic>>[
      _remoteEntry('inner.txt', '/remote/docs/inner.txt', false),
    ],
  );
  server.listen((request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    if (request.method == 'GET' && request.uri.path == '/api/files') {
      final listing =
          fixture.listings[request.uri.queryParameters['path'] ?? ''];
      if (listing == null) {
        response.statusCode = HttpStatus.notFound;
        response.write(jsonEncode(<String, dynamic>{'error': 'not found'}));
      } else {
        response.write(jsonEncode(listing));
      }
    } else if (request.method == 'POST' &&
        request.uri.path == '/api/files/directories') {
      final body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      fixture.createdDirs.add(body);
      final parentPath = body['parentPath'] as String;
      final parent = fixture.listings[parentPath]!;
      (parent['entries'] as List<dynamic>).add(
        _remoteEntry(
          body['name'] as String,
          '$parentPath/${body['name']}',
          true,
        ),
      );
      response.write(jsonEncode(parent));
    } else {
      response.statusCode = HttpStatus.notFound;
      response.write(jsonEncode(<String, dynamic>{}));
    }
    await response.close();
  });
  return fixture;
}
