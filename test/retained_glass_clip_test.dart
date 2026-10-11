// The test drives the renderer's internal clip retention directly.
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/retained_glass_clip.dart';

class _CountingClipper extends CustomClipper<Path> {
  _CountingClipper({super.reclip});

  int calls = 0;

  @override
  Path getClip(Size size) {
    calls++;
    return Path()..addOval(Offset.zero & size);
  }

  @override
  bool shouldReclip(_CountingClipper oldClipper) => true;
}

void main() {
  testWidgets('a clipper path is kept until the clip itself would change', (
    WidgetTester tester,
  ) async {
    final owner = GlobalKey();
    final shape = GlobalKey();
    final reclip = ValueNotifier(0);
    addTearDown(reclip.dispose);
    Widget scene(
      _CountingClipper clipper,
      double width, {
      Clip behavior = Clip.antiAlias,
    }) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: owner,
          width: 200,
          height: 200,
          child: Align(
            alignment: Alignment.topLeft,
            child: ClipPath(
              clipper: clipper,
              clipBehavior: behavior,
              child: SizedBox(key: shape, width: width, height: 50),
            ),
          ),
        ),
      ),
    );
    RenderBox box(GlobalKey key) =>
        key.currentContext!.findRenderObject()! as RenderBox;

    var clipper = _CountingClipper(reclip: reclip);
    await tester.pumpWidget(scene(clipper, 100));
    final clip = RetainedGlassClip();
    addTearDown(clip.dispose);
    clip.update(box(owner), [box(shape)]);

    int calls(void Function() sync) {
      final before = clipper.calls;
      sync();
      return clipper.calls - before;
    }

    expect(calls(clip.sync), 1);
    expect(calls(clip.sync), 0);
    expect(calls(clip.sync), 0);
    expect(clip.ownerBounds, const Rect.fromLTWH(0, 0, 100, 50));

    reclip.value++;
    expect(calls(clip.sync), 1);
    expect(calls(clip.sync), 0);

    await tester.pumpWidget(scene(clipper, 120));
    expect(calls(clip.sync), 1);
    expect(clip.ownerBounds, const Rect.fromLTWH(0, 0, 120, 50));

    clipper = _CountingClipper(reclip: reclip);
    await tester.pumpWidget(scene(clipper, 120));
    expect(calls(clip.sync), 1);
    expect(calls(clip.sync), 0);

    await tester.pumpWidget(scene(clipper, 150, behavior: Clip.none));
    clip.sync();
    expect(clip.ownerBounds, isNull);
    await tester.pumpWidget(scene(clipper, 150));
    clip.sync();
    expect(
      clip.ownerBounds,
      const Rect.fromLTWH(0, 0, 150, 50),
      reason: 'a resize while the clip was off must not leave the old path',
    );
  });
}
