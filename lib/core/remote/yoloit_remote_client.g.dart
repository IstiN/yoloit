// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'yoloit_remote_client.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RemoteSetupInstallRun _$RemoteSetupInstallRunFromJson(
  Map<String, dynamic> json,
) => RemoteSetupInstallRun(
  id: json['id'] as String,
  script: json['script'] as String,
);

Map<String, dynamic> _$RemoteSetupInstallRunToJson(
  RemoteSetupInstallRun instance,
) => <String, dynamic>{'id': instance.id, 'script': instance.script};

RemoteSetupInstallLog _$RemoteSetupInstallLogFromJson(
  Map<String, dynamic> json,
) => RemoteSetupInstallLog(
  id: json['id'] as String,
  lines: (json['lines'] as List<dynamic>).map((e) => e as String).toList(),
  running: json['running'] as bool,
  exitCode: (json['exitCode'] as num?)?.toInt(),
);

Map<String, dynamic> _$RemoteSetupInstallLogToJson(
  RemoteSetupInstallLog instance,
) => <String, dynamic>{
  'id': instance.id,
  'lines': instance.lines,
  'running': instance.running,
  'exitCode': instance.exitCode,
};

RemoteDirectoryListing _$RemoteDirectoryListingFromJson(
  Map<String, dynamic> json,
) => RemoteDirectoryListing(
  path: json['path'] as String,
  parent: json['parent'] as String?,
  entries:
      (json['entries'] as List<dynamic>)
          .map((e) => RemoteDirectoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
  roots:
      (json['roots'] as List<dynamic>)
          .map((e) => RemoteDirectoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
);

Map<String, dynamic> _$RemoteDirectoryListingToJson(
  RemoteDirectoryListing instance,
) => <String, dynamic>{
  'path': instance.path,
  'parent': instance.parent,
  'entries': instance.entries,
  'roots': instance.roots,
};

RemoteDirectoryEntry _$RemoteDirectoryEntryFromJson(
  Map<String, dynamic> json,
) => RemoteDirectoryEntry(
  name: json['name'] as String,
  path: json['path'] as String,
  isDirectory: json['isDirectory'] as bool,
);

Map<String, dynamic> _$RemoteDirectoryEntryToJson(
  RemoteDirectoryEntry instance,
) => <String, dynamic>{
  'name': instance.name,
  'path': instance.path,
  'isDirectory': instance.isDirectory,
};

RemoteTerminalLog _$RemoteTerminalLogFromJson(Map<String, dynamic> json) =>
    RemoteTerminalLog(
      next: (json['next'] as num).toInt(),
      chunks:
          (json['chunks'] as List<dynamic>).map((e) => e as String).toList(),
      running: json['running'] as bool,
      exitCode: (json['exitCode'] as num?)?.toInt(),
    );

Map<String, dynamic> _$RemoteTerminalLogToJson(RemoteTerminalLog instance) =>
    <String, dynamic>{
      'next': instance.next,
      'chunks': instance.chunks,
      'running': instance.running,
      'exitCode': instance.exitCode,
    };
