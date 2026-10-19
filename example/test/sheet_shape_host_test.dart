import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

/// A sheet's glass and its clip are one outline: the rim and the
/// refraction band of the floating sheet's glass run round all four of
/// its corners, the 54 point bottom ones as well as the 38 point top
/// ones, as UIKit's single per-corner glass element draws them (device
/// reference tool/ios_reference/references/dark/sheet-medium.png), on the
/// host's Impeller with the liquid tier:
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/sheet_shape_host_test.dart
///
/// The sheet floats at the medium detent over a flat page; at the 45
/// degree point of each corner the test reads the pixels just inside the
/// clip's edge along the diagonal and compares them with the glass
/// farther in. A glass drawn with another outline than the clip's leaves
/// a corner with no rim at all. Without Impeller the test does nothing.
void main() {
  const page = Color(0xFF2050A0);
  const scale = 3.0;

  for (final brightness in Brightness.values) {
    testWidgets('the rim runs round every corner (${brightness.name})', (
      WidgetTester tester,
    ) async {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      tester.view.physicalSize = const ui.Size(402, 874) * scale;
      tester.view.devicePixelRatio = scale;
      addTearDown(tester.view.reset);
      await tester.runAsync(GlassBuiltInPainter.precache);
      if (!MorphTheme.liquidGlassAvailable) return;

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
      late BuildContext content;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(402, 874),
              devicePixelRatio: scale,
              padding: EdgeInsets.only(top: 62, bottom: 34),
              viewPadding: EdgeInsets.only(top: 62, bottom: 34),
              displayCornerRadii: BorderRadius.all(Radius.circular(62)),
            ),
            child: MorphTheme(
              data: MorphThemeData(
                brightness: brightness,
                glass: const MorphGlassRenderer.tier(MorphGlassTier.liquid),
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Navigator(
                  key: navigator,
                  onGenerateRoute: (RouteSettings settings) =>
                      PageRouteBuilder<void>(
                        pageBuilder:
                            (
                              BuildContext context,
                              Animation<double> a,
                              Animation<double> b,
                            ) => const ColoredBox(
                              color: page,
                              child: SizedBox.expand(),
                            ),
                      ),
                ),
              ),
            ),
          ),
        ),
      );
      await frames(5);
      unawaited(
        showMorphSheet<void>(
          navigator.currentContext!,
          detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
          builder: (BuildContext context) {
            content = context;
            return const SizedBox.expand();
          },
        ),
      );

      Future<_Shot> shoot() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = (await tester.runAsync(
          () => render.toImage(pixelRatio: scale),
        ))!;
        final data = (await tester.runAsync(image.toByteData))!;
        final shot = _Shot(data.buffer.asUint8List(), image.width);
        image.dispose();
        return shot;
      }

      await frames(90);
      final rest = await shoot();
      MorphSheet.of(content).animateTo(MorphSheetDetent.large);
      await frames(4);
      final docking = await shoot();

      for (final (moment, shot) in [('rest', rest), ('docking', docking)]) {
        final rims = shot.cornerRims();
        final top = math.min(rims.topLeft, rims.topRight);
        final bottom = math.min(rims.bottomLeft, rims.bottomRight);
        expect(top, greaterThan(12), reason: '$moment: $rims');
        expect(bottom, greaterThan(top * 0.4), reason: '$moment: $rims');
      }
    });
  }
}

class _Shot {
  _Shot(this.bytes, this.width);

  final Uint8List bytes;
  final int width;

  int get height => bytes.length ~/ 4 ~/ width;

  int _sum(int x, int y) {
    final i = (y * width + x) * 4;
    return bytes[i] + bytes[i + 1] + bytes[i + 2];
  }

  // The dimmed page, read in the screen's top left corner.
  bool _isPage(int x, int y) {
    final i = (y * width + x) * 4;
    return (bytes[i] - bytes[0]).abs() +
            (bytes[i + 1] - bytes[1]).abs() +
            (bytes[i + 2] - bytes[2]).abs() <
        6;
  }

  /// The column's first pixel that is not the page, from the top.
  int _topOf(int x) {
    for (var y = 0; y < height; y++) {
      if (!_isPage(x, y)) return y;
    }
    return height;
  }

  /// The row's first pixel that is not the page, from the left.
  int _leftOf(int y) {
    for (var x = 0; x < width; x++) {
      if (!_isPage(x, y)) return x;
    }
    return width;
  }

  /// How far the pixels 2 to 10 inside the edge differ from the glass 60
  /// pixels in, summed along the inward diagonal of each corner from its
  /// 45 degree point: the rim and the refraction band. Zero is a corner
  /// whose visible edge cuts through the glass's interior.
  ({double topLeft, double topRight, double bottomLeft, double bottomRight})
  cornerRims() {
    final top = _topOf(width ~/ 2);
    final bottom = height - 1 - _bottomInset();
    final left = _leftOf((top + bottom) ~/ 2);
    final right = width - 1 - left;
    const reach = 150;
    double rim(int cx, int cy, double angle) {
      final dx = math.cos(angle);
      final dy = math.sin(angle);
      var t = 0.0;
      while (true) {
        final x = (cx + dx * t).round();
        final y = (cy + dy * t).round();
        if (x < 0 || y < 0 || x >= width || y >= height || _isPage(x, y)) {
          break;
        }
        t += 0.25;
      }
      int at(double k) =>
          _sum((cx + dx * (t - k)).round(), (cy + dy * (t - k)).round());
      final interior = at(60);
      var band = 0;
      for (var k = 2; k <= 10; k++) {
        band += (at(k.toDouble()) - interior).abs();
      }
      return band.toDouble();
    }

    const quarter = math.pi / 4;
    return (
      topLeft: rim(left + reach, top + reach, math.pi + quarter),
      topRight: rim(right - reach, top + reach, -quarter),
      bottomLeft: rim(left + reach, bottom - reach, math.pi - quarter),
      bottomRight: rim(right - reach, bottom - reach, quarter),
    );
  }

  int _bottomInset() {
    final x = width ~/ 2;
    for (var y = height - 1; y >= 0; y--) {
      if (!_isPage(x, y)) return height - 1 - y;
    }
    return 0;
  }
}
