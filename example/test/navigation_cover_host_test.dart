// The test reads the navigation card's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
// The test switches the navigation card's cut and reads its strip.
// ignore: implementation_imports
import 'package:morph/src/widgets/navigation_card_reach.dart';
// ignore: implementation_imports
import 'package:morph/src/widgets/navigation_stack.dart'
    show debugNavigationCardOf, debugNavigationCoverCut;
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// A page under the sliding card of the page above paints only the strip
/// that card leaves visible, on the host's Impeller:
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/navigation_cover_host_test.dart
///
/// The reach of the card's rounded superellipse is checked against
/// Impeller's own raster of the clip; then every frame of the gallery's
/// pushes and pops is shot with the cut and without it in the same app
/// and must match to the byte. Without Impeller the test does nothing.
void main() {
  test('the card reach covers every pixel the clip leaves to the page '
      'under it', () async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    for (final (width, height, radius, ratio) in const [
      (411.43, 914.29, 62.0, 2.625),
      (402.0, 874.0, 62.0, 3.0),
      (402.0, 874.0, 55.0, 3.0),
      (768.0, 1024.0, 18.0, 2.0),
      (1024.0, 768.0, 18.0, 2.0),
      (200.0, 600.0, 62.0, 3.0),
      (320.0, 568.0, 40.0, 2.0),
    ]) {
      final columns = (width * ratio).round();
      final rows = (height * ratio).round();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final black = ui.Paint();
      black.color = const ui.Color(0xFF000000);
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, columns.toDouble(), rows.toDouble()),
        black,
      );
      canvas.scale(ratio);
      final card = ui.Rect.fromLTWH(0, 0, width, height);
      canvas.clipRSuperellipse(
        ui.RSuperellipse.fromRectAndRadius(card, ui.Radius.circular(radius)),
      );
      final white = ui.Paint();
      white.color = const ui.Color(0xFFFFFFFF);
      canvas.drawRect(card, white);
      final image = await recorder.endRecording().toImage(columns, rows);
      final pixels = (await image.toByteData())!;
      var last = -1;
      for (var x = 0; x < columns ~/ 2; x++) {
        for (final y in [0, 1, rows - 2, rows - 1]) {
          if (pixels.getUint8((y * columns + x) * 4) != 255) last = x;
        }
      }
      final reach =
          navigationCardEdgeReach(ui.Size(width, height), radius, ratio) *
          ratio;
      final label = '$width x $height r $radius at $ratio';
      expect(last, lessThan(reach), reason: label);
      // The rows the corner leaves run well past the corner itself.
      expect(last, greaterThan(radius * ratio), reason: label);
      expect(reach - last, lessThan(24), reason: label);
    }
  });

  for (final tier in const [MorphGlassTier.flat, MorphGlassTier.liquid]) {
    for (final brightness in Brightness.values) {
      testWidgets('${tier.name} ${brightness.name}: the cut page shows the '
          'same pixels', (WidgetTester tester) async {
        if (!ui.ImageFilter.isShaderFilterSupported) return;
        tester.view.physicalSize = const ui.Size(1080, 2400);
        tester.view.devicePixelRatio = 2.625;
        addTearDown(tester.view.reset);
        addTearDown(() => debugNavigationCoverCut = true);
        await tester.runAsync(GlassBuiltInPainter.precache);

        Future<void> frames(int count) async {
          for (var i = 0; i < count; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        final boundary = GlobalKey();
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: GalleryApp(navigatorKey: navigator),
          ),
        );
        await frames(10);
        final settings = GalleryGlassScope.read(navigator.currentContext!);
        settings.tier = tier;
        settings.appearance = brightness;
        settings.blur = 1;
        await frames(20);

        Future<Uint8List> shoot() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = (await tester.runAsync(
            () => render.toImage(pixelRatio: 2.625),
          ))!;
          return (await tester.runAsync(
            image.toByteData,
          ))!.buffer.asUint8List();
        }

        List<RenderObject> cards() => [
          for (final box in tester.allRenderObjects)
            if (debugNavigationCardOf(box) != null) box,
        ];

        var cut = 0;
        var pageCut = 0;
        var compared = 0;
        Future<void> slide(String name, int count) async {
          for (var frame = 0; frame < count; frame++) {
            await frames(1);
            final shown = [
              for (final box in cards()) ?debugNavigationCardOf(box)!.shown,
            ];
            final clipped = [
              for (final box in cards())
                if (debugNavigationCardOf(box)!.clip case final rect?)
                  if (rect.width < (box as RenderBox).size.width) rect,
            ];
            // Paints the cards again within this frame, so nothing but the
            // cut changes between the shots.
            Future<Uint8List> repaint({required bool cut}) async {
              debugNavigationCoverCut = cut;
              final boxes = cards();
              for (final box in boxes) {
                box.markNeedsPaint();
              }
              final owner = boxes.first.owner!;
              owner.flushCompositingBits();
              owner.flushPaint();
              return shoot();
            }

            final withCut = await repaint(cut: true);
            final whole = await repaint(cut: false);
            final again = await repaint(cut: true);
            expect(
              _differing(again, withCut),
              0,
              reason:
                  '$name frame $frame repeats: '
                  '${_box(again, withCut)}',
            );
            final differing = _differing(again, whole);
            expect(
              differing,
              0,
              reason:
                  '$name frame $frame: $differing pixels differ in '
                  '${_box(again, whole)} (strips $shown)',
            );
            compared++;
            if (shown.isNotEmpty) cut++;
            if (clipped.isNotEmpty) pageCut++;
          }
        }

        final entry = galleryEntries.firstWhere((e) => e.title == 'Navigation');
        unawaited(
          navigator.currentState!.push(
            MorphNavigationRoute<void>(builder: entry.builder),
          ),
        );
        await slide('enter', 40);
        await frames(60);
        await tester.tap(find.text('Message 0'));
        await slide('nested push', 40);
        await frames(60);
        unawaited(
          Navigator.of(
            tester.element(find.text('Message 0', skipOffstage: false)),
          ).maybePop(),
        );
        await slide('nested pop', 40);
        // The report is the test's output.
        // ignore: avoid_print
        print(
          '${tier.name} ${brightness.name}: $compared frames identical, '
          '$cut with the dim cut, $pageCut with the page cut',
        );
        expect(cut, greaterThan(compared ~/ 2));
        if (tier == MorphGlassTier.flat) expect(pageCut, cut);
      });
    }
  }
}

int _differing(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      count++;
    }
  }
  return count;
}

String _box(Uint8List a, Uint8List b) {
  const columns = 1080;
  var left = columns, top = 1 << 30, right = -1, bottom = -1, count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] == b[i] &&
        a[i + 1] == b[i + 1] &&
        a[i + 2] == b[i + 2] &&
        a[i + 3] == b[i + 3]) {
      continue;
    }
    final p = i ~/ 4;
    final x = p % columns;
    final y = p ~/ columns;
    count++;
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
  }
  return count == 0 ? 'none' : '$count px in x $left..$right y $top..$bottom';
}
