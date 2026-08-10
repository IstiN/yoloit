import 'dart:convert';
import 'dart:ffi' show Abi;

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

  group('MacosUpdateManifest.fileForCurrentArch', () {
    final hostArch = Abi.current() == Abi.macosArm64 ? 'arm64' : 'x64';
    final otherArch = hostArch == 'arm64' ? 'x64' : 'arm64';

    MacosUpdateManifest manifest(List<MacosUpdateFile> files) =>
        MacosUpdateManifest(version: '1.0.0', files: files, releaseDate: null);

    test('picks the file whose arch field matches the host CPU', () {
      final m = manifest(<MacosUpdateFile>[
        MacosUpdateFile(
          url: 'app-$otherArch-mac.zip',
          sha512: 'other',
          arch: otherArch,
        ),
        MacosUpdateFile(
          url: 'app-$hostArch-mac.zip',
          sha512: 'host',
          arch: hostArch,
        ),
      ]);
      expect(m.fileForCurrentArch().sha512, 'host');
    });

    test('falls back to the first zip when no arch matches', () {
      final m = manifest(<MacosUpdateFile>[
        const MacosUpdateFile(
          url: 'app-universal-mac.zip',
          sha512: 'universal',
          arch: 'riscv',
        ),
      ]);
      expect(m.fileForCurrentArch().sha512, 'universal');
    });

    test('detects arch from the file name when the arch field is absent', () {
      final m = manifest(<MacosUpdateFile>[
        const MacosUpdateFile(url: 'app-macos-arm64.zip', sha512: 'arm'),
        const MacosUpdateFile(url: 'app-macos-x86_64.zip', sha512: 'intel'),
      ]);
      expect(
        m.fileForCurrentArch().sha512,
        hostArch == 'arm64' ? 'arm' : 'intel',
      );
    });

    test('recognizes the -x64 file name suffix', () {
      final m = manifest(<MacosUpdateFile>[
        const MacosUpdateFile(url: 'tool-universal.zip', sha512: 'uni'),
        const MacosUpdateFile(url: 'tool-macos-x64.zip', sha512: 'intel'),
      ]);
      expect(
        m.fileForCurrentArch().sha512,
        hostArch == 'x64' ? 'intel' : 'uni',
      );
    });

    test('ignores non-zip artifacts', () {
      final m = manifest(<MacosUpdateFile>[
        const MacosUpdateFile(url: 'app-macos-arm64.dmg', sha512: 'dmg'),
        const MacosUpdateFile(url: 'app-macos-arm64.zip', sha512: 'zip'),
      ]);
      expect(m.fileForCurrentArch().sha512, 'zip');
    });

    test('throws when the manifest has no zip artifact', () {
      final m = manifest(<MacosUpdateFile>[
        const MacosUpdateFile(url: 'app-macos-arm64.dmg', sha512: 'dmg'),
      ]);
      expect(m.fileForCurrentArch, throwsStateError);
    });
  });
}
