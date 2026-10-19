import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/glass_painter.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/widgets/zoom_source.dart';

/// A sheet is one outline in every state and transition: the glass its
/// painter is handed and the clip round the sheet are the same continuous
/// rounded rect on every frame (the renderer shades a top and a bottom
/// radius exactly, glass_shape_pair_test), and while it zooms out of a
/// source the container's clip is the one outline its glass fills. The
/// bottom corners follow the device's clip layer: 54 floating, 54 to 62 as
/// it docks, 0 at the docked rest, from 0 back to 54 as it undocks.
void main() {
  testWidgets('programmatic detent changes', (WidgetTester tester) async {
    final sheet = await _present(tester);
    expect(sheet.clip(tester).blRadiusX, 54);
    expect(sheet.clip(tester).tlRadiusX, 38);

    sheet.animateTo(tester, MorphSheetDetent.large);
    final docking = await sheet.frames(tester, 40);
    for (var i = 1; i < docking.length; i++) {
      if (docking[i].blRadiusX == 0) break;
      expect(
        docking[i].blRadiusX,
        greaterThanOrEqualTo(docking[i - 1].blRadiusX),
      );
    }
    expect(docking.map((RRect r) => r.blRadiusX), contains(closeTo(62, 0.6)));
    expect(sheet.clip(tester).blRadiusX, 0);
    expect(sheet.clip(tester).tlRadiusX, 38);

    sheet.animateTo(tester, MorphSheetDetent.medium);
    final undocking = await sheet.frames(tester, 40);
    expect(undocking[1].blRadiusX, lessThan(12));
    for (var i = 1; i < undocking.length; i++) {
      expect(
        undocking[i].blRadiusX,
        greaterThanOrEqualTo(undocking[i - 1].blRadiusX),
      );
    }
    expect(sheet.clip(tester).blRadiusX, closeTo(54, 1e-6));
    expect(sheet.compared, greaterThan(40));
  });

  testWidgets('an interrupted change runs on from where it was', (
    WidgetTester tester,
  ) async {
    final sheet = await _present(tester);
    sheet.animateTo(tester, MorphSheetDetent.large);
    final out = await sheet.frames(tester, 6);
    sheet.animateTo(tester, MorphSheetDetent.medium);
    final back = await sheet.frames(tester, 40);
    final radii = [...out, ...back].map((RRect r) => r.blRadiusX).toList();
    for (var i = 1; i < radii.length; i++) {
      expect((radii[i] - radii[i - 1]).abs(), lessThan(3), reason: 'frame $i');
    }
    expect(radii.last, closeTo(54, 1e-6));
  });

  testWidgets('a dragged change', (WidgetTester tester) async {
    final sheet = await _present(tester);
    final gesture = await tester.startGesture(const Offset(201, 440));
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(0, -12));
      await sheet.frames(tester, 1);
    }
    final held = sheet.clip(tester).blRadiusX;
    expect(held, greaterThan(54));
    expect(held, lessThanOrEqualTo(62));
    await gesture.up();
    await sheet.frames(tester, 60);
    expect(sheet.clip(tester).blRadiusX, 0);
    expect(sheet.compared, greaterThan(30));
  });

  testWidgets('a pull of a sheet that cannot be dismissed', (
    WidgetTester tester,
  ) async {
    final sheet = await _present(tester, dismissible: false);
    final gesture = await tester.startGesture(const Offset(201, 440));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await sheet.frames(tester, 1);
      expect(sheet.clip(tester).blRadiusX, closeTo(54, 1e-6));
    }
    expect(tester.getRect(find.byKey(_content)).top, greaterThan(430));
    await gesture.up();
    await sheet.frames(tester, 60);
    expect(tester.getRect(find.byKey(_content)).top, closeTo(415, 1));
  });

  testWidgets('the keyboard rising and falling during a drag', (
    WidgetTester tester,
  ) async {
    final sheet = await _present(tester);
    final gesture = await tester.startGesture(const Offset(201, 440));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await sheet.frames(tester, 1);
    }
    tester.view.viewInsets = const FakeViewPadding(bottom: 328 * 3);
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, -4));
      await sheet.frames(tester, 1);
    }
    tester.view.resetViewInsets();
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, 4));
      await sheet.frames(tester, 1);
    }
    await gesture.up();
    await sheet.frames(tester, 60);
    expect(tester.takeException(), isNull);
    expect(sheet.compared, greaterThan(20));
  });

  testWidgets('rotation and size changes', (WidgetTester tester) async {
    final sheet = await _present(tester);
    tester.view.physicalSize = const Size(874, 402) * 3;
    tester.view.padding = const FakeViewPadding(left: 62 * 3, right: 62 * 3);
    await sheet.frames(tester, 40);
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    await sheet.frames(tester, 40);
    expect(sheet.clip(tester).blRadiusX, closeTo(54, 1e-6));
    expect(tester.getRect(find.byKey(_content)).top, closeTo(415, 1));
    expect(sheet.compared, greaterThan(60));
  });

  testWidgets('Reduce Motion', (WidgetTester tester) async {
    final sheet = await _present(tester, disableAnimations: true);
    sheet.animateTo(tester, MorphSheetDetent.large);
    await sheet.frames(tester, 40);
    expect(sheet.clip(tester).blRadiusX, 0);
    expect(sheet.compared, greaterThan(40));
  });

  testWidgets('a sheet presented from a sheet', (WidgetTester tester) async {
    final sheet = await _present(tester);
    unawaited(
      showMorphSheet<void>(
        tester.element(find.byKey(_content)),
        detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
        builder: (BuildContext context) => const SizedBox.expand(key: _nested),
      ),
    );
    await sheet.frames(tester, 60, key: _nested);
    MorphSheet.of(
      tester.element(find.byKey(_nested)),
    ).animateTo(MorphSheetDetent.large);
    await sheet.frames(tester, 60, key: _nested);
    expect(sheet.clip(tester, key: _nested).blRadiusX, 0);
    expect(sheet.clip(tester).blRadiusX, closeTo(54, 1e-6));
  });

  testWidgets('a zoom out of a source and back is one outline', (
    WidgetTester tester,
  ) async {
    final link = MorphSourceLink();
    final sheet = await _present(tester, from: link);
    // _present pumped the whole opening; zooms again with a close.
    expect(sheet.zoomFrames, greaterThan(10));
    expect(sheet.clip(tester).blRadiusX, closeTo(54, 1e-6));
    Navigator.of(tester.element(find.byKey(_content))).pop();
    await sheet.frames(tester, 80);
    expect(find.byKey(_content), findsNothing);
    expect(sheet.zoomFrames, greaterThan(30));
    expect(sheet.zoomCompared, greaterThan(30));
  });
}

const _content = ValueKey<String>('content');
const _nested = ValueKey<String>('nested');
const _source = ValueKey<String>('source');

class _Recorder extends MorphGlassPainter {
  final List<RRect> shapes = [];

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) {
    if (surface.kind == MorphGlassKind.menu) shapes.add(surface.shape);
    return buildFill(context, surface);
  }
}

class _Sheet {
  _Sheet(this.recorder);

  final _Recorder recorder;
  int compared = 0;
  int zoomFrames = 0;
  int zoomCompared = 0;

  RRect clip(WidgetTester tester, {Key key = _content}) => tester
      .renderObjectList<RenderMorphLiveBox>(
        find.ancestor(of: find.byKey(key), matching: find.byType(MorphLiveBox)),
      )
      .first
      .clipOf!()!;

  void animateTo(WidgetTester tester, MorphSheetDetent detent) =>
      MorphSheet.of(tester.element(find.byKey(_content))).animateTo(detent);

  /// Pumps [count] frames and checks each: the glass the painter drew is
  /// the clip's outline, or, while a zoom carries the sheet, the
  /// container's. Returns the clip of every frame the sheet had one.
  Future<List<RRect>> frames(
    WidgetTester tester,
    int count, {
    Key key = _content,
  }) async {
    final clips = <RRect>[];
    for (var i = 0; i < count; i++) {
      recorder.shapes.clear();
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byKey(key).evaluate().isEmpty) continue;
      final zoom = <RenderClipRSuperellipse>[];
      for (
        RenderObject? node = tester.renderObject(find.byKey(key));
        node != null;
        node = node.parent
      ) {
        if (node is RenderClipRSuperellipse &&
            node.clipper is MorphZoomContinuousClipper) {
          zoom.add(node);
        }
      }
      if (zoom.isNotEmpty) {
        expect(zoom, hasLength(1), reason: 'one clip while zooming');
        zoomFrames++;
        final container =
            (zoom.single.clipper! as MorphZoomContinuousClipper).shape;
        if (recorder.shapes.isEmpty) continue;
        final body = recorder.shapes.last;
        final fit = container.width / body.width;
        expect(body.height * fit, closeTo(container.height, 1e-6));
        expect(body.tlRadiusX * fit, closeTo(container.tlRadiusX, 1e-6));
        expect(body.blRadiusX * fit, closeTo(container.blRadiusX, 1e-6));
        zoomCompared++;
        continue;
      }
      final clip = this.clip(tester, key: key);
      clips.add(clip);
      if (recorder.shapes.isEmpty) continue;
      expect(recorder.shapes, contains(clip), reason: 'frame $i');
      compared++;
    }
    return clips;
  }
}

Future<_Sheet> _present(
  WidgetTester tester, {
  bool dismissible = true,
  bool disableAnimations = false,
  MorphSourceLink? from,
}) async {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  final recorder = _Recorder();
  await tester.pumpWidget(
    MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations)
            .applyDisplayCornerRadii(
              const BorderRadius.all(Radius.circular(62)),
            ),
        child: MorphGlassScope(painter: recorder, child: child!),
      ),
      home: MorphScope(
        child: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 131,
                  top: 276,
                  width: 140,
                  height: 48,
                  child: MorphTag(
                    id: from ?? MorphSourceLink(),
                    shape: const StadiumBorder(),
                    child: GestureDetector(
                      onTap: () => showMorphSheet<void>(
                        context,
                        from: from,
                        dismissible: dismissible,
                        detents: const [
                          MorphSheetDetent.medium,
                          MorphSheetDetent.large,
                        ],
                        builder: (BuildContext context) =>
                            const SizedBox.expand(key: _content),
                      ),
                      child: const ColoredBox(
                        key: _source,
                        color: Color(0xFFFF00FF),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(_source));
  final sheet = _Sheet(recorder);
  await sheet.frames(tester, 80);
  return sheet;
}
