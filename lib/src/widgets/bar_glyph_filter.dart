import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/glyph_scale.dart';

/// A bar foreground stack that shares filters between compatible neighbors.
@internal
class MorphBarGlyphStack extends MultiChildRenderObjectWidget {
  /// Creates an unclipped, positioned foreground stack.
  const MorphBarGlyphStack({required super.children, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => _GlyphStack(
    Directionality.of(context),
    MediaQuery.devicePixelRatioOf(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    final stack = renderObject as _GlyphStack;
    stack.textDirection = Directionality.of(context);
    stack.pixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

/// A glyph's filter, transform and opacity with a stable layout box.
@internal
class MorphBarGlyphFilter extends SingleChildRenderObjectWidget {
  /// Creates an independently paintable glyph, eligible for stack batching.
  const MorphBarGlyphFilter({
    required this.sigma,
    required this.scale,
    required this.opacity,
    this.allowBatch = true,
    required super.child,
    super.key,
  });

  /// Local Gaussian sigma; zero omits filtering.
  final double sigma;

  /// Uniform scale about the item's center.
  final double scale;

  /// Foreground opacity.
  final double opacity;

  /// Whether the source can share a filter with other glyphs.
  final bool allowBatch;

  @override
  RenderObject createRenderObject(BuildContext context) => _GlyphFilter(
    sigma,
    scale,
    ui.Color.getAlphaFromOpacity(opacity.clamp(0, 1)),
    allowBatch,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _GlyphFilter).update(
      sigma,
      scale,
      ui.Color.getAlphaFromOpacity(opacity.clamp(0, 1)),
      allowBatch,
    );
  }
}

Matrix4 _scaleAt(double scale, Offset center) {
  final matrix = Matrix4.diagonal3Values(scale, scale, 1);
  matrix.setTranslationRaw(center.dx * (1 - scale), center.dy * (1 - scale), 0);
  return matrix;
}

class _GlyphFilter extends RenderProxyBox {
  _GlyphFilter(this.sigma, this.scale, this.alpha, this.allowBatch);

  double sigma;
  double scale;
  int alpha;
  bool allowBatch;
  bool sourceOnly = false;
  final LayerHandle<ImageFilterLayer> _blur = LayerHandle<ImageFilterLayer>();
  final LayerHandle<TransformLayer> _transform = LayerHandle<TransformLayer>();
  final LayerHandle<OpacityLayer> _opacity = LayerHandle<OpacityLayer>();

  void update(double blur, double zoom, int opacity, bool batch) {
    if (sigma == blur &&
        scale == zoom &&
        alpha == opacity &&
        allowBatch == batch) {
      return;
    }
    sigma = blur;
    scale = zoom;
    alpha = opacity;
    allowBatch = batch;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  bool get eligible =>
      allowBatch &&
      sigma * scale >= MorphGlyphRaster.minBlur &&
      scale > 0 &&
      alpha > 0;

  @override
  bool get alwaysNeedsCompositing =>
      child != null && (sigma > 0 || (alpha > 0 && alpha < 255));

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_scaleAt(scale, size.center(Offset.zero)));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintTransform(
        transform: _scaleAt(scale, size.center(Offset.zero)),
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );

  void source(PaintingContext context, Offset offset) {
    if (child != null) context.paintChild(child!, offset);
  }

  void filtered(PaintingContext context, Offset offset) {
    if (sigma <= 0) {
      _blur.layer = null;
      source(context, offset);
      return;
    }
    final layer = _blur.layer ?? ImageFilterLayer();
    layer.imageFilter = ui.ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: TileMode.decal,
    );
    layer.offset = offset;
    _blur.layer = layer;
    context.pushLayer(layer, source, offset);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (sourceOnly) {
      source(context, offset);
      return;
    }
    if (alpha == 0 || scale == 0 || child == null) return;
    void transformed(PaintingContext context, Offset offset) {
      _transform.layer = context.pushTransform(
        needsCompositing,
        offset,
        _scaleAt(scale, size.center(Offset.zero)),
        filtered,
        oldLayer: _transform.layer,
      );
    }

    if (alpha == 255) {
      _opacity.layer = null;
      transformed(context, offset);
    } else {
      _opacity.layer = context.pushOpacity(
        offset,
        alpha,
        transformed,
        oldLayer: _opacity.layer,
      );
    }
  }

  @override
  void dispose() {
    _blur.layer = null;
    _transform.layer = null;
    _opacity.layer = null;
    super.dispose();
  }
}

class _CohortLayers {
  final LayerHandle<ImageFilterLayer> blur = LayerHandle<ImageFilterLayer>();
  final LayerHandle<TransformLayer> transform = LayerHandle<TransformLayer>();
  final LayerHandle<OpacityLayer> opacity = LayerHandle<OpacityLayer>();

  void dispose() {
    blur.layer = null;
    transform.layer = null;
    opacity.layer = null;
  }
}

class _GlyphStack extends RenderStack {
  _GlyphStack(TextDirection direction, this._pixelRatio)
    : super(textDirection: direction, clipBehavior: Clip.none);

  double _pixelRatio;
  final List<_CohortLayers> _layers = [];

  double get pixelRatio => _pixelRatio;

  set pixelRatio(double value) {
    if (value == _pixelRatio) return;
    _pixelRatio = value;
    markNeedsPaint();
  }

  _GlyphFilter? _glyph(RenderBox child) {
    RenderBox? current = child;
    while (current is RenderProxyBox) {
      if (current is _GlyphFilter) return current;
      current = current.child;
    }
    return null;
  }

  Rect _coverage(RenderBox child, _GlyphFilter glyph) {
    final offset = (child.parentData! as StackParentData).offset;
    return Rect.fromCenter(
      center: offset + child.size.center(Offset.zero),
      width: child.size.width * glyph.scale,
      height: child.size.height * glyph.scale,
    ).inflate(glyph.sigma * glyph.scale * 4 + 1 / _pixelRatio);
  }

  @override
  void paintStack(PaintingContext context, Offset offset) {
    var used = 0;
    var child = firstChild;
    while (child != null) {
      final glyph = _glyph(child);
      final members = <(RenderBox, _GlyphFilter)>[];
      final coverage = <Rect>[];
      var next = childAfter(child);
      if (glyph != null && glyph.eligible) {
        members.add((child, glyph));
        coverage.add(_coverage(child, glyph));
        var union = coverage.first;
        var area = union.width * union.height;
        while (next != null) {
          final candidate = _glyph(next);
          if (candidate == null ||
              !candidate.eligible ||
              candidate.sigma != glyph.sigma ||
              candidate.scale != glyph.scale ||
              candidate.alpha != glyph.alpha) {
            break;
          }
          final rect = _coverage(next, candidate);
          if (coverage.any((bounds) => bounds.overlaps(rect))) break;
          final expanded = union.expandToInclude(rect);
          final expandedArea = area + rect.width * rect.height;
          if (expanded.width * expanded.height > expandedArea * 2) break;
          members.add((next, candidate));
          coverage.add(rect);
          union = expanded;
          area = expandedArea;
          next = childAfter(next);
        }
      }
      if (members.length < 2) {
        context.paintChild(
          child,
          offset + (child.parentData! as StackParentData).offset,
        );
      } else {
        if (used == _layers.length) _layers.add(_CohortLayers());
        final layers = _layers[used++];
        final anchor =
            (child.parentData! as StackParentData).offset +
            child.size.center(Offset.zero);
        void source(PaintingContext context, Offset origin) {
          for (final (box, sprite) in members) {
            final parent = (box.parentData! as StackParentData).offset;
            final center = box.size.center(Offset.zero);
            final position = anchor + (parent + center - anchor) / glyph!.scale;
            sprite.sourceOnly = true;
            try {
              context.paintChild(box, origin + position - center);
            } finally {
              sprite.sourceOnly = false;
            }
          }
        }

        void filtered(PaintingContext context, Offset origin) {
          final blur = layers.blur.layer ?? ImageFilterLayer();
          blur.offset = origin;
          blur.imageFilter = ui.ImageFilter.blur(
            sigmaX: glyph!.sigma,
            sigmaY: glyph.sigma,
            tileMode: TileMode.decal,
          );
          layers.blur.layer = blur;
          context.pushLayer(blur, source, origin);
        }

        void transformed(PaintingContext context, Offset origin) {
          layers.transform.layer = context.pushTransform(
            true,
            origin,
            _scaleAt(glyph!.scale, anchor),
            filtered,
            oldLayer: layers.transform.layer,
          );
        }

        if (glyph!.alpha == 255) {
          layers.opacity.layer = null;
          transformed(context, offset);
        } else {
          layers.opacity.layer = context.pushOpacity(
            offset,
            glyph.alpha,
            transformed,
            oldLayer: layers.opacity.layer,
          );
        }
      }
      child = next;
    }
    while (_layers.length > used) {
      _layers.removeLast().dispose();
    }
  }

  @override
  void dispose() {
    for (final layers in _layers) {
      layers.dispose();
    }
    _layers.clear();
    super.dispose();
  }
}
