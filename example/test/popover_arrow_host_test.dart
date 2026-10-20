// The test drives the package's internal placement.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/pass/final_pass.dart';
import 'package:morph/morph.dart';
// ignore: implementation_imports
import 'package:morph/src/widgets/alert_motion.dart';
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_tier.dart';

/// An action sheet popover's arrow is the popover's own glass: on the host
/// Impeller, over a plain backdrop, the arrow and the content shade
/// continuously across the edge the arrow leaves, in every direction, in
/// light and dark, on the liquid and the flat tier, with the arrow slid
/// toward a corner, and while the popover grows out of and shrinks into
/// the arrow's tip. Before the arrow was part of the glass, the liquid
/// tier stepped 20 - 88 in luma across that edge (the content's rim ran
/// across the arrow's base) and the arrow differed from the content by 7 -
/// 10 per channel.
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/popover_arrow_host_test.dart
///
/// `--dart-define=POPOVER_DUMP=<dir>` writes each shot as a PNG. Without
/// Impeller the test does nothing.
const double _dpr = 3;
const Size _screen = Size(402, 874);
const String _dump = String.fromEnvironment('POPOVER_DUMP');

const Color _backdrop = Color(0xFF5A7FA8);

final GlobalKey _shot = GlobalKey();

Widget _page(Brightness brightness, MorphGlassTier tier, Rect source) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(platform: TargetPlatform.iOS, brightness: brightness),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(platformBrightness: brightness, padding: EdgeInsets.zero),
        child: GlassAdaptiveScope(
          renderer: const GlassBuiltInPainter(),
          tier: tier,
          child: RepaintBoundary(key: _shot, child: child),
        ),
      ),
      home: ColoredBox(
        color: _backdrop,
        child: Builder(
          builder: (BuildContext context) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showMorphActionSheet(
              context,
              title: 'Title',
              message: 'Message',
              anchorRect: source,
              actions: const [
                MorphAlertAction(title: 'One'),
                MorphAlertAction(title: 'Two'),
                MorphAlertAction(
                  title: 'Cancel',
                  style: MorphAlertActionStyle.cancel,
                ),
              ],
            ),
          ),
        ),
      ),
    );

class _Shot {
  _Shot(this.width, this.bytes);

  final int width;
  final Uint8List bytes;

  /// The color at [p] in logical pixels, as RGB.
  List<int> at(Offset p) {
    final x = (p.dx * _dpr).floor();
    final y = (p.dy * _dpr).floor();
    final i = (y * width + x) * 4;
    return [bytes[i], bytes[i + 1], bytes[i + 2]];
  }
}

double _luma(List<int> c) => 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2];

double _distance(List<int> a, List<int> b) =>
    ((a[0] - b[0]).abs() + (a[1] - b[1]).abs() + (a[2] - b[2]).abs()) / 3;

/// How the arrow meets the content in one shot, along the arrow's axis.
class _Seam {
  _Seam(this.step, this.interior, this.material);

  /// The largest luma step between neighboring device pixels within 3 pt
  /// either side of the edge the arrow leaves.
  final double step;

  /// The same, 4 to 10 pt inside the content: the glass's own variation.
  final double interior;

  /// The mean channel difference between the arrow 5 pt past that edge
  /// and the content 5 pt inside it.
  final double material;
}

/// Measures the seam of [placement] drawn at [scale] about its anchor.
_Seam _measure(_Shot shot, MorphPopoverPlacement placement, double scale) {
  final content = placement.content;
  final anchor = placement.anchor;
  Offset screen(Offset p) => anchor + (p - anchor) * scale;
  final (Offset base, Offset out) = switch (placement.arrowDirection) {
    MorphPopoverArrowDirection.down => (
      Offset(placement.arrowCenter, content.bottom),
      const Offset(0, 1),
    ),
    MorphPopoverArrowDirection.up => (
      Offset(placement.arrowCenter, content.top),
      const Offset(0, -1),
    ),
    MorphPopoverArrowDirection.left => (
      Offset(content.left, placement.arrowCenter),
      const Offset(-1, 0),
    ),
    MorphPopoverArrowDirection.right => (
      Offset(content.right, placement.arrowCenter),
      const Offset(1, 0),
    ),
  };
  List<int> at(double t) => shot.at(screen(base + out * t));
  double steps(double from, double to) {
    var worst = 0.0;
    var last = _luma(at(from));
    for (var t = from + 1 / _dpr / scale; t <= to; t += 1 / _dpr / scale) {
      final now = _luma(at(t));
      worst = math.max(worst, (now - last).abs());
      last = now;
    }
    return worst;
  }

  return _Seam(steps(-3, 3), steps(-10, -4), _distance(at(5), at(-5)));
}

void main() {
  testWidgets('the arrow shades as one glass with the popover', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = _screen * _dpr;
    tester.view.devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    await tester.runAsync(GlassBuiltInPainter.precache);
    await tester.runAsync(GlassFinalPass.precacheAnalyticShaders);

    final sources = {
      'down': const Rect.fromLTWH(179, 780, 44, 44),
      'up': const Rect.fromLTWH(179, 60, 44, 44),
      'left': const Rect.fromLTWH(12, 400, 44, 44),
      'right': const Rect.fromLTWH(346, 400, 44, 44),
      'corner': const Rect.fromLTWH(48, 820, 44, 44),
    };
    for (final brightness in Brightness.values) {
      for (final tier in [MorphGlassTier.liquid, MorphGlassTier.flat]) {
        for (final MapEntry(key: name, value: source) in sources.entries) {
          final label = '$name ${brightness.name} ${tier.name}';
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(_page(brightness, tier, source));
          await tester.pump();
          await tester.tapAt(const Offset(201, 437));
          final card = find
              .ancestor(
                of: find.text('Title'),
                matching: find.byType(ClipRRect),
              )
              .first;
          // Mid present, at rest and mid dismiss.
          for (final (moment, frames) in [
            ('present', 8),
            ('rest', 90),
            ('dismiss', 6),
          ]) {
            if (moment == 'dismiss') {
              Navigator.of(tester.element(find.text('Title'))).pop();
            }
            for (var i = 0; i < frames; i++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            for (var i = 0; i < 4; i++) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 30)),
              );
            }
            await tester.pump();
            final size = tester.getSize(card);
            final shown = tester.getRect(card);
            final scale = shown.width / size.width;
            final placement = morphPlacePopover(
              size: size,
              source: source,
              screen: _screen,
            );
            // The popover scales about the arrow's tip.
            final anchor = placement.anchor;
            expect(
              shown.topLeft,
              offsetMoreOrLessEquals(
                anchor + (placement.content.topLeft - anchor) * scale,
                epsilon: 0.01,
              ),
              reason: '$label $moment',
            );
            final render =
                _shot.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = (await tester.runAsync(
              () => render.toImage(pixelRatio: _dpr),
            ))!;
            final data = (await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
            ))!;
            if (_dump.isNotEmpty) {
              final png = (await tester.runAsync(
                () => image.toByteData(format: ui.ImageByteFormat.png),
              ))!;
              File(
                '$_dump/${'$label $moment'.replaceAll(' ', '-')}.png',
              ).writeAsBytesSync(png.buffer.asUint8List());
            }
            final width = image.width;
            image.dispose();
            final seam = _measure(
              _Shot(width, data.buffer.asUint8List()),
              placement,
              scale,
            );
            // A summary line per shot is the host run's output.
            // ignore: avoid_print
            print(
              '$label $moment ${placement.arrowDirection.name} '
              'scale ${scale.toStringAsFixed(2)} '
              'step ${seam.step.toStringAsFixed(1)} '
              'interior ${seam.interior.toStringAsFixed(1)} '
              'material ${seam.material.toStringAsFixed(1)}',
            );
            expect(
              seam.step,
              lessThanOrEqualTo(seam.interior + 4),
              reason: '$label $moment',
            );
            expect(
              seam.material,
              lessThanOrEqualTo(3),
              reason: '$label $moment',
            );
          }
          for (var i = 0; i < 60; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
        }
      }
    }
  });
}
