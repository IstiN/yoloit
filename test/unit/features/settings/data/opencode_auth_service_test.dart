import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/settings/data/opencode_auth_service.dart';

void main() {
  group('OpenCodeAuthService.parseAuthData', () {
    test('returns empty map for non-map data', () {
      expect(OpenCodeAuthService.parseAuthData(null), isEmpty);
      expect(OpenCodeAuthService.parseAuthData('string'), isEmpty);
      expect(OpenCodeAuthService.parseAuthData(42), isEmpty);
      expect(OpenCodeAuthService.parseAuthData([]), isEmpty);
    });

    test('extracts provider keys from valid auth json', () {
      final data = {
        'openrouter': {'type': 'api', 'key': 'sk-or-test'},
        'anthropic': {'type': 'api', 'key': 'sk-ant-test'},
      };
      final result = OpenCodeAuthService.parseAuthData(data);
      expect(result, {
        'openrouter': 'sk-or-test',
        'anthropic': 'sk-ant-test',
      });
    });

    test('skips providers with empty keys', () {
      final data = {
        'valid': {'type': 'api', 'key': 'has-key'},
        'empty': {'type': 'api', 'key': ''},
        'missing': {'type': 'api'},
      };
      final result = OpenCodeAuthService.parseAuthData(data);
      expect(result.length, 1);
      expect(result['valid'], 'has-key');
    });

    test('skips providers with empty provider id', () {
      final data = {
        '': {'type': 'api', 'key': 'sk-test'},
        'valid': {'type': 'api', 'key': 'sk-valid'},
      };
      final result = OpenCodeAuthService.parseAuthData(data);
      expect(result.length, 1);
      expect(result['valid'], 'sk-valid');
    });

    test('skips non-map provider values', () {
      final data = {
        'bad': 'not-a-map',
        'good': {'key': 'value'},
      };
      final result = OpenCodeAuthService.parseAuthData(data);
      expect(result.length, 1);
      expect(result['good'], 'value');
    });

    test('handles nested map values gracefully', () {
      final data = {
        'provider': {'key': 'secret', 'extra': 'ignored'},
      };
      final result = OpenCodeAuthService.parseAuthData(data);
      expect(result['provider'], 'secret');
    });

    test('returns empty map for empty object', () {
      expect(OpenCodeAuthService.parseAuthData({}), isEmpty);
    });
  });

  group('OpenCodeAuthService.configuredProviderIds', () {
    test('configuredProviderIds returns keys from parseAuthData', () {
      final data = {
        'openrouter': {'key': 'sk-test'},
        'anthropic': {'key': 'sk-ant'},
      };
      final providers = OpenCodeAuthService.parseAuthData(data);
      expect(providers.keys.toList(), ['openrouter', 'anthropic']);
    });

    test('configuredProviderIds returns empty list for empty data', () {
      final providers = OpenCodeAuthService.parseAuthData({});
      expect(providers.keys.toList(), isEmpty);
    });
  });
}
