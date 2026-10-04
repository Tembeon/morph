import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_liquid_native.dart';
import 'package:morph/widgets.dart';

void main() {
  setUp(() => isLocalTest = true);
  tearDown(() => isLocalTest = false);

  testWidgets('G7 a lifted multi-slot lens mounts keyed content once', (
    tester,
  ) async {
    final key = GlobalKey();
    final focus = FocusNode();
    var builds = 0;
    Widget host(double lift) => Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 300,
        height: 62,
        child: Builder(
          builder: (context) {
            return const MorphGlassRenderer().buildLayer(
              context,
              [
                const MorphGlassSurface(
                  kind: MorphGlassKind.bar,
                  shape: RRect.fromLTRBXY(0, 0, 300, 62, 31, 31),
                  color: Color(0xFFFFFFFF),
                  brightness: Brightness.light,
                ),
                MorphGlassSurface(
                  kind: MorphGlassKind.lens,
                  shape: const RRect.fromLTRBXY(10, -6, 150, 68, 37, 37),
                  color: const Color(0xFFFFFFFF),
                  brightness: Brightness.light,
                  lift: lift,
                  optics: MorphGlassOptics.large,
                ),
              ],
              contentSlots: const [
                Rect.fromLTWH(0, 0, 100, 62),
                Rect.fromLTWH(100, 0, 100, 62),
              ],
              content: Builder(
                builder: (context) {
                  builds++;
                  return Focus(
                    key: key,
                    focusNode: focus,
                    child: const Text('One mount'),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpWidget(host(0));
    final element = key.currentContext;
    await tester.pumpWidget(host(1));
    expect(tester.takeException(), isNull);
    expect(key.currentContext, same(element));
    expect(find.text('One mount'), findsOneWidget);
    expect(find.byType(MorphGlassContentCopy), findsOneWidget);
    expect(builds, 2);
    await tester.pumpWidget(host(0));
    expect(key.currentContext, same(element));
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
  });

  testWidgets('G7 copies the current composited paint without another mount', (
    tester,
  ) async {
    Widget host(Color color) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 100,
          height: 40,
          child: Builder(
            builder: (context) => const MorphGlassRenderer().buildLayer(
              context,
              [
                const MorphGlassSurface(
                  kind: MorphGlassKind.lens,
                  shape: RRect.fromLTRBXY(0, 0, 100, 40, 20, 20),
                  color: Color(0x00FFFFFF),
                  brightness: Brightness.light,
                  lift: 1,
                  optics: MorphGlassOptics.large,
                ),
              ],
              content: Opacity(opacity: 0.5, child: ColoredBox(color: color)),
            ),
          ),
        ),
      ),
    );
    Future<List<int>> pixel() async {
      final copy = tester.widget<MorphGlassContentCopy>(
        find.byType(MorphGlassContentCopy),
      );
      final recorder = ui.PictureRecorder();
      copy.snapshot.paint(ui.Canvas(recorder));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 40);
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!;
      final offset = (20 * 100 + 50) * 4;
      final rgba = [for (var i = 0; i < 4; i++) data.getUint8(offset + i)];
      image.dispose();
      picture.dispose();
      return rgba;
    }

    await tester.pumpWidget(host(const Color(0xFFFF0000)));
    expect(await tester.runAsync(pixel), [255, 0, 0, 128]);
    await tester.pumpWidget(host(const Color(0xFF00FF00)));
    expect(await tester.runAsync(pixel), [0, 255, 0, 128]);
    expect(
      find
          .byType(ColoredBox)
          .evaluate()
          .where(
            (element) =>
                (element.widget as ColoredBox).color == const Color(0xFF00FF00),
          ),
      hasLength(1),
    );
  });
}
