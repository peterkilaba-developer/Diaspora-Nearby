import 'dart:ui';

// lib/helper/helper.dart
// Platform-agnostic canvas shims (non-web).
// On non‑web platforms, these methods intentionally do nothing.
// Purpose: allow signaturepad.dart to make shared calls without importing
// web‑only Canvas 2D APIs.

/// Set fill style (color/gradient/pattern). No-op on non-web platforms.
/// fillColor expects an 'r,g,b,a' string (same as web helper).
void fillStyle(dynamic context2D, String fillColor) {}

/// Set stroke style (color/gradient/pattern). No-op on non-web platforms.
/// strokeColor expects an 'r,g,b,a' string (same as web helper).
void strokeStyle(dynamic context2D, String strokeColor) {}

/// Fill a rectangle that covers the given size. No-op on non-web platforms.
void fillRect(dynamic context2D, Size size) {}

/// Fill the current subpath(s). No-op on non-web platforms.
void fill(dynamic context2D) {}

/// Set the line cap style (e.g., 'round', 'butt', 'square'). No-op here.
void lineCap(dynamic context2D, String lineCap) {}

/// Set the current line width. No-op on non-web platforms.
void lineWidth(dynamic context2D, double lineWidth) {}

/// Stroke the current subpath(s). No-op on non-web platforms.
void stroke(dynamic context2D) {}

/// Begin a new path. No-op on non-web platforms.
void beginPath(dynamic context2D) {}

/// Add an arc to the current path. No-op on non-web platforms.
void drawContext2DArc(
  dynamic context2D,
  double x,
  double y,
  double radius,
  double startAngle,
  double endAngle,
  bool counterclockwise,
) {}

/// Add a straight line to the current path. No-op on non-web platforms.
void drawContext2DLine(
  dynamic context2D,
  double x,
  double y,
  double x1,
  double y1,
) {}
