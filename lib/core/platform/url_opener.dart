import 'package:yoloit/core/platform/url_opener_vm.dart'
    if (dart.library.html) 'package:yoloit/core/platform/url_opener_web.dart';

export 'package:yoloit/core/platform/url_opener_vm.dart'
    if (dart.library.html) 'package:yoloit/core/platform/url_opener_web.dart';

/// Opens [url] in the platform default browser (desktop) or a new tab (web).
Future<void> launchExternalUrl(String url) => openUrl(url);
