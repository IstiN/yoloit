import 'dart:io';

import 'package:yoloit/features/board/model/board_icon.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Auto-detects a board icon from the board's default folder.
///
/// Detection strategy (first hit wins):
/// 1. Well-known app icon locations (Flutter macOS/iOS/Android/web icon sets,
///    common `assets/…` and root icon files) — see [kCandidateRelativePaths].
/// 2. A bounded scan of icon-ish directories (`branding/`, `icon/`,
///    `assets/`, …) for files named like `app_icon*`, `icon*`, `logo*` or
///    `favicon*` — prefers `app_icon` and larger pixel sizes in the name.
/// 3. When the folder itself is not a project root, the same detection runs
///    inside immediate subfolders that contain a `pubspec.yaml` (e.g. a
///    nested `flutter_app/`).
///
/// Detection results are cached in memory per folder — call [invalidate] when
/// the folder contents may have changed.
///
/// Pure `dart:io` — safe to use from the desktop app and headless `yoloitd`.
class BoardIconResolver {
  BoardIconResolver({
    bool Function(String path)? fileExists,
    List<String> Function(String dirPath)? listFileNames,
  }) : _fileExists = fileExists ?? _defaultFileExists,
       _listFileNames = listFileNames ?? _defaultListFileNames;

  static final BoardIconResolver instance = BoardIconResolver();

  final bool Function(String path) _fileExists;
  final List<String> Function(String dirPath) _listFileNames;

  static bool _defaultFileExists(String path) => File(path).existsSync();

  static List<String> _defaultListFileNames(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync(followLinks: false)
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toList();
  }

  /// Candidate icon locations relative to a project root, in priority order.
  static const List<String> kCandidateRelativePaths = [
    // Flutter desktop (macOS) app icon set.
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png',
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png',
    // Flutter iOS app icon set.
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
    // Flutter Android launcher icons.
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png',
    // Flutter web icons.
    'web/icons/Icon-512.png',
    'web/icons/Icon-192.png',
    'web/icons/Icon-maskable-512.png',
    'web/favicon.png',
    // Common asset locations.
    'assets/icon.png',
    'assets/icons/icon.png',
    'assets/app_icon.png',
    'assets/icon/app_icon.png',
    'assets/icon/icon.png',
    'assets/logo.png',
    'assets/images/icon.png',
    'assets/images/logo.png',
    // Folder root.
    'icon.png',
    'app_icon.png',
    'logo.png',
    'favicon.png',
    // Windows runner icon (ico is not decodable, but some projects ship png).
    'windows/runner/resources/app_icon.png',
  ];

  /// Directories (relative to a project root) scanned for icon-ish files.
  static const List<String> kScannedDirectories = [
    '.',
    'branding',
    'brand',
    'icon',
    'icons',
    'images',
    'assets',
    'assets/images',
    'assets/icon',
    'assets/icons',
    'assets/branding',
  ];

  /// Subfolders that never contain the project we are looking for.
  static const Set<String> kSkippedSubdirectories = {
    '.git',
    '.idea',
    '.vscode',
    'build',
    'packages',
    'node_modules',
    'third_party',
    'coverage',
  };

  static const int _maxNestedProjectDirs = 20;

  final Map<String, String?> _cache = {};

  /// Returns the absolute path of the detected icon inside [folder], or `null`
  /// when nothing recognizable is found. Synchronous: detection only checks
  /// for the existence of well-known files and lists a few small directories.
  String? detectInFolder(String folder) {
    final trimmed = folder.trim();
    if (trimmed.isEmpty) return null;
    if (_cache.containsKey(trimmed)) return _cache[trimmed];
    final found = _detectUncached(trimmed);
    _cache[trimmed] = found;
    return found;
  }

  /// Returns all icon candidates inside [folder], best first:
  /// well-known app icon locations, then icon-ish files found by the
  /// directory scan (highest score first), then candidates of nested
  /// projects. Used by the icon picker to offer alternatives.
  List<String> findIconCandidates(String folder, {int limit = 12}) {
    final trimmed = folder.trim();
    if (trimmed.isEmpty) return const [];
    final results = <String>[];

    void collectInRoot(String root) {
      for (final relative in kCandidateRelativePaths) {
        final candidate = _join(root, relative);
        if (_fileExists(candidate) && !results.contains(candidate)) {
          results.add(candidate);
        }
      }
      for (final entry in _scoredIconFiles(root)) {
        if (_fileExists(entry.path) && !results.contains(entry.path)) {
          results.add(entry.path);
        }
      }
    }

    collectInRoot(trimmed);
    for (final subdir in _nestedProjectRoots(trimmed)) {
      if (results.length >= limit) break;
      collectInRoot(subdir);
    }
    if (results.length <= limit) return results;
    return results.sublist(0, limit);
  }

  /// Resolves the effective icon for [board]:
  ///
  /// 1. An explicit override from `board.metadata['icon']` wins.
  /// 2. Otherwise an icon is auto-detected from `board.defaultFolder`.
  /// 3. Otherwise `null` (the UI renders a generated letter avatar).
  BoardIconSpec? resolveForBoard(BoardDocument board) {
    final explicit = board.icon;
    if (explicit != null) return explicit;
    final detected = detectInFolder(board.defaultFolder);
    if (detected == null) return null;
    return BoardIconSpec(kind: BoardIconSpec.kindFile, value: detected);
  }

  /// Clears the detection cache for [folder] (or entirely when omitted).
  void invalidate([String? folder]) {
    if (folder == null) {
      _cache.clear();
    } else {
      _cache.remove(folder.trim());
    }
  }

  String? _detectUncached(String folder) {
    final direct = _detectInRoot(folder);
    if (direct != null) return direct;
    // Not a project root — look for a nested project (e.g. flutter_app/).
    for (final subdir in _nestedProjectRoots(folder)) {
      final nested = _detectInRoot(subdir);
      if (nested != null) return nested;
    }
    return null;
  }

  /// Immediate subfolders of [folder] that contain a `pubspec.yaml`
  /// (skipping hidden/build/vendor directories), up to a bounded count.
  Iterable<String> _nestedProjectRoots(String folder) sync* {
    var examined = 0;
    for (final name in _listSubdirectoryNames(folder)) {
      if (examined >= _maxNestedProjectDirs) break;
      if (name.startsWith('.') || kSkippedSubdirectories.contains(name)) {
        continue;
      }
      examined++;
      final subdir = _join(folder, name);
      if (_fileExists(_join(subdir, 'pubspec.yaml'))) yield subdir;
    }
  }

  List<String> _listSubdirectoryNames(String folder) {
    final dir = Directory(folder);
    if (!dir.existsSync()) return const [];
    try {
      return dir
          .listSync(followLinks: false)
          .whereType<Directory>()
          .map((entry) => entry.uri.pathSegments[entry.uri.pathSegments.length - 2])
          .toList();
    } on FileSystemException {
      return const [];
    }
  }

  String? _detectInRoot(String root) {
    for (final relative in kCandidateRelativePaths) {
      final candidate = _join(root, relative);
      if (_fileExists(candidate)) return candidate;
    }
    return _scanIconDirectories(root);
  }

  /// Icon-ish files found in [root]'s scanned directories, best score first.
  List<({int score, String path})> _scoredIconFiles(String root) {
    final scored = <({int score, String path})>[];
    for (final relative in kScannedDirectories) {
      final dirPath = relative == '.' ? root : _join(root, relative);
      List<String> names;
      try {
        names = _listFileNames(dirPath);
      } on FileSystemException {
        continue;
      }
      for (final name in names) {
        final score = scoreIconFileName(name);
        if (score > 0) {
          scored.add((score: score, path: _join(dirPath, name)));
        }
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  String? _scanIconDirectories(String root) {
    for (final entry in _scoredIconFiles(root)) {
      if (_fileExists(entry.path)) return entry.path;
    }
    return null;
  }

  /// Scores a file name by how much it looks like an app icon.
  ///
  /// Returns 0 when the file is not an icon candidate. `app_icon` beats
  /// `icon`, which beats `favicon`, which beats `logo`; a pixel size in the
  /// name (e.g. `1024`) raises the score.
  static int scoreIconFileName(String fileName) {
    final lower = fileName.toLowerCase();
    const extensions = ['.png', '.jpg', '.jpeg', '.webp', '.svg'];
    String? base;
    for (final ext in extensions) {
      if (lower.endsWith(ext)) {
        base = lower.substring(0, lower.length - ext.length);
        break;
      }
    }
    if (base == null) return 0;
    // Dark/light variants lose to the plain variant of the same icon.
    final isVariant = base.contains('_dark') || base.contains('_light');
    final int kindScore;
    if (base.contains('app_icon') || base.contains('appicon')) {
      kindScore = 400;
    } else if (base == 'icon' ||
        base.startsWith('icon_') ||
        base.startsWith('icon-') ||
        base.endsWith('_icon') ||
        base.endsWith('-icon')) {
      kindScore = 300;
    } else if (base.contains('favicon')) {
      kindScore = 200;
    } else if (base == 'logo' ||
        base.startsWith('logo_') ||
        base.startsWith('logo-') ||
        base.endsWith('_logo') ||
        base.endsWith('-logo')) {
      kindScore = 100;
    } else {
      return 0;
    }
    var score = kindScore;
    final dimension = RegExp(r'(\d{3,4})').firstMatch(base);
    if (dimension != null) {
      final pixels = int.tryParse(dimension.group(1)!) ?? 0;
      score += pixels.clamp(0, 2048) ~/ 10;
    }
    if (isVariant) score -= 50;
    return score;
  }

  static String _join(String root, String relative) {
    final normalized = relative.replaceAll('/', Platform.pathSeparator);
    if (root.endsWith(Platform.pathSeparator)) return '$root$normalized';
    return '$root${Platform.pathSeparator}$normalized';
  }
}
