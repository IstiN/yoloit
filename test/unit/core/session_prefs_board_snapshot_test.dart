import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/session/session_prefs.dart';

void main() {
  group('SessionPrefs — board snapshot', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('isBoardSnapshotEnabled defaults to false', () async {
      final result = await SessionPrefs.isBoardSnapshotEnabled();
      expect(result, isFalse);
    });

    test('saveBoardSnapshotEnabled persists value', () async {
      await SessionPrefs.saveBoardSnapshotEnabled(true);
      final result = await SessionPrefs.isBoardSnapshotEnabled();
      expect(result, isTrue);
    });

    test('saveBoardSnapshotEnabled can toggle off', () async {
      await SessionPrefs.saveBoardSnapshotEnabled(true);
      expect(await SessionPrefs.isBoardSnapshotEnabled(), isTrue);

      await SessionPrefs.saveBoardSnapshotEnabled(false);
      expect(await SessionPrefs.isBoardSnapshotEnabled(), isFalse);
    });
  });
}
