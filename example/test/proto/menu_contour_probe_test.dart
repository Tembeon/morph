import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/motion.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph_example/proto/menu_transfer_probe.dart';

const _output = String.fromEnvironment('P2_CONTOUR_OUTPUT');

Future<ui.Image> _raster(Path path, Rect bounds) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFFFFFFFF), .src);
  canvas.scale(3);
  canvas.translate(-bounds.left, -bounds.top);
  final paint = Paint();
  paint.color = const Color(0xFF000000);
  canvas.drawPath(path, paint);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (bounds.width * 3).ceil(),
    (bounds.height * 3).ceil(),
  );
  picture.dispose();
  return image;
}

Future<int> _difference(ui.Image a, ui.Image b) async {
  final first = (await a.toByteData(format: .rawRgba))!.buffer.asUint8List();
  final second = (await b.toByteData(format: .rawRgba))!.buffer.asUint8List();
  var changed = 0;
  for (var i = 0; i < first.length; i += 4) {
    if (first[i] != second[i] ||
        first[i + 1] != second[i + 1] ||
        first[i + 2] != second[i + 2] ||
        first[i + 3] != second[i + 3]) {
      changed++;
    }
  }
  return changed;
}

void main() {
  for (final gap in [0.0, 8.0, 12.0]) {
    testWidgets(
      'negative control: replacing carried contour at gap=$gap changes pixels',
      (tester) async {
        final motion = MorphMenuMotion(
          button: const Rect.fromLTWH(24, 80, 44, 44),
          bounds: const Size(402, 874),
          itemCount: 3,
        );
        final source = ProbeMenuLease(.source);
        final route = ProbeMenuLease(.route);
        final transfer = ProbeMenuTransfer(
          motion: motion,
          source: source,
          sourceTime: 0,
        );
        transfer.open(source, 0);
        transfer.transfer(source, fromTime: 0, to: route, toTime: 0);
        for (var frame = 0; frame <= 120; frame++) {
          transfer.advance(route, frame / 120);
        }
        transfer.close(route, 1);
        var frame = 121;
        while (!transfer.readyToHandBack) {
          transfer.advance(route, frame++ / 120);
          expect(frame, lessThan(300));
        }
        final neighbor = RRect.fromRectAndRadius(
          Rect.fromLTWH(68 + gap, 80, 44, 44),
          const Radius.circular(22),
        );
        final neighborPath = Path();
        neighborPath.addRRect(neighbor);
        final carried = Path.combine(
          .union,
          motion.silhouetteFor(withField: false)!.path,
          neighborPath,
        );
        final at = transfer.frame;
        transfer.transfer(route, fromTime: at.time, to: source, toTime: 73);
        expect(transfer.frame, at);
        final preserved = Path.combine(
          .union,
          motion.silhouetteFor(withField: false)!.path,
          neighborPath,
        );
        final container = morphGlassContainerOutline(
          [neighbor, transfer.frame.button, transfer.frame.menu],
          12,
          withField: false,
        ).path;
        final bounds = carried
            .getBounds()
            .expandToInclude(container.getBounds())
            .inflate(2);
        await tester.runAsync(() async {
          final before = await _raster(carried, bounds);
          final after = await _raster(container, bounds);
          final kept = await _raster(preserved, bounds);
          try {
            final changed = await _difference(before, after);
            final carryChanged = await _difference(before, kept);
            debugPrint(
              'P2_CONTOUR ${jsonEncode({'gap': gap, 'time': at.time, 'progress': at.progress, 'fusionRadius': at.fusionRadius, 'containerChangedPixels': changed, 'preservedChangedPixels': carryChanged, 'width': before.width, 'height': before.height})}',
            );
            if (_output.isNotEmpty) {
              final dir = Directory('$_output/gap-${gap.toInt()}');
              await dir.create(recursive: true);
              for (final (name, image) in [
                ('before', before),
                ('container', after),
                ('preserved', kept),
              ]) {
                final png = (await image.toByteData(format: .png))!;
                await File(
                  '${dir.path}/$name.png',
                ).writeAsBytes(png.buffer.asUint8List());
              }
            }
            expect(
              carryChanged,
              0,
              reason: 'Changing owner preserves the carried contour',
            );
            expect(
              changed,
              greaterThan(0),
              reason: 'This rejected replacement is not a continuous hand-back',
            );
          } finally {
            before.dispose();
            after.dispose();
            kept.dispose();
          }
        });
      },
    );
  }
}

// ignore_for_file: implementation_imports, invalid_use_of_internal_member
