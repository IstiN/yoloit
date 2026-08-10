import 'package:yoloit/core/platform/platform_installer.dart';

/// Recording [PlatformInstaller] fake for update-flow tests.
///
/// Records every call and never touches the real filesystem or exits the
/// process, so it is safe to install via [PlatformInstaller.setInstance]
/// in unit and widget tests.
class FakePlatformInstaller extends PlatformInstaller {
  FakePlatformInstaller({this.supports = true, this.appVersion = '1.0.0'});

  /// Value returned by [supportsInAppInstall].
  final bool supports;

  /// Value returned by [getAppVersion].
  final String appVersion;

  /// When set, [downloadAndPrepare] throws this error.
  Object? errorOnPrepare;

  final List<String> preparedUrls = <String>[];
  final List<String?> preparedTags = <String?>[];
  final List<String> launchedTokens = <String>[];

  @override
  bool get supportsInAppInstall => supports;

  @override
  Future<String> getAppVersion({String fallback = '0.0.0'}) async => appVersion;

  @override
  Future<String> downloadAndPrepare({
    required String downloadUrl,
    required ProgressCallback onProgress,
    String? releaseTag,
  }) async {
    preparedUrls.add(downloadUrl);
    preparedTags.add(releaseTag);
    final error = errorOnPrepare;
    if (error != null) throw error;
    onProgress(0.5, 'Downloading…');
    onProgress(null, 'Ready to install');
    return 'tok-${preparedUrls.length}';
  }

  @override
  Future<void> launchAndExit(String launchToken) async {
    launchedTokens.add(launchToken);
  }
}
