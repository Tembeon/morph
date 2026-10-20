import 'dart:typed_data';
import 'dart:ui';

import 'package:meta/meta.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';

/// The shapes of one geometry frame packed as the geometry pass and the
/// analytic final shader read them, in device pixels of the matte: three
/// vec4 of primitive, inverse basis and center per shape, three of rounded
/// superellipse parameters, one of bounds and a cull factor.
///
/// A matte frame hands the shape lists to the geometry pass; an analytic
/// frame writes them, with the optics and the fused boxes, into the final
/// shader's uniforms. A fused body's boxes and their tints reach the final
/// shader in both frames.
@internal
final class GlassShapePack {
  /// Primitive, inverse basis, center, distance scale and group marker:
  /// 12 floats per shape.
  final List<double> shapeData = [];

  /// The rounded superellipse parameters: 12 floats per shape, of its top
  /// half for a pair (RawShapeType.squirclePair).
  final List<double> rseData = [];

  /// The bottom half's parameters of a pair, 12 floats per shape, zeros
  /// for every other shape: the shaders read them from the second half of
  /// uRseData, at MAX_SHAPES * 3 + index * 3.
  final List<double> rseLowerData = [];

  /// The pairs among the shapes; the shaders read [rseLowerData] only for
  /// them, so a frame without one leaves it unwritten.
  int pairCount = 0;

  /// The bottom half of a shape that is no pair.
  static const List<double> noLowerHalf = <double>[
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
  ];

  /// The culling boxes: 4 floats per shape.
  final List<double> boundsData = [];

  /// The lower bound of each shape's distance from its box distance: one
  /// float per shape.
  final List<double> cullData = [];

  /// The shapes in the lists.
  int shapeCount = 0;

  /// The geometry pass's refraction height of an analytic frame.
  double refractionHeight = 0;

  /// The geometry pass's refraction amount of an analytic frame.
  double refractionAmount = 1e-3;

  /// Whether an analytic frame's refraction fits the shape.
  bool fitsShape = false;

  /// The antialiasing reach past the contour of an analytic frame.
  double contourExtent = 0.5;

  /// The narrowest merge width of an analytic frame in device pixels
  /// (the merge law's narrowest width at the layer's pixel ratio).
  double mergeMinWidth = 0;

  /// Whether an analytic frame skips the distance solve deep inside a
  /// shape.
  bool flatFace = true;

  /// The tints for a tint variant, 4 floats each: a fused body's per box,
  /// in box order, separate shapes' per shape; empty otherwise.
  final List<double> tints = [];

  /// Whether a matte frame of a fused body takes its tints from its boxes
  /// ([tints]) instead of a material map.
  bool boxTints = false;

  /// A fused body's boxes, 8 floats per box (center, half extents, clamped
  /// radius, 3 unused).
  final Float64List boxes = Float64List(GlassBoxField.maxBoxes * 8);

  /// The fused boxes; 0 for separate shapes.
  int boxCount = 0;

  /// The fused body's merge spacing in device pixels.
  double spacing = 0;

  /// Whether the shapes form a fused body of merged boxes.
  bool get fused => boxCount > 0;

  /// Empties the shape lists before a new frame packs its shapes.
  void clear() {
    shapeData.clear();
    rseData.clear();
    rseLowerData.clear();
    pairCount = 0;
    boundsData.clear();
    cullData.clear();
  }

  /// Moves the shapes and boxes by [delta] device pixels, as a uniformly
  /// translated matte moves its bounds.
  void translate(Offset delta) {
    for (var i = 0; i < shapeCount; i++) {
      shapeData[i * 12 + 8] += delta.dx;
      shapeData[i * 12 + 9] += delta.dy;
      boundsData[i * 4] += delta.dx;
      boundsData[i * 4 + 1] += delta.dy;
      boundsData[i * 4 + 2] += delta.dx;
      boundsData[i * 4 + 3] += delta.dy;
    }
    for (var i = 0; i < boxCount * 8; i += 8) {
      boxes[i] += delta.dx;
      boxes[i + 1] += delta.dy;
    }
  }
}
