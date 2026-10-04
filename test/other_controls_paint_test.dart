import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/activity_indicator.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/page_control.dart';
import 'package:morph/src/widgets/glass_button.dart';

class _PaintCounter extends SingleChildRenderObjectWidget {
  const _PaintCounter({required this.onPaint, required super.child});
  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) => _Counter(onPaint);
}

class _Counter extends RenderProxyBox {
  _Counter(this.onPaint);
  final VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}

class _Glass extends MorphGlassPainter {
  final List<MorphGlassSurface> surfaces = [];
  int layers = 0;

  @override
  Widget buildLayer(
    BuildContext context,
    List<MorphGlassSurface> surfaces, {
    Widget? content,
    List<Rect> contentSlots = const [],
    double spacing = 0,
    MorphGlassOutline? outline,
  }) {
    layers++;
    return super.buildLayer(
      context,
      surfaces,
      content: content,
      contentSlots: contentSlots,
      spacing: spacing,
      outline: outline,
    );
  }

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) {
    surfaces.add(surface);
    return const SizedBox.expand();
  }
}

Widget _scene(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(),
    child: Center(child: child),
  ),
);

void main() {
  testWidgets('PF5 spinner paints only a changed measured image', (
    tester,
  ) async {
    var paints = 0;
    await tester.pumpWidget(
      _scene(
        RepaintBoundary(
          child: _PaintCounter(
            onPaint: () => paints++,
            child: const MorphActivityIndicator(),
          ),
        ),
      ),
    );
    await tester.pump();
    final initial = paints;
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(paints, initial);
    await tester.pump(const Duration(milliseconds: 16));
    expect(paints, initial + 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A6 D7 button gives the shared glass layer its measured glow', (
    tester,
  ) async {
    final glass = _Glass();
    await tester.pumpWidget(
      _scene(
        MorphGlass(
          painter: glass,
          child: MorphGlassButton(onPressed: () {}, child: const Text('Go')),
        ),
      ),
    );
    final layoutFinder = find.descendant(
      of: find.byType(MorphGlassButton),
      matching: find.byType(LayoutBuilder),
    );
    final layout = tester.widget<LayoutBuilder>(layoutFinder);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MorphGlassButton)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.widget<LayoutBuilder>(layoutFinder), same(layout));
    expect(glass.layers, greaterThan(0));
    expect(glass.surfaces.last.glow?.isVisible, isTrue);
    expect(glass.surfaces.last.lift, greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(glass.surfaces.last.glow, isNull);
  });
  testWidgets('PF5 page motion retains its paint widget across ticks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _scene(
        MorphPageControl(count: 3, page: 0, progress: 0.4, onChanged: (_) {}),
      ),
    );
    final paintFinder = find
        .descendant(
          of: find.byType(MorphPageControl),
          matching: find.byType(CustomPaint),
        )
        .last;
    final paint = tester.widget<CustomPaint>(paintFinder);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MorphPageControl)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.widget<CustomPaint>(paintFinder), same(paint));
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
