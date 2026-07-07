// Conditional export: VM uses dart:io implementation, web uses in-memory stub.
library;

export 'yoloit_credential_store_base.dart';
export 'yoloit_credential_store_vm.dart'
    if (dart.library.html) 'yoloit_credential_store_web.dart';
