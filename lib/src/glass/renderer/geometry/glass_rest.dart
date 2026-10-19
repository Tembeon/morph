import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer.dart';
import 'package:morph/src/glass/renderer/pass/final_pass.dart';
import 'package:morph/src/glass/renderer/pass/final_pass_layout.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

/// When a liquid layer with analytic geometry shades analytically.
@internal
enum AnalyticGeometryMode {
  /// Every frame it can.
  always,

  /// Only frames whose geometry changed: at rest it encodes a matte once
  /// and shades from it until the geometry changes again.
  changes,
}

/// The switches of analytic geometry, one set for every liquid layer.
@internal
abstract final class GlassGeometryFlags {
  static final ValueNotifier<int> _invalidations = ValueNotifier(0);
  static final ValueNotifier<int> _changes = ValueNotifier(0);

  /// Notifies when a switch changes how layers encode their geometry: an
  /// attached layer that follows it draws a new geometry frame. Only a
  /// debug override or a build with analytic geometry ever notifies.
  static Listenable get invalidations => _invalidations;

  static void _invalidate() => _invalidations.value++;

  static bool? _debugAnalyticGeometry;

  /// Overrides [ShaderKeys.analyticGeometry] for every layer when not null,
  /// for an A/B of the analytic and the matte geometry. Setting it asks
  /// every attached layer for a new geometry frame.
  @visibleForTesting
  static bool? get debugAnalyticGeometry => _debugAnalyticGeometry;
  @visibleForTesting
  static set debugAnalyticGeometry(bool? value) {
    if (_debugAnalyticGeometry == value) return;
    _debugAnalyticGeometry = value;
    if (analyticGeometryEnabled) {
      unawaited(GlassFinalPass.precacheAnalyticShaders());
    }
    _invalidate();
    _changes.value++;
  }

  /// Notifies when [debugAnalyticGeometry] changes, so whatever chose its
  /// glass by [analyticGeometryEnabled] chooses again.
  static Listenable get analyticGeometryChanges => _changes;

  /// Whether liquid layers evaluate their geometry in the final shader:
  /// [debugAnalyticGeometry], else [ShaderKeys.analyticGeometry].
  ///
  /// A frame is analytic when it has at most
  /// [FinalPassLayout.analyticMaxShapes] separate shapes, or a
  /// [GlassBoxField] of at most [GlassBoxField.maxBoxes] merged boxes, and
  /// one appearance or appearances that differ only by tint; every other
  /// frame renders a matte. Separate shapes draw the same shading as the
  /// matte path, only the matte's quantization and nearest sampling gone;
  /// merged boxes follow the container's merge law exactly, where the
  /// sampled field approximates it on a 4 pt grid. Its culling rect and
  /// the bevel shadow's size response (written as 0, so inert today) read
  /// the geometry bounds rounded out to device pixels, not a texture size
  /// bucket. Shapes are evaluated where they are, without the matte's
  /// raster-phase shifts.
  static bool get analyticGeometryEnabled =>
      _debugAnalyticGeometry ?? ShaderKeys.analyticGeometry;

  static AnalyticGeometryMode? _debugAnalyticMode;

  /// Overrides [ShaderKeys.analyticMode] for every layer when not null.
  /// Setting it asks every attached layer for a new geometry frame.
  @visibleForTesting
  static AnalyticGeometryMode? get debugAnalyticMode => _debugAnalyticMode;
  @visibleForTesting
  static set debugAnalyticMode(AnalyticGeometryMode? value) {
    if (_debugAnalyticMode == value) return;
    _debugAnalyticMode = value;
    _invalidate();
  }

  /// When analytic geometry shades: [debugAnalyticMode], else
  /// [ShaderKeys.analyticMode].
  static AnalyticGeometryMode get analyticMode =>
      _debugAnalyticMode ??
      (ShaderKeys.analyticMode == 'always'
          ? AnalyticGeometryMode.always
          : AnalyticGeometryMode.changes);

  static bool? _debugAnalyticCapsule;

  /// Overrides [ShaderKeys.analyticCapsule] for every layer when not null.
  @visibleForTesting
  static bool? get debugAnalyticCapsule => _debugAnalyticCapsule;
  @visibleForTesting
  static set debugAnalyticCapsule(bool? value) {
    if (_debugAnalyticCapsule == value) return;
    _debugAnalyticCapsule = value;
    _invalidate();
  }

  /// Whether analytic frames shade full-radius rounded superellipses as
  /// stadiums: [debugAnalyticCapsule], else [ShaderKeys.analyticCapsule].
  static bool get analyticCapsuleEnabled =>
      _debugAnalyticCapsule ?? ShaderKeys.analyticCapsule;

  static bool _debugAnalyticFlatFace = true;

  /// Whether analytic frames of separate shapes skip a rounded
  /// superellipse's distance solve where a pixel lies provably deeper than
  /// any bevel, glint, border or bevel shadow reaches; the pixels are the
  /// same either way. Setting it asks every attached layer for a new
  /// geometry frame.
  @visibleForTesting
  static bool get debugAnalyticFlatFace => _debugAnalyticFlatFace;
  @visibleForTesting
  static set debugAnalyticFlatFace(bool value) {
    if (_debugAnalyticFlatFace == value) return;
    _debugAnalyticFlatFace = value;
    _invalidate();
  }

  /// Whether analytic frames skip the distance solve deep inside a shape:
  /// [debugAnalyticFlatFace].
  static bool get analyticFlatFace => _debugAnalyticFlatFace;
}

/// What a [GlassRestWatch] reads from the layer it watches and asks of it.
@internal
abstract interface class GlassRestHost {
  /// Whether the layer is attached.
  bool get attached;

  /// Whether the layer's current geometry frame is analytic.
  bool get analyticFrame;

  /// Whether the layer holds a matte now.
  bool get holdsMatte;

  /// The renderer that holds the layer's matte textures.
  FlutterGpuGeometryRenderer? get gpuGeometryRenderer;

  /// The geometry frames the layer rendered as a matte.
  int get matteBuilds;

  /// Asks the layer for a new geometry frame.
  void requestGeometryFrame();
}

/// When a liquid layer with analytic geometry rests on a matte, and when
/// it hands its matte textures back.
///
/// In [AnalyticGeometryMode.changes] a layer shades analytically on frames
/// whose geometry changed (its encoded inputs, up to a uniform translation,
/// plus [inputsChanged]); after [restFrames] frames without a change - or
/// at once when no frame is coming - it asks for one matte frame and rests
/// on it until the geometry changes, which is analytic in the same frame.
/// The matte textures go back after [releaseFrames] analytic frames in a
/// row; in [AnalyticGeometryMode.always], after two analytic frames with no
/// matte between them.
@internal
final class GlassRestWatch {
  /// Watches [_host].
  GlassRestWatch(this._host);

  final GlassRestHost _host;

  /// The consecutive frames a layer's geometry must stay unchanged before,
  /// in [AnalyticGeometryMode.changes], it encodes a matte to rest on.
  static const int restFrames = 2;

  /// The analytic geometry frames in a row after which, in
  /// [AnalyticGeometryMode.changes], a layer hands its matte textures back.
  static const int releaseFrames = 120;

  /// The times layers handed their matte textures back, in debug builds.
  @visibleForTesting
  static int debugMatteReleases = 0;

  // Whether the geometry inputs a matte does not track by its own revision
  // changed since the last geometry frame: the field, the optics settings,
  // the pixel ratio, mixed appearances.
  bool _inputsChanged = true;
  // Geometry changes seen, for the rest watch.
  int _changes = 0;
  // Whether the layer rests on a matte, and whether its next unchanged
  // geometry frame starts resting.
  bool _resting = false;
  bool _restRequested = false;
  bool _watched = false;
  int _analyticSinceMatte = 0;
  bool _releaseScheduled = false;

  /// Whether the layer rests on a matte in [AnalyticGeometryMode.changes].
  bool get resting => _resting;

  /// Notes a change of a geometry input a matte does not track by its own
  /// revision: the field, the optics settings, the pixel ratio, mixed
  /// appearances.
  void inputsChanged() => _inputsChanged = true;

  /// Notes before a geometry frame whether its geometry is [unchanged]
  /// since the last one, up to a uniform translation.
  void noteFrame({required bool unchanged}) {
    final changed = !unchanged || _inputsChanged;
    _inputsChanged = false;
    if (GlassGeometryFlags.analyticMode != AnalyticGeometryMode.changes) {
      _resting = false;
      _restRequested = false;
      return;
    }
    if (changed) {
      _changes++;
      _resting = false;
      _restRequested = false;
    } else if (_restRequested) {
      _restRequested = false;
      _resting = true;
    }
  }

  /// After a geometry frame: in [AnalyticGeometryMode.changes] an analytic
  /// frame watches for rest and hands the matte back only after a long run;
  /// otherwise the matte goes back after two analytic frames.
  void afterFrame() {
    final analytic = _host.analyticFrame;
    if (GlassGeometryFlags.analyticMode == AnalyticGeometryMode.changes) {
      if (!analytic) {
        _analyticSinceMatte = 0;
        return;
      }
      _watch();
      if (++_analyticSinceMatte == releaseFrames) {
        final renderer = _host.gpuGeometryRenderer;
        if (renderer != null && renderer.holdsOutput && !_host.holdsMatte) {
          renderer.releaseOutput();
          assert(() {
            debugMatteReleases++;
            return true;
          }());
        }
      }
      return;
    }
    if (analytic) _scheduleRelease();
  }

  // Once the geometry stayed unchanged for [restFrames] frames - or no
  // frame is coming, so it cannot change - asks for one matte frame to rest
  // on.
  void _watch() {
    if (_watched) return;
    _watched = true;
    var start = _changes;
    // The frame that changed the geometry does not count.
    var still = -1;
    final scheduler = SchedulerBinding.instance;
    void check(Duration _) {
      if (!_host.attached || !_host.analyticFrame) {
        _watched = false;
        return;
      }
      if (_changes != start) {
        start = _changes;
        still = 0;
      } else {
        still++;
      }
      if (still >= restFrames || !scheduler.hasScheduledFrame) {
        _watched = false;
        _restRequested = true;
        _host.requestGeometryFrame();
        return;
      }
      scheduler.addPostFrameCallback(check);
    }

    scheduler.addPostFrameCallback(check);
  }

  // Hands the renderer's matte and material textures back once the layer
  // has drawn analytic frames for two frames with no matte between them;
  // the next matte frame takes textures again.
  void _scheduleRelease() {
    if (_releaseScheduled) return;
    final renderer = _host.gpuGeometryRenderer;
    if (renderer == null || !renderer.holdsOutput) return;
    _releaseScheduled = true;
    final builds = _host.matteBuilds;
    final scheduler = SchedulerBinding.instance;
    scheduler.addPostFrameCallback((_) {
      if (!_host.attached ||
          !_host.analyticFrame ||
          _host.matteBuilds != builds) {
        _releaseScheduled = false;
        return;
      }
      scheduler.addPostFrameCallback((_) {
        _releaseScheduled = false;
        final renderer = _host.gpuGeometryRenderer;
        if (_host.attached &&
            _host.analyticFrame &&
            _host.matteBuilds == builds &&
            renderer != null &&
            !_host.holdsMatte) {
          renderer.releaseOutput();
          assert(() {
            debugMatteReleases++;
            return true;
          }());
        }
      });
      scheduler.scheduleFrame();
    });
  }
}
