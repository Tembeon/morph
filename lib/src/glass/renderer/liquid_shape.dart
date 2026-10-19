import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/renderer.dart';

/// Represents a shape that can be used by a [LiquidGlass] widget.
sealed class LiquidShape extends OutlinedBorder {
  const LiquidShape({super.side = BorderSide.none});

  @protected
  OutlinedBorder get _equivalentOutlinedBorder;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _equivalentOutlinedBorder.getInnerPath(
      rect,
      textDirection: textDirection,
    );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _equivalentOutlinedBorder.getOuterPath(
      rect,
      textDirection: textDirection,
    );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    _equivalentOutlinedBorder.paint(canvas, rect, textDirection: textDirection);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is LiquidShape &&
          other.side == side &&
          other._radius == _radius;

  @override
  int get hashCode => Object.hash(runtimeType, side, _radius);

  @override
  String toString() => _radius == null
      ? '${objectRuntimeType(this, 'LiquidShape')}($side)'
      : '${objectRuntimeType(this, 'LiquidShape')}($side, $_radius)';

  Object? get _radius => null;
}

/// Represents a squircle shape that can be used by a [LiquidGlass] widget.
///
/// Works like a [RoundedSuperellipseBorder] whose two top corners share
/// one radius and two bottom corners another: Flutter's continuous
/// rounded superellipse of those radii, the outline a sheet's glass and
/// its clip share (top 38, bottom 54 to 62).
class LiquidRoundedSuperellipse extends LiquidShape {
  /// Creates a squircle with corners of [borderRadius], or with the two
  /// bottom ones of [bottomRadius] when it is given.
  const LiquidRoundedSuperellipse({
    required double borderRadius,
    double? bottomRadius,
    super.side = BorderSide.none,
  }) : topRadius = borderRadius,
       bottomRadius = bottomRadius ?? borderRadius;

  /// The radius of the two top corners.
  final double topRadius;

  /// The radius of the two bottom corners.
  final double bottomRadius;

  /// Whether every corner has the same radius.
  bool get isUniform => topRadius == bottomRadius;

  /// The four corners, for Flutter's clips and paths of the same outline.
  BorderRadius get radii => BorderRadius.vertical(
    top: Radius.circular(topRadius),
    bottom: Radius.circular(bottomRadius),
  );

  @override
  OutlinedBorder get _equivalentOutlinedBorder =>
      RoundedSuperellipseBorder(borderRadius: radii, side: side);

  @override
  LiquidRoundedSuperellipse copyWith({
    BorderSide? side,
    double? borderRadius,
    double? bottomRadius,
  }) {
    return LiquidRoundedSuperellipse(
      side: side ?? this.side,
      borderRadius: borderRadius ?? topRadius,
      bottomRadius:
          bottomRadius ?? (borderRadius == null ? this.bottomRadius : null),
    );
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidRoundedSuperellipse(
      borderRadius: topRadius * t,
      bottomRadius: bottomRadius * t,
      side: side.scale(t),
    );
  }

  @override
  Object get _radius => isUniform ? topRadius : (topRadius, bottomRadius);
}

/// Represents an ellipse shape that can be used by a [LiquidGlass] widget.
///
/// Works like an [OvalBorder].
class LiquidOval extends LiquidShape {
  /// Creates a new [LiquidOval] with the given [side].
  const LiquidOval({super.side = BorderSide.none});

  @override
  OutlinedBorder get _equivalentOutlinedBorder => const OvalBorder();

  @override
  OutlinedBorder copyWith({BorderSide? side}) {
    return LiquidOval(side: side ?? this.side);
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidOval(side: side.scale(t));
  }
}

/// Represents a rounded rectangle shape that can be used by a [LiquidGlass]
/// widget.
///
/// Works like a [RoundedRectangleBorder].
class LiquidRoundedRectangle extends LiquidShape {
  /// Creates a new [LiquidRoundedRectangle] with the given [borderRadius].
  const LiquidRoundedRectangle({
    required this.borderRadius,
    super.side = BorderSide.none,
  });

  /// The radius of the rounded rectangle.
  ///
  /// This is the radius of the corners of the rounded rectangle.
  final double borderRadius;

  @override
  OutlinedBorder get _equivalentOutlinedBorder => RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
    side: side,
  );

  @override
  LiquidRoundedRectangle copyWith({BorderSide? side, double? borderRadius}) {
    return LiquidRoundedRectangle(
      side: side ?? this.side,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidRoundedRectangle(
      borderRadius: borderRadius * t,
      side: side.scale(t),
    );
  }

  @override
  double get _radius => borderRadius;
}
