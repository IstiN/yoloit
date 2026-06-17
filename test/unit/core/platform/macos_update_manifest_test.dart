import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/macos_update_manifest.dart';

void main() {
  const sampleYaml = '''
version: 1.0.57
files:
  - url: yoloit-macos-arm64-1.0.57-mac.zip
    sha512: arm64hash==
    size: 111
    arch: arm64
  - url: yoloit-macos-x86_64-1.0.57-mac.zip
    sha512: x64hash==
    size: 222
    arch: x64
path: yoloit-macos-arm64-1.0.57-mac.zip
sha512: arm64hash==
releaseDate: '2026-06-17T12:00:00.000Z'
''';

  test('parse reads version and files from latest-mac.yml', () {
    final manifest = MacosUpdateManifest.parse(sampleYaml);
    expect(manifest.version, '1.0.57');
    expect(manifest.files, hasLength(2));
    expect(manifest.files.first.url, contains('arm64'));
  });

  test('downloadUrlFor builds GitHub release asset URL', () {
    final manifest = MacosUpdateManifest.parse(sampleYaml);
    final url = manifest.downloadUrlFor(
      manifest.files.first,
      tagName: 'v1.0.57',
    );
    expect(
      url,
      'https://github.com/IstiN/yoloit/releases/download/v1.0.57/'
      'yoloit-macos-arm64-1.0.57-mac.zip',
    );
  });

  test('verifySha512Base64 accepts matching digest', () {
    final bytes = utf8.encode('hello');
    final digest = base64.encode(sha512.convert(bytes).bytes);
    expect(() => verifySha512Base64(bytes, digest), returnsNormally);
  });

  test('verifySha512Base64 rejects tampered payload', () {
    expect(
      () => verifySha512Base64([1, 2, 3], 'bad=='),
      throwsStateError,
    );
  });
}
