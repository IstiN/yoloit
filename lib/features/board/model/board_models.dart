import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:yoloit/features/board/model/board_json_converters.dart';

part 'board_models.g.dart';

enum BoardLinkStyle { line, arrow }

enum BoardLinkBehavior { fixed, dynamic }

/// Line geometry for board links.
enum BoardLinkGeometry { bezier, straight, elbow }

// ─────────────────────────────────────────────────────────────────────────────
// Drawing element
// ─────────────────────────────────────────────────────────────────────────────

/// A free-hand drawing element stored as a list of strokes.
///
/// Each stroke is a list of [Offset] points **relative to [position]**
/// (the top-left of the element's bounding box in board space).
/// This makes dragging cheap — only [position] needs to change.
class BoardDrawingElement extends Equatable {
  const BoardDrawingElement({
    required this.id,
    required this.strokes,
    required this.position,
    required this.size,
    required this.strokeColor,
    required this.strokeWidth,
    this.zIndex = 0,
    this.hidden = false,
  });

  final String id;

  /// Strokes as lists of points relative to [position].
  final List<List<Offset>> strokes;

  /// Top-left of the bounding box in board space.
  final Offset position;

  /// Bounding box size (width × height) in board space.
  final Size size;

  final Color strokeColor;
  final double strokeWidth;
  final int zIndex;
  final bool hidden;

  Rect get bounds => position & size;

  BoardDrawingElement copyWith({
    String? id,
    List<List<Offset>>? strokes,
    Offset? position,
    Size? size,
    Color? strokeColor,
    double? strokeWidth,
    int? zIndex,
    bool? hidden,
  }) {
    return BoardDrawingElement(
      id: id ?? this.id,
      strokes: strokes ?? this.strokes,
      position: position ?? this.position,
      size: size ?? this.size,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      zIndex: zIndex ?? this.zIndex,
      hidden: hidden ?? this.hidden,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'strokes':
        strokes
            .map((stroke) => stroke.map((p) => [p.dx, p.dy]).toList())
            .toList(),
    'position': [position.dx, position.dy],
    'size': [size.width, size.height],
    'strokeColor': strokeColor.toARGB32(),
    'strokeWidth': strokeWidth,
    'zIndex': zIndex,
    'hidden': hidden,
  };

  factory BoardDrawingElement.fromJson(Map<String, dynamic> json) {
    final rawStrokes = json['strokes'] as List? ?? const [];
    final rawPos = json['position'] as List? ?? const [0, 0];
    final rawSize = json['size'] as List? ?? const [100, 100];
    return BoardDrawingElement(
      id: json['id'] as String,
      strokes:
          rawStrokes
              .map(
                (stroke) =>
                    (stroke as List)
                        .map(
                          (p) => Offset(
                            (p as List)[0] is num
                                ? (p[0] as num).toDouble()
                                : 0,
                            p[1] is num ? (p[1] as num).toDouble() : 0,
                          ),
                        )
                        .toList(),
              )
              .toList(),
      position: Offset(
        (rawPos[0] as num).toDouble(),
        (rawPos[1] as num).toDouble(),
      ),
      size: Size(
        (rawSize[0] as num).toDouble(),
        (rawSize[1] as num).toDouble(),
      ),
      strokeColor: Color((json['strokeColor'] as num).toInt()),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 3.0,
      zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      hidden: json['hidden'] as bool? ?? false,
    );
  }

  /// Build a [BoardDrawingElement] from raw board-space points captured during
  /// a single draw gesture. Points must not be empty.
  factory BoardDrawingElement.fromRawStroke({
    required String id,
    required List<Offset> rawPoints,
    required Color strokeColor,
    required double strokeWidth,
    int zIndex = 0,
  }) {
    assert(rawPoints.isNotEmpty);
    double minX = rawPoints.first.dx;
    double minY = rawPoints.first.dy;
    double maxX = minX;
    double maxY = minY;
    for (final p in rawPoints) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    const padding = 8.0;
    final origin = Offset(minX - padding, minY - padding);
    final relativePoints = rawPoints
        .map((p) => p - origin)
        .toList(growable: false);
    return BoardDrawingElement(
      id: id,
      strokes: [relativePoints],
      position: origin,
      size: Size(
        math.max(maxX - minX + padding * 2, strokeWidth * 2),
        math.max(maxY - minY + padding * 2, strokeWidth * 2),
      ),
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      zIndex: zIndex,
    );
  }

  @override
  List<Object?> get props => [
    id,
    strokes,
    position,
    size,
    strokeColor,
    strokeWidth,
    zIndex,
    hidden,
  ];
}

class BoardViewport extends Equatable {
  const BoardViewport({
    this.scale = 1.0,
    this.translation = Offset.zero,
    this.focusedPanelId,
    this.zoomOnFocus = false,
  });

  final double scale;
  final Offset translation;
  final String? focusedPanelId;

  /// Transient flag — set by CLI/assistant focus commands to trigger zoom-to-panel.
  /// Cleared after the zoom animation is applied. Not persisted across restarts.
  final bool zoomOnFocus;

  BoardViewport copyWith({
    double? scale,
    Offset? translation,
    String? focusedPanelId,
    bool clearFocusedPanelId = false,
    bool? zoomOnFocus,
  }) {
    return BoardViewport(
      scale: scale ?? this.scale,
      translation: translation ?? this.translation,
      focusedPanelId:
          clearFocusedPanelId ? null : (focusedPanelId ?? this.focusedPanelId),
      zoomOnFocus: zoomOnFocus ?? this.zoomOnFocus,
    );
  }

  Map<String, dynamic> toJson() => {
    'scale': scale,
    'translation': [translation.dx, translation.dy],
    'focusedPanelId': focusedPanelId,
    // zoomOnFocus is transient — not persisted
  };

  factory BoardViewport.fromJson(Map<String, dynamic> json) {
    final rawTranslation = json['translation'];
    final List<num> values =
        rawTranslation is List ? rawTranslation.cast<num>() : const <num>[];
    return BoardViewport(
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      translation:
          values.length >= 2
              ? Offset(values[0].toDouble(), values[1].toDouble())
              : Offset.zero,
      focusedPanelId: json['focusedPanelId'] as String?,
      // zoomOnFocus always starts false on load
    );
  }

  @override
  List<Object?> get props => [scale, translation, focusedPanelId, zoomOnFocus];
}

@JsonSerializable()
class BoardPanelBounds extends Equatable {
  const BoardPanelBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  @JsonKey(defaultValue: 0.0)
  final double x;
  @JsonKey(defaultValue: 0.0)
  final double y;
  @JsonKey(defaultValue: 320.0)
  final double width;
  @JsonKey(defaultValue: 220.0)
  final double height;

  Offset get offset => Offset(x, y);
  Size get size => Size(width, height);
  Rect get rect => Rect.fromLTWH(x, y, width, height);

  BoardPanelBounds copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return BoardPanelBounds(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toJson() => _$BoardPanelBoundsToJson(this);

  factory BoardPanelBounds.fromJson(Map<String, dynamic> json) =>
      _$BoardPanelBoundsFromJson(json);

  @override
  List<Object?> get props => [x, y, width, height];
}

@JsonSerializable()
class BoardPanelInstance extends Equatable {
  const BoardPanelInstance({
    required this.id,
    required this.type,
    required this.title,
    required this.bounds,
    this.color,
    this.params = const {},
    this.state = const {},
    this.zIndex = 0,
    this.hidden = false,
    this.locked = false,
    this.pinned = false,
  });

  final String id;
  final String type;
  @JsonKey(defaultValue: 'Panel')
  final String title;
  final BoardPanelBounds bounds;
  @ColorNullableJsonConverter()
  final Color? color;
  final Map<String, dynamic> params;
  final Map<String, dynamic> state;
  @JsonKey(defaultValue: 0)
  final int zIndex;
  @JsonKey(defaultValue: false)
  final bool hidden;
  @JsonKey(defaultValue: false)
  final bool locked;
  @JsonKey(defaultValue: false)
  final bool pinned;

  BoardPanelInstance copyWith({
    String? id,
    String? type,
    String? title,
    BoardPanelBounds? bounds,
    Color? color,
    bool clearColor = false,
    Map<String, dynamic>? params,
    Map<String, dynamic>? state,
    int? zIndex,
    bool? hidden,
    bool? locked,
    bool? pinned,
  }) {
    return BoardPanelInstance(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      bounds: bounds ?? this.bounds,
      color: clearColor ? null : (color ?? this.color),
      params: params ?? this.params,
      state: state ?? this.state,
      zIndex: zIndex ?? this.zIndex,
      hidden: hidden ?? this.hidden,
      locked: locked ?? this.locked,
      pinned: pinned ?? this.pinned,
    );
  }

  Map<String, dynamic> toJson() => _$BoardPanelInstanceToJson(this);

  factory BoardPanelInstance.fromJson(Map<String, dynamic> json) =>
      _$BoardPanelInstanceFromJson(json);

  @override
  List<Object?> get props => [
    id,
    type,
    title,
    bounds,
    color,
    params,
    state,
    zIndex,
    hidden,
    locked,
    pinned,
  ];
}

@JsonSerializable()
class BoardPanelLink extends Equatable {
  const BoardPanelLink({
    required this.id,
    required this.fromPanelId,
    required this.toPanelId,
    this.style = BoardLinkStyle.arrow,
    this.behavior = BoardLinkBehavior.fixed,
    this.color = Colors.lightBlueAccent,
    this.geometry = BoardLinkGeometry.bezier,
  });

  final String id;
  final String fromPanelId;
  final String toPanelId;
  final BoardLinkStyle style;
  final BoardLinkBehavior behavior;
  @ColorJsonConverter()
  final Color color;
  final BoardLinkGeometry geometry;

  BoardPanelLink copyWith({
    String? id,
    String? fromPanelId,
    String? toPanelId,
    BoardLinkStyle? style,
    BoardLinkBehavior? behavior,
    Color? color,
    BoardLinkGeometry? geometry,
  }) {
    return BoardPanelLink(
      id: id ?? this.id,
      fromPanelId: fromPanelId ?? this.fromPanelId,
      toPanelId: toPanelId ?? this.toPanelId,
      style: style ?? this.style,
      behavior: behavior ?? this.behavior,
      color: color ?? this.color,
      geometry: geometry ?? this.geometry,
    );
  }

  Map<String, dynamic> toJson() => _$BoardPanelLinkToJson(this);

  factory BoardPanelLink.fromJson(Map<String, dynamic> json) =>
      _$BoardPanelLinkFromJson(json);

  @override
  List<Object?> get props => [
    id,
    fromPanelId,
    toPanelId,
    style,
    behavior,
    color,
    geometry,
  ];
}

class BoardDocument extends Equatable {
  const BoardDocument({
    required this.id,
    required this.name,
    this.viewport = const BoardViewport(),
    this.panels = const [],
    this.links = const [],
    this.drawings = const [],
    this.metadata = const {},
  });

  final String id;
  final String name;
  final BoardViewport viewport;
  final List<BoardPanelInstance> panels;
  final List<BoardPanelLink> links;
  final List<BoardDrawingElement> drawings;
  final Map<String, dynamic> metadata;

  String get defaultFolder =>
      (metadata['defaultFolder'] as String? ?? '').trim();

  BoardDocument copyWith({
    String? id,
    String? name,
    BoardViewport? viewport,
    List<BoardPanelInstance>? panels,
    List<BoardPanelLink>? links,
    List<BoardDrawingElement>? drawings,
    Map<String, dynamic>? metadata,
  }) {
    return BoardDocument(
      id: id ?? this.id,
      name: name ?? this.name,
      viewport: viewport ?? this.viewport,
      panels: panels ?? this.panels,
      links: links ?? this.links,
      drawings: drawings ?? this.drawings,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'viewport': viewport.toJson(),
    'panels': panels.map((panel) => panel.toJson()).toList(),
    'links': links.map((link) => link.toJson()).toList(),
    'drawings': drawings.map((d) => d.toJson()).toList(),
    'metadata': metadata,
  };

  factory BoardDocument.fromJson(Map<String, dynamic> json) {
    final rawPanels = json['panels'] as List? ?? const [];
    final rawLinks = json['links'] as List? ?? const [];
    final rawDrawings = json['drawings'] as List? ?? const [];
    return BoardDocument(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Board',
      viewport: BoardViewport.fromJson(
        Map<String, dynamic>.from(json['viewport'] as Map? ?? const {}),
      ),
      panels:
          rawPanels
              .map(
                (entry) => BoardPanelInstance.fromJson(
                  Map<String, dynamic>.from(entry as Map),
                ),
              )
              .toList(),
      links:
          rawLinks
              .map(
                (entry) => BoardPanelLink.fromJson(
                  Map<String, dynamic>.from(entry as Map),
                ),
              )
              .toList(),
      drawings:
          rawDrawings
              .map(
                (entry) => BoardDrawingElement.fromJson(
                  Map<String, dynamic>.from(entry as Map),
                ),
              )
              .toList(),
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    viewport,
    panels,
    links,
    drawings,
    metadata,
  ];
}
