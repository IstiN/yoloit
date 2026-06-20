import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// The origin of a set of board templates.
///
/// Templates may be loaded from a local directory on disk or from a remote
/// GitHub repository. The repository path inside the repo is fixed to
/// `yoloit/templates` by convention.
class TemplateSource extends Equatable {
  const TemplateSource({
    required this.id,
    required this.type,
    this.localPath,
    this.githubOwner,
    this.githubRepo,
    this.githubBranch,
    this.githubPath = 'yoloit/templates',
    this.githubToken,
    this.enabled = true,
  }) : assert(
         type == TemplateSourceType.local ? localPath != null : true,
         'localPath is required for local sources',
       ),
       assert(
         type == TemplateSourceType.github
             ? githubOwner != null && githubRepo != null
             : true,
         'githubOwner and githubRepo are required for github sources',
       );

  final String id;
  final TemplateSourceType type;
  final String? localPath;
  final String? githubOwner;
  final String? githubRepo;
  final String? githubBranch;
  final String githubPath;
  final String? githubToken;
  final bool enabled;

  String get displayName {
    switch (type) {
      case TemplateSourceType.local:
        return 'Local: $localPath';
      case TemplateSourceType.github:
        return 'GitHub: $githubOwner/$githubRepo';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'localPath': localPath,
    'githubOwner': githubOwner,
    'githubRepo': githubRepo,
    'githubBranch': githubBranch,
    'githubPath': githubPath,
    'githubToken': githubToken,
    'enabled': enabled,
  };

  factory TemplateSource.fromJson(Map<String, dynamic> json) {
    final type = TemplateSourceType.values.byName(
      (json['type'] as String? ?? 'local'),
    );
    return TemplateSource(
      id: json['id'] as String? ?? '',
      type: type,
      localPath: json['localPath'] as String?,
      githubOwner: json['githubOwner'] as String?,
      githubRepo: json['githubRepo'] as String?,
      githubBranch: json['githubBranch'] as String?,
      githubPath: json['githubPath'] as String? ?? 'yoloit/templates',
      githubToken: json['githubToken'] as String?,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  TemplateSource copyWith({
    String? id,
    TemplateSourceType? type,
    String? localPath,
    String? githubOwner,
    String? githubRepo,
    String? githubBranch,
    String? githubPath,
    String? githubToken,
    bool? enabled,
  }) => TemplateSource(
    id: id ?? this.id,
    type: type ?? this.type,
    localPath: localPath ?? this.localPath,
    githubOwner: githubOwner ?? this.githubOwner,
    githubRepo: githubRepo ?? this.githubRepo,
    githubBranch: githubBranch ?? this.githubBranch,
    githubPath: githubPath ?? this.githubPath,
    githubToken: githubToken ?? this.githubToken,
    enabled: enabled ?? this.enabled,
  );

  @override
  List<Object?> get props => [
    id,
    type,
    localPath,
    githubOwner,
    githubRepo,
    githubBranch,
    githubPath,
    githubToken,
    enabled,
  ];
}

enum TemplateSourceType { local, github }

/// A single user-configurable value for a board template.
class TemplateParameter extends Equatable {
  const TemplateParameter({
    required this.name,
    required this.type,
    required this.label,
    this.description,
    this.required = false,
    this.defaultValue,
    this.options,
    this.picker,
    this.validation,
  }) : assert(
         type != TemplateParameterType.choice || options != null,
         'choice parameters must provide options',
       );

  final String name;
  final TemplateParameterType type;
  final String label;
  final String? description;
  final bool required;
  final Object? defaultValue;
  final List<TemplateParameterOption>? options;
  final TemplateParameterPicker? picker;
  final TemplateParameterValidation? validation;

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.name,
    'label': label,
    'description': description,
    'required': required,
    'default': defaultValue,
    'options': options?.map((o) => o.toJson()).toList(),
    'picker': picker?.name,
    'validation': validation?.toJson(),
  };

  factory TemplateParameter.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'] as List?;
    final rawValidation = json['validation'];
    return TemplateParameter(
      name: json['name'] as String? ?? '',
      type: TemplateParameterType.values.byName(
        (json['type'] as String? ?? 'string'),
      ),
      label: json['label'] as String? ?? json['name'] as String? ?? '',
      description: json['description'] as String?,
      required: json['required'] as bool? ?? false,
      defaultValue: json['default'],
      options:
          rawOptions
              ?.map(
                (e) => TemplateParameterOption.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList(),
      picker:
          json['picker'] == null
              ? null
              : TemplateParameterPicker.values.byName(
                json['picker'] as String,
              ),
      validation:
          rawValidation is Map
              ? TemplateParameterValidation.fromJson(
                Map<String, dynamic>.from(rawValidation),
              )
              : null,
    );
  }

  @override
  List<Object?> get props => [
    name,
    type,
    label,
    description,
    required,
    defaultValue,
    options,
    picker,
    validation,
  ];
}

enum TemplateParameterType {
  string,
  text,
  path,
  boolean,
  choice,
  color,
}

enum TemplateParameterPicker { file, directory }

class TemplateParameterOption extends Equatable {
  const TemplateParameterOption({required this.value, required this.label});

  final String value;
  final String label;

  Map<String, dynamic> toJson() => {'value': value, 'label': label};

  factory TemplateParameterOption.fromJson(Map<String, dynamic> json) =>
      TemplateParameterOption(
        value: json['value']?.toString() ?? '',
        label: json['label']?.toString() ?? json['value']?.toString() ?? '',
      );

  @override
  List<Object?> get props => [value, label];
}

class TemplateParameterValidation extends Equatable {
  const TemplateParameterValidation({
    this.minLength,
    this.maxLength,
    this.pattern,
    this.min,
    this.max,
  });

  final int? minLength;
  final int? maxLength;
  final String? pattern;
  final num? min;
  final num? max;

  Map<String, dynamic> toJson() => {
    'minLength': minLength,
    'maxLength': maxLength,
    'pattern': pattern,
    'min': min,
    'max': max,
  };

  factory TemplateParameterValidation.fromJson(Map<String, dynamic> json) =>
      TemplateParameterValidation(
        minLength: json['minLength'] as int?,
        maxLength: json['maxLength'] as int?,
        pattern: json['pattern'] as String?,
        min: json['min'] as num?,
        max: json['max'] as num?,
      );

  @override
  List<Object?> get props => [minLength, maxLength, pattern, min, max];
}

/// A single operation inside a template.
///
/// The payload is intentionally a plain map so that templates can reuse the
/// same operation vocabulary as `board:apply` without the model layer knowing
/// about every possible field.
@immutable
class TemplateOperation {
  const TemplateOperation({this.condition, required this.payload});

  /// When non-null, the operation is applied only if the interpolated value
  /// evaluates to a truthy string ('true', 'yes', '1') or boolean `true`.
  final String? condition;

  /// The raw `board:apply` operation map. Parameter interpolation happens
  /// at apply time, not at parse time.
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
    if (condition != null) 'condition': condition,
    ...payload,
  };

  factory TemplateOperation.fromJson(Map<String, dynamic> json) {
    final payload = Map<String, dynamic>.from(json);
    final condition = payload.remove('condition') as String?;
    return TemplateOperation(condition: condition, payload: payload);
  }
}

/// A loaded board template ready to be rendered or applied.
class BoardTemplate extends Equatable {
  const BoardTemplate({
    required this.id,
    required this.name,
    this.icon,
    this.author,
    this.description,
    this.parameters = const [],
    this.operations = const [],
    required this.sourceId,
    this.sourcePath,
  });

  final String id;
  final String name;
  final String? icon;
  final String? author;
  final String? description;
  final List<TemplateParameter> parameters;
  final List<TemplateOperation> operations;
  final String sourceId;
  final String? sourcePath;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'author': author,
    'description': description,
    'parameters': parameters.map((p) => p.toJson()).toList(),
    'operations': operations.map((o) => o.toJson()).toList(),
    'sourceId': sourceId,
    'sourcePath': sourcePath,
  };

  factory BoardTemplate.fromJson(Map<String, dynamic> json) {
    final rawParams = json['parameters'] as List?;
    final rawOps = json['operations'] as List?;
    return BoardTemplate(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['id'] as String? ?? 'Template',
      icon: json['icon'] as String?,
      author: json['author'] as String?,
      description: json['description'] as String?,
      parameters:
          rawParams
              ?.map(
                (e) => TemplateParameter.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList() ??
          const [],
      operations:
          rawOps
              ?.map(
                (e) => TemplateOperation.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList() ??
          const [],
      sourceId: json['sourceId'] as String? ?? '',
      sourcePath: json['sourcePath'] as String?,
    );
  }

  BoardTemplate copyWith({
    String? id,
    String? name,
    String? icon,
    String? author,
    String? description,
    List<TemplateParameter>? parameters,
    List<TemplateOperation>? operations,
    String? sourceId,
    String? sourcePath,
  }) => BoardTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    author: author ?? this.author,
    description: description ?? this.description,
    parameters: parameters ?? this.parameters,
    operations: operations ?? this.operations,
    sourceId: sourceId ?? this.sourceId,
    sourcePath: sourcePath ?? this.sourcePath,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    icon,
    author,
    description,
    parameters,
    operations,
    sourceId,
    sourcePath,
  ];
}
