import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

/// electron-updater / Squirrel.Mac manifest (`latest-mac.yml`).
class MacosUpdateManifest {
  const MacosUpdateManifest({
    required this.version,
    required this.files,
    required this.releaseDate,
  });

  final String version;
  final List<MacosUpdateFile> files;
  final String? releaseDate;

  static const String fileName = 'latest-mac.yml';

  static String feedUrlForTag(String tagName) =>
      'https://github.com/IstiN/yoloit/releases/download/$tagName/$fileName';

  static String get latestFeedUrl =>
      'https://github.com/IstiN/yoloit/releases/latest/download/$fileName';

  static MacosUpdateManifest parse(String yamlText) {
    final root = loadYaml(yamlText);
    if (root is! YamlMap) {
      throw const FormatException('latest-mac.yml root must be a map');
    }

    final version = root['version']?.toString().trim() ?? '';
    if (version.isEmpty) {
      throw const FormatException('latest-mac.yml missing version');
    }

    final filesRaw = root['files'];
    if (filesRaw is! YamlList || filesRaw.isEmpty) {
      throw const FormatException('latest-mac.yml missing files');
    }

    final files = <MacosUpdateFile>[];
    for (final entry in filesRaw) {
      if (entry is! YamlMap) continue;
      final url = entry['url']?.toString().trim() ?? '';
      final sha512 = entry['sha512']?.toString().trim() ?? '';
      final size = entry['size'];
      final arch = entry['arch']?.toString().trim();
      if (url.isEmpty || sha512.isEmpty) {
        throw FormatException('invalid file entry in latest-mac.yml: $entry');
      }
      files.add(
        MacosUpdateFile(
          url: url,
          sha512: sha512,
          size: size is num ? size.toInt() : int.tryParse('$size'),
          arch: arch == null || arch.isEmpty ? null : arch,
        ),
      );
    }

    return MacosUpdateManifest(
      version: version,
      files: files,
      releaseDate: root['releaseDate']?.toString(),
    );
  }

  static Future<MacosUpdateManifest> fetch({required String feedUrl}) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(feedUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'YoLoIT/updater');
      req.headers.set(HttpHeaders.acceptHeader, 'application/yaml,text/yaml,*/*');
      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw HttpException('Manifest HTTP ${resp.statusCode}', uri: Uri.parse(feedUrl));
      }
      final body = await resp.transform(utf8.decoder).join();
      return parse(body);
    } finally {
      client.close();
    }
  }

  /// Picks the ZIP entry for the current CPU architecture.
  MacosUpdateFile fileForCurrentArch() {
    final wanted = _currentArchKey();
    MacosUpdateFile? archMatch;
    MacosUpdateFile? zipFallback;

    for (final file in files) {
      if (!file.url.toLowerCase().endsWith('.zip')) continue;
      zipFallback ??= file;
      final fileArch = file.arch ?? _archFromFileName(file.url);
      if (fileArch == wanted) {
        archMatch = file;
        break;
      }
    }

    final picked = archMatch ?? zipFallback;
    if (picked == null) {
      throw StateError('No .zip artifact for arch $wanted in latest-mac.yml');
    }
    return picked;
  }

  static String _currentArchKey() {
    if (Abi.current() == Abi.macosArm64) return 'arm64';
    if (Abi.current() == Abi.macosX64) return 'x64';
    return 'x64';
  }

  static String? _archFromFileName(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('arm64')) return 'arm64';
    if (lower.contains('x86_64') || lower.contains('-x64')) return 'x64';
    return null;
  }

  String downloadUrlFor(MacosUpdateFile file, {required String tagName}) {
    return 'https://github.com/IstiN/yoloit/releases/download/$tagName/${file.url}';
  }
}

class MacosUpdateFile {
  const MacosUpdateFile({
    required this.url,
    required this.sha512,
    this.size,
    this.arch,
  });

  final String url;
  final String sha512;
  final int? size;
  final String? arch;
}

/// Verifies [bytes] against electron-updater base64 sha512 [expected].
void verifySha512Base64(List<int> bytes, String expected) {
  final digest = base64.encode(sha512.convert(bytes).bytes);
  if (digest != expected) {
    throw StateError('SHA-512 mismatch (expected update integrity check failed)');
  }
}
