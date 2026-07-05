/// Web stub for [PlatformShell] symbols used by [ProviderModelCatalogService].
abstract class PlatformShell {
  static final PlatformShell _instance = _WebPlatformShell();
  static PlatformShell get instance => _instance;

  String enrichedPath(String existing) => existing;
}

class _WebPlatformShell extends PlatformShell {}
