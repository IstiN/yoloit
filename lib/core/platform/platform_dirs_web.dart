import 'package:yoloit/core/platform/platform_dirs.dart';

PlatformDirs createPlatformDirs() => const WebPlatformDirs();

/// Web stub for [PlatformDirs].
///
/// Browser storage has no real file system, so these paths are used only as
/// scoped prefixes by [FileStorageAdapter].
class WebPlatformDirs extends PlatformDirs {
  const WebPlatformDirs();

  @override
  String get configDir => 'yoloit';

  @override
  String get dataDir => 'yoloit';

  @override
  String get logsDir => 'yoloit/logs';

  @override
  String get tempDir => 'yoloit/tmp';

  @override
  String get skillsDir => 'yoloit/skills';

  @override
  String get yoloitTempDir => 'yoloit/tmp';
}
