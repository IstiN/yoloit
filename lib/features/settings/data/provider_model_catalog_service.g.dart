// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider_model_catalog_service.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProviderCatalog _$ProviderCatalogFromJson(Map<String, dynamic> json) =>
    ProviderCatalog(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      models: (json['models'] as List<dynamic>)
          .map((e) => ChatModelInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ProviderCatalogToJson(ProviderCatalog instance) =>
    <String, dynamic>{
      'id': instance.id,
      'displayName': instance.displayName,
      'models': instance.models.map((e) => e.toJson()).toList(),
    };
