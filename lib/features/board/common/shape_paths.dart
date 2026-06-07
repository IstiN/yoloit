import 'package:flutter/material.dart';

/// Diamond path inside [rect].
Path diamondPath(Rect rect) => Path()
  ..moveTo(rect.center.dx, rect.top)
  ..lineTo(rect.right, rect.center.dy)
  ..lineTo(rect.center.dx, rect.bottom)
  ..lineTo(rect.left, rect.center.dy)
  ..close();

/// Triangle path inside [rect].
Path trianglePath(Rect rect) => Path()
  ..moveTo(rect.center.dx, rect.top)
  ..lineTo(rect.right, rect.bottom)
  ..lineTo(rect.left, rect.bottom)
  ..close();
