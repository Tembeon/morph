import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

import '../integration_test/support/control_matrix.dart';

/// Every cell of the control matrix runs on the host: its control builds,
/// its actions find their targets and leave no presentation open, and a
/// control removed while its menu is still out lets the menu go.
void main() {
  setUpAll(() async {
    // No Impeller on the host: the renderer reports its fake fallback once.
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {};
    try {
      await MorphGlassRenderer.precache();
    } finally {
      FlutterError.onError = previous;
    }
  });

  testWidgets('every matrix cell runs and cleans up', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const GalleryApp(key: ValueKey('matrix'), home: MatrixStage()),
    );
    await tester.pump(const Duration(seconds: 1));
    final driver = _HostDriver(tester);
    final scenes = <String>[];
    await runControlMatrix(driver, (String scene) {
      scenes.add(scene);
      return true;
    });
    expect(driver.measured, scenes);
    expect(find.byType(MatrixStage), findsOneWidget);
    // Nothing presented is left over a cell: the next one sees the page.
    expect(MatrixStage.control.value, isNull);
  });

  // The device bench counts the date picker's saveLayers per frame
  // (tool/ios_reference/spec/date-picker.md): its glass is the only one
  // left, and the stage adds none after the empty cell's floor ticker.
  for (final tier in [MorphGlassTier.flat, MorphGlassTier.fake]) {
    testWidgets('the date picker open-close composites only its glass '
        'offscreen (${tier.name})', (WidgetTester tester) async {
      final initial = GalleryGlassSettings.initialTier;
      GalleryGlassSettings.initialTier = tier.name;
      addTearDown(() => GalleryGlassSettings.initialTier = initial);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const GalleryApp(key: ValueKey('matrix'), home: MatrixStage()),
      );
      await tester.pump(const Duration(seconds: 1));
      final frames = <Map<String, int>>[];
      final driver = _HostDriver(
        tester,
        onFrame: () {
          if (MatrixStage.control.value != null) {
            frames.add(_offscreen(tester));
          }
        },
      );
      await runControlMatrix(
        driver,
        (String scene) =>
            scene == 'm/empty/frames' || scene == 'm/date-picker/open-close',
      );
      expect(frames, isNotEmpty);
      final kinds = {for (final frame in frames) ...frame.keys};
      expect(
        kinds,
        tier == MorphGlassTier.flat ? isEmpty : {'backdrop'},
        reason: 'offscreen layers other than the overlay glass',
      );
      final most = frames.fold(
        0,
        (int a, Map<String, int> f) =>
            (f['backdrop'] ?? 0) > a ? f['backdrop']! : a,
      );
      expect(most, tier == MorphGlassTier.flat ? 0 : 1);
    });
  }
}

Map<String, int> _offscreen(WidgetTester tester) {
  final counts = <String, int>{};
  void walk(Layer layer) {
    final kind = switch (layer) {
      // ignore: invalid_use_of_visible_for_testing_member
      BackdropFilterLayer() when layer.engineLayer != null => 'backdrop',
      OpacityLayer(:final alpha?) when alpha > 0 && alpha < 255 => 'opacity',
      ImageFilterLayer() => 'image_filter',
      ColorFilterLayer() => 'color_filter',
      ShaderMaskLayer() => 'shader_mask',
      ClipRectLayer(clipBehavior: Clip.antiAliasWithSaveLayer) ||
      ClipRRectLayer(clipBehavior: Clip.antiAliasWithSaveLayer) ||
      ClipRSuperellipseLayer(clipBehavior: Clip.antiAliasWithSaveLayer) ||
      ClipPathLayer(clipBehavior: Clip.antiAliasWithSaveLayer) => 'clip',
      _ => null,
    };
    if (kind != null) counts[kind] = (counts[kind] ?? 0) + 1;
    if (layer is ContainerLayer) {
      for (
        var child = layer.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        walk(child);
      }
    }
  }

  // ignore: invalid_use_of_protected_member
  walk(tester.binding.renderViews.first.layer!);
  return counts;
}

class _HostDriver implements MatrixDriver {
  _HostDriver(this.tester, {this.onFrame});

  @override
  final WidgetTester tester;

  /// Called after every frame when set; frames are then pumped 16 ms
  /// apart.
  final VoidCallback? onFrame;

  final List<String> measured = [];
  int _pointer = 1;

  Future<void> _pump([Duration duration = Duration.zero]) async {
    final onFrame = this.onFrame;
    if (onFrame == null) return tester.pump(duration);
    const step = Duration(milliseconds: 16);
    var left = duration;
    do {
      final next = left > step ? step : left;
      await tester.pump(next);
      onFrame();
      left -= next;
    } while (left > Duration.zero);
  }

  @override
  Future<void> settle([int ms = 900]) => _pump(Duration(milliseconds: ms));

  @override
  Future<void> finger(
    Offset from,
    List<Offset> path, {
    Duration holdBefore = const Duration(milliseconds: 16),
  }) async {
    final gesture = await tester.createGesture(pointer: _pointer++);
    await gesture.down(from);
    await _pump(holdBefore);
    for (final p in path) {
      await gesture.moveTo(p);
      await _pump(const Duration(milliseconds: 8));
    }
    await gesture.up();
    await _pump();
  }

  @override
  Future<void> tap(Offset at) =>
      finger(at, const [], holdBefore: const Duration(milliseconds: 60));

  @override
  Future<void> measure(String name, Future<void> Function() body) async {
    measured.add(name);
    final routes = find.byType(ModalBarrier);
    final before = routes.evaluate().length;
    await body();
    expect(
      routes.evaluate().length,
      lessThanOrEqualTo(before),
      reason: '$name left a presentation open',
    );
  }
}
