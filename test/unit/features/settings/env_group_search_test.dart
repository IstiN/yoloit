import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/settings/ui/env_group_search.dart';

GlobalEnvGroup _group(
  String id,
  String name,
  Map<String, String> values,
) => GlobalEnvGroup(id: id, name: name, values: values);

void main() {
  group('EnvGroupSearch.filter', () {
    test('empty query returns all groups with all entries', () {
      final groups = [
        _group('a', 'Alpha', const {'K1': 'v1'}),
        _group('b', 'Beta', const {'K2': 'v2', 'K3': 'v3'}),
      ];
      final results = EnvGroupSearch.filter(groups, '  ');
      expect(results, hasLength(2));
      expect(results[0].entries, hasLength(1));
      expect(results[1].entries, hasLength(2));
    });

    test('group name match keeps all entries', () {
      final groups = [
        _group('a', 'Alpha API', const {'SECRET': 'v1', 'OTHER': 'v2'}),
        _group('b', 'Beta', const {'ALPHA': 'v3'}),
      ];
      final results = EnvGroupSearch.filter(groups, 'alpha api');
      expect(results, hasLength(1));
      expect(results.single.group.id, 'a');
      expect(results.single.entries, hasLength(2));
    });

    test('key match keeps only matching entries of matching groups', () {
      final groups = [
        _group('a', 'Alpha', const {'OPENAI_KEY': 'v1', 'OTHER': 'v2'}),
        _group('b', 'Beta', const {'UNRELATED': 'v3'}),
      ];
      final results = EnvGroupSearch.filter(groups, 'openai');
      expect(results, hasLength(1));
      expect(results.single.group.id, 'a');
      expect(results.single.entries.single.key, 'OPENAI_KEY');
    });

    test('search is case-insensitive', () {
      final groups = [_group('a', 'Alpha', const {'MiXeD': 'v1'})];
      expect(EnvGroupSearch.filter(groups, 'mixed'), hasLength(1));
      expect(EnvGroupSearch.filter(groups, 'ALPHA'), hasLength(1));
    });

    test('draft keys never match a query', () {
      final groups = [
        _group('a', 'Alpha', const {'__draft_1': '', 'REAL_KEY': 'v'}),
      ];
      final results = EnvGroupSearch.filter(
        groups,
        'draft',
        isDraftKey: (key) => key.startsWith('__draft_'),
      );
      expect(results, isEmpty);
      // Non-matching query still returns the group (name does not match, the
      // real key does not match either).
      final keyResults = EnvGroupSearch.filter(
        groups,
        'real',
        isDraftKey: (key) => key.startsWith('__draft_'),
      );
      expect(keyResults.single.entries.single.key, 'REAL_KEY');
    });

    test('no match returns empty list', () {
      final groups = [_group('a', 'Alpha', const {'K1': 'v1'})];
      expect(EnvGroupSearch.filter(groups, 'zzz'), isEmpty);
    });
  });
}
