// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'card_props.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChangedFileEntry _$ChangedFileEntryFromJson(Map<String, dynamic> json) =>
    ChangedFileEntry(
      path: json['path'] as String,
      name: json['name'] as String,
      status: json['status'] as String,
      addedLines: (json['addedLines'] as num?)?.toInt() ?? 0,
      removedLines: (json['removedLines'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$ChangedFileEntryToJson(ChangedFileEntry instance) =>
    <String, dynamic>{
      'path': instance.path,
      'name': instance.name,
      'status': instance.status,
      'addedLines': instance.addedLines,
      'removedLines': instance.removedLines,
    };
