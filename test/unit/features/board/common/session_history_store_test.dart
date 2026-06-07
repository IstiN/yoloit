import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/common/session_history_store.dart';

class _TestEntry {
  _TestEntry({required this.id, required this.name});
  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class _TestStore extends SessionHistoryStore<_TestEntry> {
  @override
  String get key => 'test_entries';

  @override
  _TestEntry fromJson(Map<String, dynamic> json) =>
      _TestEntry(id: json['id'] as String, name: json['name'] as String);

  @override
  Map<String, dynamic> toJson(_TestEntry entry) => entry.toJson();

  @override
  String idOf(_TestEntry entry) => entry.id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SessionHistoryStore', () {
    test('loadAll returns empty list when no data', () async {
      final store = _TestStore();
      final result = await store.loadAll();
      expect(result, isEmpty);
    });

    test('saveAll and loadAll round-trip', () async {
      final store = _TestStore();
      final entries = [
        _TestEntry(id: '1', name: 'First'),
        _TestEntry(id: '2', name: 'Second'),
      ];

      await store.saveAll(entries);
      final loaded = await store.loadAll();

      expect(loaded.length, 2);
      expect(loaded[0].id, '1');
      expect(loaded[0].name, 'First');
      expect(loaded[1].id, '2');
    });

    test('loadAll returns empty list on invalid json', () async {
      SharedPreferences.setMockInitialValues({
        'test_entries': 'not-json',
      });
      final store = _TestStore();
      final result = await store.loadAll();
      expect(result, isEmpty);
    });

    test('delete removes entry by id', () async {
      final store = _TestStore();
      await store.saveAll([
        _TestEntry(id: 'a', name: 'Alpha'),
        _TestEntry(id: 'b', name: 'Beta'),
      ]);

      await store.delete('a');
      final loaded = await store.loadAll();

      expect(loaded.length, 1);
      expect(loaded.single.id, 'b');
    });

    test('delete does nothing when id not found', () async {
      final store = _TestStore();
      await store.saveAll([_TestEntry(id: 'x', name: 'Xavier')]);

      await store.delete('missing');
      final loaded = await store.loadAll();

      expect(loaded.length, 1);
    });
  });

  group('ChatSessionHistory', () {
    test('singleton instance exists', () {
      expect(ChatSessionHistory.instance, isNotNull);
    });

    test('key is chat_session_history', () {
      expect(ChatSessionHistory.instance.key, 'chat_session_history');
    });

    test('idOf returns entry id', () {
      final entry = ChatSessionEntry(
        id: 'sess-1',
        sessionName: 'Test',
        provider: 'copilot',
        model: 'gpt-4',
        workingDir: '/tmp',
        createdAt: DateTime.now(),
      );
      expect(ChatSessionHistory.instance.idOf(entry), 'sess-1');
    });

    test('fromJson/toJson round-trip', () {
      final entry = ChatSessionEntry(
        id: 'sess-2',
        sessionName: 'Round Trip',
        provider: 'openai',
        model: 'gpt-3',
        workingDir: '/home',
        createdAt: DateTime(2024, 6, 1, 12, 0, 0),
        lastMessageAt: DateTime(2024, 6, 1, 13, 0, 0),
        messageCount: 10,
        envGroupIds: ['env1', 'env2'],
      );

      final json = entry.toJson();
      final restored = ChatSessionEntry.fromJson(json);

      expect(restored.id, entry.id);
      expect(restored.sessionName, entry.sessionName);
      expect(restored.provider, entry.provider);
      expect(restored.model, entry.model);
      expect(restored.workingDir, entry.workingDir);
      expect(restored.createdAt, entry.createdAt);
      expect(restored.lastMessageAt, entry.lastMessageAt);
      expect(restored.messageCount, entry.messageCount);
      expect(restored.envGroupIds, entry.envGroupIds);
    });

    test('fromJson handles missing optional fields', () {
      final restored = ChatSessionEntry.fromJson({
        'id': 'sess-3',
        'sessionName': 'Minimal',
      });

      expect(restored.id, 'sess-3');
      expect(restored.sessionName, 'Minimal');
      expect(restored.provider, 'copilot');
      expect(restored.model, '');
      expect(restored.workingDir, '');
      expect(restored.messageCount, 0);
      expect(restored.envGroupIds, isEmpty);
      expect(restored.lastMessageAt, isNull);
    });

    test('fromJson handles null lastMessageAt', () {
      final restored = ChatSessionEntry.fromJson({
        'id': 'sess-4',
        'sessionName': 'NoLastMessage',
        'lastMessageAt': null,
      });

      expect(restored.lastMessageAt, isNull);
    });

    test('toJson writes empty envGroupIds when empty', () {
      final entry = ChatSessionEntry(
        id: 'sess-5',
        sessionName: 'NoEnv',
        provider: 'copilot',
        model: 'gpt-4',
        workingDir: '/tmp',
        createdAt: DateTime.now(),
      );

      final json = entry.toJson();
      expect(json['envGroupIds'], <String>[]);
    });

    test('toJson includes envGroupIds when not empty', () {
      final entry = ChatSessionEntry(
        id: 'sess-6',
        sessionName: 'WithEnv',
        provider: 'copilot',
        model: 'gpt-4',
        workingDir: '/tmp',
        createdAt: DateTime.now(),
        envGroupIds: ['g1'],
      );

      final json = entry.toJson();
      expect(json['envGroupIds'], ['g1']);
    });
  });
}
