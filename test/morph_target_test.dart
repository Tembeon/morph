import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

void main() {
  group('degenerate overlays', () {
    test('dialog floors its rect at zero on a tiny overlay', () {
      final Rect rect = MorphTargetSpec.dialog().rectFor(
        const Size(30, 30),
        EdgeInsets.zero,
      );
      expect(rect.width, greaterThanOrEqualTo(0));
      expect(rect.height, greaterThanOrEqualTo(0));
    });

    test('sheet floors its rect at zero on a tiny overlay', () {
      final Rect rect = MorphTargetSpec.sheet().rectFor(
        const Size(20, 20),
        const EdgeInsets.only(top: 40, bottom: 40),
      );
      expect(rect.width, greaterThanOrEqualTo(0));
      expect(rect.height, greaterThanOrEqualTo(0));
    });
  });

  group('popover placement', () {
    test('the bottom safe area counts when deciding to flip above', () {
      const Rect anchor = Rect.fromLTWH(100, 420, 80, 40);
      const Size overlay = Size(400, 640);
      final MorphTargetSpec spec = MorphTargetSpec.popover(
        anchor: anchor,
        size: const Size(200, 120),
      );
      // Without bottom padding the popover fits below the anchor.
      final Rect below = spec.rectFor(overlay, EdgeInsets.zero);
      expect(below.top, greaterThan(anchor.bottom));
      // A home indicator eats the room below: the popover must flip
      // above instead of sitting under system chrome.
      final Rect above = spec.rectFor(
        overlay,
        const EdgeInsets.only(bottom: 60),
      );
      expect(above.bottom, lessThan(anchor.top));
    });

    test('content height alone forces the flip above', () {
      // No safe area anywhere: the flip decision is purely the content
      // height against the room below the anchor.
      const Rect anchor = Rect.fromLTWH(100, 420, 80, 40);
      final MorphTargetSpec spec = MorphTargetSpec.popover(
        anchor: anchor,
        size: const Size(200, 220),
      );
      final Rect rect = spec.rectFor(const Size(400, 640), EdgeInsets.zero);
      expect(rect.bottom, lessThan(anchor.top));
      // The gap is preserved on the flipped side.
      expect(anchor.top - rect.bottom, 10);
    });

    test('a popover taller than either side clamps inside the overlay', () {
      // Neither below nor above fits a 900 px popover: it pins to the
      // top margin instead of escaping off-screen.
      final MorphTargetSpec spec = MorphTargetSpec.popover(
        anchor: const Rect.fromLTWH(100, 300, 80, 40),
        size: const Size(200, 900),
      );
      final Rect rect = spec.rectFor(const Size(400, 640), EdgeInsets.zero);
      expect(rect.top, 12);
      expect(rect.left, greaterThanOrEqualTo(12));
      expect(rect.right, lessThanOrEqualTo(400 - 12));
    });

    test('horizontal safe areas clamp the popover', () {
      final MorphTargetSpec spec = MorphTargetSpec.popover(
        anchor: const Rect.fromLTWH(0, 100, 40, 40),
        size: const Size(200, 120),
      );
      final Rect rect = spec.rectFor(
        const Size(400, 640),
        const EdgeInsets.only(left: 44),
      );
      expect(rect.left, greaterThanOrEqualTo(44));
    });
  });

  testWidgets('maybeMorphAnchorRect degrades to null off the tree', (
    WidgetTester tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            captured = context;
            return const Text('probe');
          },
        ),
      ),
    );
    expect(maybeMorphAnchorRect(captured), isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(maybeMorphAnchorRect(captured), isNull);
  });
}
