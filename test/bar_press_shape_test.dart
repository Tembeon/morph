import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/glass_painter.dart';
import 'package:morph/src/widgets/bar_items.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/widgets.dart';

class _Recorder extends MorphGlassPainter {
  List<MorphGlassSurface> surfaces = [];

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) =>
      const SizedBox.expand();

  @override
  Widget buildLayer(
    BuildContext context,
    List<MorphGlassSurface> surfaces, {
    Widget? content,
    List<Rect> contentSlots = const [],
    double spacing = 0,
    MorphGlassOutline? outline,
  }) {
    this.surfaces = surfaces;
    return content ?? const SizedBox.expand();
  }

  RRect get shape => surfaces.where((s) => s.opacity > 0).single.shape;
}

void main() {
  for (final (name, metrics) in [
    ('navigation', MorphBarMetrics.navigation),
    ('toolbar', MorphBarMetrics.toolbar),
  ]) {
    for (final wide in [false, true]) {
      testWidgets('$name ${wide ? 'wide' : 'round'} capsule retains its '
          'rounded ends through a hold, drag and release', (tester) async {
        final recorder = _Recorder();
        await tester.pumpWidget(
          MaterialApp(
            home: MorphGlassScope(
              painter: recorder,
              child: Center(
                child: SizedBox(
                  width: 340,
                  height: 80,
                  child: MorphBarItems(
                    metrics: metrics,
                    top: 16,
                    leadingInset: 28,
                    trailingInset: 28,
                    groups: [
                      MorphPlacedGroup(
                        MorphBarButtonGroup([
                          MorphBarButton(
                            id: 'button',
                            label: wide ? 'Options' : null,
                            icon: wide
                                ? null
                                : const SizedBox.square(dimension: 24),
                            onPressed: () {},
                          ),
                        ], id: 'group'),
                        MorphBarSide.leading,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rest = recorder.shape;
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey<Object>('button'))),
        );
        var expanded = false;
        Future<void> checkFrames(int count) async {
          for (var i = 0; i < count; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            final shape = recorder.shape;
            expanded = expanded || shape.height > rest.height + 1;
            // A held circle has no straight side; a wide capsule's end
            // still spans its full height, including during spring recoil.
            expect(
              shape.tlRadiusX,
              closeTo(shape.shortestSide / 2, 1e-9),
              reason: 'The corner must follow the visible capsule size.',
            );
          }
        }

        await checkFrames(40);
        await gesture.moveBy(const Offset(18, 4));
        await checkFrames(20);
        await gesture.up();
        await checkFrames(80);
        await tester.pumpAndSettle();
        expect(expanded, isTrue);
        expect(
          recorder.shape.outerRect,
          rectMoreOrLessEquals(rest.outerRect, epsilon: MorphRest.length),
        );
        expect(
          recorder.shape.tlRadiusX,
          closeTo(rest.tlRadiusX, MorphRest.length),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
