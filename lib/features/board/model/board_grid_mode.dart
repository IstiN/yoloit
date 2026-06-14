import 'package:equatable/equatable.dart';

/// Persistent configuration for the board grid view.
class BoardGridMode extends Equatable {
  const BoardGridMode({
    this.enabled = false,
    this.cellSize = 220.0,
    this.spacing = 24.0,
  });

  final bool enabled;
  final double cellSize;
  final double spacing;

  BoardGridMode copyWith({bool? enabled, double? cellSize, double? spacing}) {
    return BoardGridMode(
      enabled: enabled ?? this.enabled,
      cellSize: cellSize ?? this.cellSize,
      spacing: spacing ?? this.spacing,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'cellSize': cellSize,
    'spacing': spacing,
  };

  factory BoardGridMode.fromJson(Map<String, dynamic> json) {
    return BoardGridMode(
      enabled: json['enabled'] as bool? ?? false,
      cellSize: (json['cellSize'] as num?)?.toDouble() ?? 220.0,
      spacing: (json['spacing'] as num?)?.toDouble() ?? 24.0,
    );
  }

  @override
  List<Object?> get props => [enabled, cellSize, spacing];
}
