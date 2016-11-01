// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'basic_types.dart';
import 'dart:ui' as ui show lerpDouble;

/// An offset that's expressed as a fraction of a Size.
///
/// FractionalOffset(1.0, 0.0) represents the top right of the Size,
/// FractionalOffset(0.0, 1.0) represents the bottom left of the Size,
class FractionalOffset {
  /// Creates a fractional offset.
  ///
  /// The [dx] and [dy] arguments must not be null.
  const FractionalOffset(this.dx, this.dy);

  /// The distance fraction in the horizontal direction.
  ///
  /// A value of 0.0 corresponds to the leftmost edge. A value of 1.0
  /// corresponds to the rightmost edge.
  final double dx;

  /// The distance fraction in the vertical direction.
  ///
  /// A value of 0.0 corresponds to the topmost edge. A value of 1.0
  /// corresponds to the bottommost edge.
  final double dy;

  /// The top left corner.
  static const FractionalOffset topLeft = const FractionalOffset(0.0, 0.0);

  /// The center point along the top edge.
  static const FractionalOffset topCenter = const FractionalOffset(0.5, 0.0);

  /// The top right corner.
  static const FractionalOffset topRight = const FractionalOffset(1.0, 0.0);

  /// The bottom left corner.
  static const FractionalOffset bottomLeft = const FractionalOffset(0.0, 1.0);

  /// The center point along the bottom edge.
  static const FractionalOffset bottomCenter = const FractionalOffset(0.5, 1.0);

  /// The bottom right corner.
  static const FractionalOffset bottomRight = const FractionalOffset(1.0, 1.0);

  /// The center point along the left edge.
  static const FractionalOffset centerLeft = const FractionalOffset(0.0, 0.5);

  /// The center point along the right edge.
  static const FractionalOffset centerRight = const FractionalOffset(1.0, 0.5);

  /// The center point, both horizontally and vertically.
  static const FractionalOffset center = const FractionalOffset(0.5, 0.5);

  /// Returns the negation of the given fractional offset.
  FractionalOffset operator -() {
    return new FractionalOffset(-dx, -dy);
  }

  /// Returns the difference between two fractional offsets.
  FractionalOffset operator -(FractionalOffset other) {
    return new FractionalOffset(dx - other.dx, dy - other.dy);
  }

  /// Returns the sum of two fractional offsets.
  FractionalOffset operator +(FractionalOffset other) {
    return new FractionalOffset(dx + other.dx, dy + other.dy);
  }

  /// Scales the fractional offset in each dimension by the given factor.
  FractionalOffset operator *(double other) {
    return new FractionalOffset(dx * other, dy * other);
  }

  /// Divides the fractional offset in each dimension by the given factor.
  FractionalOffset operator /(double other) {
    return new FractionalOffset(dx / other, dy / other);
  }

  /// Integer divides the fractional offset in each dimension by the given factor.
  FractionalOffset operator ~/(double other) {
    return new FractionalOffset((dx ~/ other).toDouble(), (dy ~/ other).toDouble());
  }

  /// Computes the remainder in each dimension by the given factor.
  FractionalOffset operator %(double other) {
    return new FractionalOffset(dx % other, dy % other);
  }

  /// Returns the offset that is this fraction in the direction of the given offset.
  Offset alongOffset(Offset other) {
    return new Offset(dx * other.dx, dy * other.dy);
  }

  /// Returns the offset that is this fraction within the given size.
  Offset alongSize(Size other) {
    return new Offset(dx * other.width, dy * other.height);
  }

  /// Returns the point that is this fraction within the given rect.
  Point withinRect(Rect rect) {
    return new Point(rect.left + dx * rect.width, rect.top + dy * rect.height);
  }

  /// Returns a rect of the given size, centered at this fraction of the given rect.
  ///
  /// For example, a 100×100 size inscribed on a 200×200 rect using
  /// [FractionalOffset.topLeft] would be the 100×100 rect at the top left of
  /// the 200×200 rect.
  Rect inscribe(Size size, Rect rect) {
    return new Rect.fromLTWH(
      rect.left + (rect.width - size.width) * dx,
      rect.top + (rect.height - size.height) * dy,
      size.width,
      size.height
    );
  }

  @override
  bool operator ==(dynamic other) {
    if (other is! FractionalOffset)
      return false;
    final FractionalOffset typedOther = other;
    return dx == typedOther.dx &&
           dy == typedOther.dy;
  }

  @override
  int get hashCode => hashValues(dx, dy);

  /// Linearly interpolate between two EdgeInsets.
  ///
  /// If either is null, this function interpolates from [FractionalOffset.topLeft].
  // TODO(abarth): Consider interpolating from [FractionalOffset.center] instead
  // to remove upper-left bias.
  static FractionalOffset lerp(FractionalOffset a, FractionalOffset b, double t) {
    if (a == null && b == null)
      return null;
    if (a == null)
      return new FractionalOffset(b.dx * t, b.dy * t);
    if (b == null)
      return new FractionalOffset(b.dx * (1.0 - t), b.dy * (1.0 - t));
    return new FractionalOffset(ui.lerpDouble(a.dx, b.dx, t), ui.lerpDouble(a.dy, b.dy, t));
  }

  @override
  String toString() => '$runtimeType($dx, $dy)';
}
