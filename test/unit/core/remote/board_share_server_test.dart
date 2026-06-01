import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/remote/board_share_server.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });

  test('share server exposes local boards to remote clients', () async {
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    await cubit.load();
    await cubit.createBoard(name: 'Shared board');
    final sourceBoard = cubit.state.activeBoard!;

    final info = await BoardShareServer.instance.start(cubit, port: 0);
    addTearDown(BoardShareServer.instance.stop);

    final client = YoloitRemoteClient(
      baseUrl: 'http://127.0.0.1:${info.port}',
      token: info.token,
    );
    final boards = await client.listBoards();
    expect(boards.map((board) => board['id']), contains(sourceBoard.id));

    final remoteBoard = await client.fetchBoard(sourceBoard.id);
    expect(remoteBoard.name, 'Shared board');

    final renamed = await client.putBoard(
      remoteBoard.copyWith(
        name: 'Edited',
        viewport: const BoardViewport(scale: 0.4),
      ),
    );
    expect(renamed.name, 'Edited');
    expect(renamed.viewport.scale, 0.4);
    expect(cubit.state.activeBoard!.name, 'Edited');
    expect(cubit.state.activeBoard!.viewport.scale, sourceBoard.viewport.scale);
  });

  test(
    'share server exposes setup and filesystem APIs used by remote panels',
    () async {
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await cubit.load();

      final info = await BoardShareServer.instance.start(cubit, port: 0);
      addTearDown(BoardShareServer.instance.stop);

      final client = YoloitRemoteClient(
        baseUrl: 'http://127.0.0.1:${info.port}',
        token: info.token,
      );

      final setup = await client.setupCheck();
      expect(setup.packages, isNotEmpty);

      final listing = await client.listDirectory(Directory.current.path);
      expect(listing.path, Directory.current.path);
      expect(
        listing.entries.map((entry) => entry.name),
        contains('pubspec.yaml'),
      );

      final defaultListing = await client.listDirectory(null);
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null && home.trim().isNotEmpty) {
        expect(defaultListing.path, home.trim());
        expect(
          defaultListing.roots.map((entry) => entry.name),
          contains('Home'),
        );
      }
    },
  );
}
