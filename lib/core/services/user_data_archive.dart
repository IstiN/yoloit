import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yoloit/core/platform/platform_dirs.dart';

/// Snapshot of all the on-disk roots that hold YoLoIT user state.
///
/// All four roots are captured explicitly because YoLoIT's data is fragmented
/// across them — zipping just `~/.config/yoloit/` misses boards (which live in
/// SharedPreferences) and workspace paths (which live in `~/.yoloit/`).
@immutable
class ArchiveRoots {
  const ArchiveRoots({
    required this.platformDirs,
    required this.yoloitHome,
    required this.sharedPrefsAvailable,
  });

  /// Detect roots from the current environment (production use).
  factory ArchiveRoots.detect({PlatformDirs? dirs}) {
    final d = dirs ?? PlatformDirs.instance;
    final home = Platform.environment['HOME'] ?? '/tmp';
    return ArchiveRoots(
      platformDirs: d,
      yoloitHome: p.join(home, '.yoloit'),
      sharedPrefsAvailable: true,
    );
  }

  final PlatformDirs platformDirs;

  /// Path to `~/.yoloit/` (AppConfig + workspaces.json).
  final String yoloitHome;

  /// False in headless tests where `SharedPreferences.setMockInitialValues`
  /// is used and no real plist exists.
  final bool sharedPrefsAvailable;

  String get configDir => platformDirs.configDir;
  String get dataDir => platformDirs.dataDir;
}

/// What to include in the archive. Defaults are chosen so the archive is
/// "full local state minus ephemeral/machine-specific stuff". Secrets are
/// off by default — they require an explicit opt-in.
@immutable
class ArchiveIncludeOptions {
  const ArchiveIncludeOptions({
    this.secrets = false,
    this.history = true,
    this.chatSessions = true,
    this.calendar = true,
    this.stateJson = true,
    this.templatesCache = false,
  });

  final bool secrets;
  final bool history;
  final bool chatSessions;
  final bool calendar;
  final bool stateJson;
  final bool templatesCache;

  static const defaults = ArchiveIncludeOptions();

  Map<String, bool> toMap() => {
    'secrets': secrets,
    'history': history,
    'chatSessions': chatSessions,
    'calendar': calendar,
    'stateJson': stateJson,
    'templatesCache': templatesCache,
  };
}

/// A single absolute path discovered inside the archive, captured during
/// pack so restore can offer path-rewrite.
@immutable
class PathIndexEntry {
  const PathIndexEntry({
    required this.kind,
    required this.old,
    this.boardId,
    this.panelId,
    this.workspaceId,
  });

  /// Where this path lives, e.g. `board.defaultFolder`,
  /// `panel.params.rootPath`, `workspace.path`.
  final String kind;

  /// Original absolute path from the source machine.
  final String old;

  final String? boardId;
  final String? panelId;
  final String? workspaceId;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'old': old,
    if (boardId != null) 'boardId': boardId,
    if (panelId != null) 'panelId': panelId,
    if (workspaceId != null) 'workspaceId': workspaceId,
  };

  factory PathIndexEntry.fromJson(Map<String, dynamic> json) =>
      PathIndexEntry(
        kind: json['kind'] as String,
        old: json['old'] as String,
        boardId: json['boardId'] as String?,
        panelId: json['panelId'] as String?,
        workspaceId: json['workspaceId'] as String?,
      );
}

@immutable
class ArchiveManifest {
  const ArchiveManifest({
    required this.schemaVersion,
    required this.createdAt,
    required this.sourceAppVersion,
    required this.sourceHostname,
    required this.sourceHome,
    required this.sourceUsername,
    required this.contents,
    required this.flags,
    required this.pathIndex,
  });

  final int schemaVersion;
  final DateTime createdAt;
  final String sourceAppVersion;
  final String sourceHostname;
  final String sourceHome;
  final String sourceUsername;
  final List<String> contents;
  final Map<String, bool> flags;
  final List<PathIndexEntry> pathIndex;

  static const currentSchemaVersion = 1;

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toIso8601String(),
    'sourceAppVersion': sourceAppVersion,
    'sourceHostname': sourceHostname,
    'sourceHome': sourceHome,
    'sourceUsername': sourceUsername,
    'contents': contents,
    'flags': flags,
    'pathIndex': pathIndex.map((e) => e.toJson()).toList(),
  };

  factory ArchiveManifest.fromJson(Map<String, dynamic> json) =>
      ArchiveManifest(
        schemaVersion: json['schemaVersion'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        sourceAppVersion: json['sourceAppVersion'] as String,
        sourceHostname: json['sourceHostname'] as String,
        sourceHome: json['sourceHome'] as String,
        sourceUsername: json['sourceUsername'] as String,
        contents: (json['contents'] as List).cast<String>(),
        flags: (json['flags'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v as bool),
        ),
        pathIndex: (json['pathIndex'] as List)
            .map((e) => PathIndexEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

enum ImportMode { merge, replace }

enum PathRewriteStrategy { auto, ask, keep }

/// One planned filesystem change produced during a restore preview.
@immutable
class PlannedChange {
  const PlannedChange({
    required this.root,
    required this.action,
    required this.path,
  });

  /// "prefs" | "config" | "data" | "workspaces"
  final String root;

  /// "add" | "overwrite" | "skip"
  final String action;

  /// Path relative to [root].
  final String path;

  Map<String, dynamic> toJson() => {
    'root': root,
    'action': action,
    'path': path,
  };

  factory PlannedChange.fromJson(Map<String, dynamic> json) => PlannedChange(
    root: json['root'] as String,
    action: json['action'] as String,
    path: json['path'] as String,
  );
}

@immutable
class MissingPathWarning {
  const MissingPathWarning({required this.entry, required this.rewritten});

  final PathIndexEntry entry;
  final String rewritten;

  Map<String, dynamic> toJson() => {
    'entry': entry.toJson(),
    'rewritten': rewritten,
  };

  factory MissingPathWarning.fromJson(Map<String, dynamic> json) =>
      MissingPathWarning(
        entry: PathIndexEntry.fromJson(json['entry'] as Map<String, dynamic>),
        rewritten: json['rewritten'] as String,
      );
}

/// A board id that exists in both the archive and the destination. The caller
/// decides via [ImportConflictResolver].
@immutable
class BoardConflict {
  const BoardConflict({
    required this.boardId,
    required this.incomingName,
    required this.existingName,
  });

  final String boardId;
  final String incomingName;
  final String existingName;
}

enum BoardConflictChoice { overwrite, keepBoth, renameIncoming, skipIncoming }

/// Optional flags for fine-grained restore control (mostly for the CLI).
@immutable
class ImportOverrides {
  const ImportOverrides({
    this.prefs = true,
    this.config = true,
    this.data = true,
    this.workspaces = true,
  });

  final bool prefs;
  final bool config;
  final bool data;
  final bool workspaces;

  static const defaults = ImportOverrides();
}

@immutable
class ImportReport {
  const ImportReport({
    required this.manifest,
    required this.changes,
    required this.missing,
    required this.conflicts,
    required this.dryRun,
  });

  final ArchiveManifest manifest;
  final List<PlannedChange> changes;
  final List<MissingPathWarning> missing;
  final List<BoardConflict> conflicts;
  final bool dryRun;

  int get totalChanges => changes.length;
  int get totalMissing => missing.length;
  int get totalConflicts => conflicts.length;

  Map<String, dynamic> toJson() => {
    'manifest': manifest.toJson(),
    'dryRun': dryRun,
    'changes': changes.map((c) => c.toJson()).toList(),
    'missing': missing.map((m) => m.toJson()).toList(),
    'conflicts': conflicts
        .map(
          (c) => {
            'boardId': c.boardId,
            'incomingName': c.incomingName,
            'existingName': c.existingName,
          },
        )
        .toList(),
  };

  factory ImportReport.fromJson(Map<String, dynamic> json) => ImportReport(
    manifest: ArchiveManifest.fromJson(json['manifest'] as Map<String, dynamic>),
    dryRun: json['dryRun'] as bool? ?? true,
    changes: (json['changes'] as List)
        .map((e) => PlannedChange.fromJson(e as Map<String, dynamic>))
        .toList(),
    missing: (json['missing'] as List)
        .map((e) => MissingPathWarning.fromJson(e as Map<String, dynamic>))
        .toList(),
    conflicts: (json['conflicts'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (c) => BoardConflict(
            boardId: c['boardId'] as String,
            incomingName: c['incomingName'] as String? ?? '',
            existingName: c['existingName'] as String? ?? '',
          ),
        )
        .toList(),
  );
}

typedef ImportConflictResolver = Future<BoardConflictChoice> Function(
  BoardConflict conflict,
);

/// App version reader — overridable in tests.
typedef AppVersionReader = String Function();

/// Read the YoLoIT version from the environment. In production the app
/// embeds its version via the release workflow; in tests we inject a stub.
String defaultAppVersionReader() =>
    Platform.environment['YOLOIT_VERSION'] ?? '0.0.0';

/// Encrypted archive envelope: magic + salt + ciphertext+tag.
///
/// Format: `YLA1` (4 bytes) || salt (16 bytes) ||
/// ciphertext || 16-byte GCM tag. PBKDF2-SHA256 with 200_000 iterations
/// derives a 256-bit AES key from the passphrase.
class ArchiveCipher {
  const ArchiveCipher();

  static const _magic = 'YLA1';

  Future<void> encrypt(
    List<int> plaintext,
    StreamSink<List<int>> sink,
    String passphrase,
  ) async {
    final algorithm = AesGcm.with256bits();
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 200000,
      bits: 256,
    );
    final salt = _secureBytes(16);
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final secretBox = await algorithm.encrypt(
      plaintext,
      secretKey: key,
      nonce: salt.sublist(0, 12),
    );
    sink.add(_magic.codeUnits);
    sink.add(salt);
    sink.add(secretBox.cipherText);
    sink.add(secretBox.mac.bytes);
    await sink.close();
  }

  Future<List<int>> decrypt(Stream<List<int>> input, String passphrase) async {
    final bytes = await _flatten(input);
    if (bytes.length < 4 + 16 + 16) {
      throw const FormatException('Encrypted archive too short');
    }
    final magic = String.fromCharCodes(bytes.sublist(0, 4));
    if (magic != _magic) {
      throw const FormatException('Not an encrypted YoLoIT archive');
    }
    final salt = bytes.sublist(4, 20);
    final tag = bytes.sublist(bytes.length - 16);
    final ciphertext = bytes.sublist(20, bytes.length - 16);
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 200000,
      bits: 256,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final algorithm = AesGcm.with256bits();
    final secretBox = SecretBox(
      ciphertext,
      nonce: salt.sublist(0, 12),
      mac: Mac(tag),
    );
    return algorithm.decrypt(secretBox, secretKey: key);
  }

  /// True if [bytes] starts with the encryption magic.
  bool looksEncrypted(List<int> bytes) =>
      bytes.length >= 4 && String.fromCharCodes(bytes.sublist(0, 4)) == _magic;
}

List<int> _secureBytes(int n) {
  final r = math.Random.secure();
  return List<int>.generate(n, (_) => r.nextInt(256));
}

Future<List<int>> _flatten(Stream<List<int>> input) async {
  final out = <int>[];
  await for (final chunk in input) {
    out.addAll(chunk);
  }
  return out;
}

/// Packs all YoLoIT user state into a single `.tar` archive (optionally
/// AES-GCM-encrypted) and returns the manifest.
///
/// Phase 1 scope: pack + inspect + dry-run restore with path-rewrite `auto`.
/// Interactive conflict resolution (path `ask`, board conflicts) lives in a
/// later phase wired into the CLI.
class UserDataArchive {
  UserDataArchive({
    ArchiveRoots? roots,
    ArchiveCipher? cipher,
    AppVersionReader? appVersion,
    String? sourceHomeOverride,
    String? sourceUsernameOverride,
    String? sourceHostnameOverride,
  })  : _roots = roots ?? ArchiveRoots.detect(),
        _cipher = cipher ?? const ArchiveCipher(),
        _appVersion = appVersion ?? defaultAppVersionReader,
        // ignore: prefer_initializing_formals
        _sourceHomeOverride = sourceHomeOverride,
        // ignore: prefer_initializing_formals
        _sourceUsernameOverride = sourceUsernameOverride,
        // ignore: prefer_initializing_formals
        _sourceHostnameOverride = sourceHostnameOverride;

  UserDataArchive.withOverrides({
    required ArchiveRoots roots,
    required String sourceHome,
    required String sourceUsername,
    String? sourceHostname,
    ArchiveCipher? cipher,
    AppVersionReader? appVersion,
  })  :
        // ignore: prefer_initializing_formals
        _roots = roots,
        _cipher = cipher ?? const ArchiveCipher(),
        _appVersion = appVersion ?? defaultAppVersionReader,
        _sourceHomeOverride = sourceHome,
        _sourceUsernameOverride = sourceUsername,
        _sourceHostnameOverride = sourceHostname;

  final ArchiveRoots _roots;
  final ArchiveCipher _cipher;
  final AppVersionReader _appVersion;
  final String? _sourceHomeOverride;
  final String? _sourceUsernameOverride;
  final String? _sourceHostnameOverride;

  String _resolveSourceHome() =>
      _sourceHomeOverride ?? Platform.environment['HOME'] ?? '/tmp';
  String _resolveSourceUsername() =>
      _sourceUsernameOverride ?? Platform.environment['USER'] ?? 'unknown';
  String _resolveSourceHostname() =>
      _sourceHostnameOverride ?? Platform.environment['HOSTNAME'] ?? 'unknown';

  /// Pack all user state into [outputPath]. If [passphrase] is non-null the
  /// archive is AES-GCM encrypted.
  Future<ArchiveManifest> pack({
    required String outputPath,
    String? passphrase,
    ArchiveIncludeOptions include = ArchiveIncludeOptions.defaults,
  }) async {
    final manifest = await _buildManifest(include: include);
    final tarBytes = await _buildTar(manifest, include: include);
    final outFile = File(outputPath);
    await outFile.parent.create(recursive: true);
    final sink = outFile.openWrite();
    try {
      if (passphrase != null && passphrase.isNotEmpty) {
        await _cipher.encrypt(tarBytes, sink, passphrase);
      } else {
        sink.add(tarBytes);
      }
    } finally {
      await sink.close();
    }
    return manifest;
  }

  /// Read the manifest from an existing archive without applying it.
  Future<ArchiveManifest> inspect(
    String archivePath, {
    String? passphrase,
  }) async {
    final bytes = await File(archivePath).readAsBytes();
    final tarBytes = await _decodeEnvelope(bytes, passphrase: passphrase);
    return _readManifestFromTar(tarBytes);
  }

  /// Restore an archive. When [dryRun] is true (the default) no files are
  /// touched; the returned report describes what would change.
  Future<ImportReport> restore({
    required String archivePath,
    ImportMode mode = ImportMode.merge,
    PathRewriteStrategy pathRewrite = PathRewriteStrategy.auto,
    String? passphrase,
    bool dryRun = true,
    ImportOverrides overrides = ImportOverrides.defaults,
    ImportConflictResolver? onConflict,
  }) async {
    final bytes = await File(archivePath).readAsBytes();
    final tarBytes = await _decodeEnvelope(bytes, passphrase: passphrase);
    final manifest = _readManifestFromTar(tarBytes);
    final entries = _unpackTar(tarBytes);

    final existingBoards = await _readExistingBoardIds();
    final existingNames = await _readExistingBoardNamesById();

    final plan = _planRestore(
      entries: entries,
      manifest: manifest,
      mode: mode,
      pathRewrite: pathRewrite,
      overrides: overrides,
      existingBoardIds: existingBoards,
      existingBoardNames: existingNames,
    );

    if (dryRun) {
      return ImportReport(
        manifest: manifest,
        changes: plan.changes,
        missing: plan.missing,
        conflicts: plan.conflicts,
        dryRun: true,
      );
    }

    final resolutions = <String, BoardConflictChoice>{};
    for (final c in plan.conflicts) {
      final choice = onConflict != null
          ? await onConflict(c)
          : BoardConflictChoice.keepBoth;
      resolutions[c.boardId] = choice;
    }

    await _applyRestore(
      entries: entries,
      manifest: manifest,
      mode: mode,
      pathRewrite: pathRewrite,
      overrides: overrides,
      conflictResolutions: resolutions,
    );

    return ImportReport(
      manifest: manifest,
      changes: plan.changes,
      missing: plan.missing,
      conflicts: plan.conflicts,
      dryRun: false,
    );
  }

  // ── Manifest construction ─────────────────────────────────────────────

  Future<ArchiveManifest> _buildManifest({
    required ArchiveIncludeOptions include,
  }) async {
    final pathIndex = <PathIndexEntry>[];

    // Walk workspaces for absolute paths.
    final workspacesFile = File(p.join(_roots.yoloitHome, 'workspaces.json'));
    if (workspacesFile.existsSync()) {
      _indexWorkspacePaths(workspacesFile, pathIndex);
    }

    // Walk SharedPreferences for board metadata + panel path params.
    if (_roots.sharedPrefsAvailable) {
      final prefs = await SharedPreferences.getInstance();
      await _indexPrefsPaths(prefs, pathIndex);
    }

    return ArchiveManifest(
      schemaVersion: ArchiveManifest.currentSchemaVersion,
      createdAt: DateTime.now().toUtc(),
      sourceAppVersion: _appVersion(),
      sourceHostname: _resolveSourceHostname(),
      sourceHome: _resolveSourceHome(),
      sourceUsername: _resolveSourceUsername(),
      contents: const ['prefs', 'config', 'data', 'workspaces'],
      flags: include.toMap(),
      pathIndex: pathIndex,
    );
  }

  void _indexWorkspacePaths(File f, List<PathIndexEntry> out) {
    try {
      final raw = f.readAsStringSync();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final workspaces = decoded['workspaces'];
      if (workspaces is! List) return;
      for (final ws in workspaces) {
        if (ws is! Map) continue;
        final id = ws['id'] as String?;
        final paths = ws['paths'];
        if (paths is! List) continue;
        for (final path in paths) {
          if (path is String && path.startsWith('/')) {
            out.add(
              PathIndexEntry(
                kind: 'workspace.path',
                workspaceId: id,
                old: path,
              ),
            );
          }
        }
      }
    } catch (_) {
      // Corrupt or missing — skip silently.
    }
  }

  Future<void> _indexPrefsPaths(
    SharedPreferences prefs,
    List<PathIndexEntry> out,
  ) async {
    final boardsJson = prefs.getString('board.documents.v1');
    if (boardsJson == null || boardsJson.isEmpty) return;
    try {
      final decoded = jsonDecode(boardsJson);
      if (decoded is! List) return;
      for (final board in decoded) {
        if (board is! Map) continue;
        final id = board['id'] as String?;
        final metadata = board['metadata'];
        if (metadata is Map) {
          final df = metadata['defaultFolder'];
          if (df is String && df.startsWith('/')) {
            out.add(
              PathIndexEntry(
                kind: 'board.defaultFolder',
                boardId: id,
                old: df,
              ),
            );
          }
        }
        final panels = board['panels'];
        if (panels is List) {
          for (final panel in panels) {
            if (panel is! Map) continue;
            final panelId = panel['id'] as String?;
            for (final key in const ['params', 'state']) {
              final container = panel[key];
              if (container is! Map) continue;
              for (final field in const ['path', 'rootPath', 'workingDir']) {
                final v = container[field];
                if (v is String && v.startsWith('/')) {
                  out.add(
                    PathIndexEntry(
                      kind: 'panel.$key.$field',
                      boardId: id,
                      panelId: panelId,
                      old: v,
                    ),
                  );
                }
              }
            }
          }
        }
      }
    } catch (_) {
      // Skip silently on parse errors.
    }
  }

  // ── Tar packing ───────────────────────────────────────────────────────

  Future<List<int>> _buildTar(
    ArchiveManifest manifest, {
    required ArchiveIncludeOptions include,
  }) async {
    final archive = Archive();
    final contents = <String, List<int>>{};

    contents['manifest.json'] = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
    );

    if (_roots.sharedPrefsAvailable) {
      final prefsBytes = await _dumpPrefs();
      if (prefsBytes != null) {
        contents['prefs/preferences.json'] = prefsBytes;
      }
    }

    _collectDir(
      source: _roots.configDir,
      prefix: 'config',
      include: include,
      contents: contents,
    );
    _collectDir(
      source: _roots.dataDir,
      prefix: 'data',
      include: include,
      contents: contents,
    );
    _collectFile(
      source: File(p.join(_roots.yoloitHome, 'config.json')),
      archiveName: 'workspaces/config.json',
      contents: contents,
    );
    _collectFile(
      source: File(p.join(_roots.yoloitHome, 'workspaces.json')),
      archiveName: 'workspaces/workspaces.json',
      contents: contents,
    );

    for (final entry in contents.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }

    return TarEncoder().encode(archive);
  }

  /// Dump all YoLoIT-owned SharedPreferences keys as JSON.
  Future<List<int>?> _dumpPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      out[key] = prefs.get(key);
    }
    if (out.isEmpty) return null;
    return utf8.encode(const JsonEncoder.withIndent('  ').convert(out));
  }

  void _collectDir({
    required String source,
    required String prefix,
    required ArchiveIncludeOptions include,
    required Map<String, List<int>> contents,
  }) {
    final dir = Directory(source);
    if (!dir.existsSync()) return;
    final excludes = _excludesFor(include, prefix);
    _walkDir(dir, prefix, contents, excludes);
  }

  Set<String> _excludesFor(ArchiveIncludeOptions include, String prefix) {
    final out = <String>{};
    if (prefix == 'config') {
      out.add('runtime');
      if (!include.stateJson) out.add('state.json');
      if (!include.templatesCache) out.add('templates/cache');
      if (!include.secrets) out.add('credentials');
    } else if (prefix == 'data') {
      out.add('asr_samples');
      if (!include.history) out.add('boards_history');
      if (!include.chatSessions) out.add('chat_sessions');
      if (!include.calendar) out.add('calendar_events');
    }
    return out;
  }

  void _walkDir(
    Directory dir,
    String prefix,
    Map<String, List<int>> contents,
    Set<String> excludes,
  ) {
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: dir.path);
      if (_isExcluded(rel, excludes)) continue;
      final posixRel = rel.replaceAll(Platform.pathSeparator, '/');
      contents['$prefix/$posixRel'] = entity.readAsBytesSync();
    }
  }

  void _collectFile({
    required File source,
    required String archiveName,
    required Map<String, List<int>> contents,
  }) {
    if (!source.existsSync()) return;
    contents[archiveName] = source.readAsBytesSync();
  }

  bool _isExcluded(String relPath, Set<String> excludes) {
    for (final ex in excludes) {
      if (ex.contains('/')) {
        if (relPath == ex || relPath.startsWith('$ex/')) return true;
      } else {
        final parts = p.split(relPath);
        if (parts.contains(ex)) return true;
      }
    }
    return false;
  }

  // ── Unpacking + restore planning ──────────────────────────────────────

  Future<List<int>> _decodeEnvelope(
    List<int> bytes, {
    String? passphrase,
  }) async {
    if (_cipher.looksEncrypted(bytes)) {
      if (passphrase == null || passphrase.isEmpty) {
        throw const FormatException(
          'Archive is encrypted; provide a passphrase',
        );
      }
      return _cipher.decrypt(Stream.value(bytes), passphrase);
    }
    return bytes;
  }

  ArchiveManifest _readManifestFromTar(List<int> tarBytes) {
    final archive = TarDecoder().decodeBytes(tarBytes);
    final manifestFile = archive.files.firstWhere(
      (f) => f.name == 'manifest.json',
      orElse: () => throw const FormatException(
        'Archive is missing manifest.json',
      ),
    );
    final content = manifestFile.content as List<int>;
    final json = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
    return ArchiveManifest.fromJson(json);
  }

  List<ArchiveFile> _unpackTar(List<int> tarBytes) {
    return TarDecoder().decodeBytes(tarBytes).files;
  }

  ({List<PlannedChange> changes, List<MissingPathWarning> missing, List<BoardConflict> conflicts}) _planRestore({
    required List<ArchiveFile> entries,
    required ArchiveManifest manifest,
    required ImportMode mode,
    required PathRewriteStrategy pathRewrite,
    required ImportOverrides overrides,
    required Set<String> existingBoardIds,
    required Map<String, String> existingBoardNames,
  }) {
    final changes = <PlannedChange>[];
    final missing = <MissingPathWarning>[];
    final boardConflicts = <BoardConflict>[];

    final pathRewrites = _buildPathRewrites(manifest, pathRewrite);

    for (final entry in entries) {
      if (entry.name == 'manifest.json') continue;
      if (!entry.name.contains('/')) continue;

      final root = entry.name.split('/').first;
      if (!_isRootEnabled(root, overrides)) continue;

      final relPath = entry.name.substring(root.length + 1);
      final action = _planFileAction(root: root, relPath: relPath, mode: mode);

      changes.add(PlannedChange(root: root, action: action, path: relPath));

      if (root == 'prefs' && relPath == 'preferences.json') {
        _detectBoardConflicts(
          entry,
          existingBoardIds,
          existingBoardNames,
          boardConflicts,
        );
      }
    }

    for (final idx in manifest.pathIndex) {
      final rewritten = _applyPathRewrites(idx.old, pathRewrites);
      if (rewritten == idx.old && !File(idx.old).existsSync()) {
        missing.add(MissingPathWarning(entry: idx, rewritten: rewritten));
      } else if (rewritten != idx.old &&
          !Directory(p.dirname(rewritten)).existsSync()) {
        missing.add(MissingPathWarning(entry: idx, rewritten: rewritten));
      }
    }

    return (changes: changes, missing: missing, conflicts: boardConflicts);
  }

  bool _isRootEnabled(String root, ImportOverrides overrides) {
    switch (root) {
      case 'prefs':
        return overrides.prefs;
      case 'config':
        return overrides.config;
      case 'data':
        return overrides.data;
      case 'workspaces':
        return overrides.workspaces;
      default:
        return true;
    }
  }

  String _planFileAction({
    required String root,
    required String relPath,
    required ImportMode mode,
  }) {
    final dest = _resolveDest(root, relPath);
    if (root == 'prefs') {
      // SharedPreferences writes don't conflict at file-system level —
      // the planner reports them as "add" by default; board-id collisions
      // are surfaced separately via [BoardConflict].
      return 'add';
    }
    final exists = dest.existsSync();
    if (!exists) return 'add';
    return mode == ImportMode.replace ? 'overwrite' : 'skip';
  }

  File _resolveDest(String root, String relPath) {
    switch (root) {
      case 'config':
        return File(p.join(_roots.configDir, relPath));
      case 'data':
        return File(p.join(_roots.dataDir, relPath));
      case 'workspaces':
        return File(p.join(_roots.yoloitHome, relPath));
      case 'prefs':
      default:
        // Prefs go through SharedPreferences, not the filesystem.
        return File(p.join(_roots.platformDirs.tempDir, 'prefs_$relPath'));
    }
  }

  Map<String, String> _buildPathRewrites(
    ArchiveManifest manifest,
    PathRewriteStrategy strategy,
  ) {
    if (strategy != PathRewriteStrategy.auto) return const {};
    final sourceHome = manifest.sourceHome;
    final targetHome = _roots.platformDirs.userHome;
    if (targetHome == null || targetHome.isEmpty) return const {};
    if (sourceHome == targetHome || sourceHome.isEmpty) return const {};
    return {sourceHome: targetHome};
  }

  String _applyPathRewrites(String path, Map<String, String> rewrites) {
    var current = path;
    for (final entry in rewrites.entries) {
      if (current.startsWith(entry.key)) {
        current = entry.value + current.substring(entry.key.length);
      }
    }
    return current;
  }

  Future<Set<String>> _readExistingBoardIds() async {
    final out = <String>{};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('board.documents.v1');
    if (raw == null) return out;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final b in decoded) {
          if (b is Map && b['id'] is String) out.add(b['id'] as String);
        }
      }
    } catch (_) {}
    return out;
  }

  Future<Map<String, String>> _readExistingBoardNamesById() async {
    final out = <String, String>{};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('board.documents.v1');
    if (raw == null) return out;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final b in decoded) {
          if (b is Map && b['id'] is String) {
            out[b['id'] as String] = (b['name'] as String?) ?? '';
          }
        }
      }
    } catch (_) {}
    return out;
  }

  void _detectBoardConflicts(
    ArchiveFile entry,
    Set<String> existingIds,
    Map<String, String> existingNames,
    List<BoardConflict> out,
  ) {
    try {
      final json = jsonDecode(utf8.decode(entry.content as List<int>));
      if (json is! Map) return;
      final raw = json['board.documents.v1'];
      if (raw is! String) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final b in decoded) {
        if (b is! Map) continue;
        final id = b['id'] as String?;
        if (id == null || !existingIds.contains(id)) continue;
        out.add(
          BoardConflict(
            boardId: id,
            incomingName: (b['name'] as String?) ?? '',
            existingName: existingNames[id] ?? '',
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _applyRestore({
    required List<ArchiveFile> entries,
    required ArchiveManifest manifest,
    required ImportMode mode,
    required PathRewriteStrategy pathRewrite,
    required ImportOverrides overrides,
    required Map<String, BoardConflictChoice> conflictResolutions,
  }) async {
    final pathRewrites = _buildPathRewrites(manifest, pathRewrite);

    for (final entry in entries) {
      if (entry.name == 'manifest.json') continue;
      if (!entry.name.contains('/')) continue;
      final root = entry.name.split('/').first;
      if (!_isRootEnabled(root, overrides)) continue;
      final relPath = entry.name.substring(root.length + 1);
      final content = entry.content as List<int>;

      if (root == 'prefs') {
        await _restorePrefs(content);
        continue;
      }
      if (root == 'workspaces' && relPath == 'workspaces.json') {
        await _restoreWorkspacesJson(content, pathRewrites);
        continue;
      }

      final destBase = root == 'config' ? _roots.configDir : _roots.dataDir;
      final dest = File(p.join(destBase, relPath));
      final plan = _planFileAction(root: root, relPath: relPath, mode: mode);
      if (plan == 'skip') continue;
      dest.parent.createSync(recursive: true);
      dest.writeAsBytesSync(content);
    }

    // Note: conflict resolutions are recorded but the prefs restore above
    // doesn't yet rewrite board names. Future phase: wire renameIncoming /
    // skipIncoming into _restorePrefs by mutating the JSON before write.
    if (conflictResolutions.isNotEmpty) {
      // Hook for future conflict-aware restore. No-op in phase 1.
    }
  }

  Future<void> _restorePrefs(List<int> content) async {
    final json = jsonDecode(utf8.decode(content));
    if (json is! Map) return;
    final prefs = await SharedPreferences.getInstance();
    for (final entry in json.entries) {
      final key = entry.key as String;
      final value = entry.value;
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, value.cast<String>());
      }
    }
  }

  Future<void> _restoreWorkspacesJson(
    List<int> content,
    Map<String, String> pathRewrites,
  ) async {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
    } catch (_) {
      json = {};
    }
    final workspaces = json['workspaces'];
    if (workspaces is! List) return;
    final out = <Map<String, dynamic>>[];
    for (final ws in workspaces) {
      if (ws is! Map) {
        out.add(<String, dynamic>{});
        continue;
      }
      final m = Map<String, dynamic>.from(ws);
      final paths = m['paths'];
      if (paths is List) {
        m['paths'] = paths.map<String>((e) {
          if (e is String) return _applyPathRewrites(e, pathRewrites);
          return e.toString();
        }).toList();
      }
      out.add(m);
    }
    json['workspaces'] = out;

    final dest = File(p.join(_roots.yoloitHome, 'workspaces.json'));
    dest.parent.createSync(recursive: true);
    dest.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  }
}
