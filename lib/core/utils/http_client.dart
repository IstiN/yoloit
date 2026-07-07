// Conditional export: VM uses dart:io HttpClient, web uses package:http.
library;

export 'http_client_base.dart';
export 'http_client_vm.dart'
    if (dart.library.html) 'http_client_web.dart';
