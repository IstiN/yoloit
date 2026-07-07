// Conditional export: VM uses dart:io implementation, web uses in-memory stub.
library;

export 'secure_storage_factory_vm.dart'
    if (dart.library.html) 'secure_storage_factory_web.dart';
