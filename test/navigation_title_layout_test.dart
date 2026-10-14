import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/navigation_bar.dart'
    show morphInlineTitleBounds, morphInlineTitleFrame;
import 'package:morph/widgets.dart';

// Native rows (iPhone 17 Pro simulator, iOS 27.0, 402 pt): a chevron back
// capsule 16 - 60, an icon pair capsule 282 - 386, the heart/share pair
// beside a prominent Done from 197; title ink positions in the comments.
({double left, double width, bool centered})? _frame(
  double text, {
  List<(double, double, bool)> capsules = const [],
  bool rtl = false,
}) {
  final b = morphInlineTitleBounds(
    barWidth: 402,
    sideInset: 16,
    capsules: capsules,
  );
  return morphInlineTitleFrame(
    barWidth: 402,
    textWidth: text,
    lo: b.lo,
    hi: b.hi,
    rtl: rtl,
  );
}

const _back = (16.0, 60.0, true);
const _pair = (282.0, 386.0, false);
const _pairDone = (197.0, 386.0, false);

void main() {
  group('the native title rule', () {
    test('a title that fits centered stays centered', () {
      // "Hi" ink 194.0 - 207.7 beside the pair.
      final f = _frame(14, capsules: [_back, _pair])!;
      expect(f.centered, isTrue);
      expect(f.left, closeTo(194, 0.5));
      // A 293 pt title without groups: ink 54.3 - 347.3.
      expect(_frame(293)!.left, closeTo(54.5, 0.5));
    });

    test('a title that does not fit centered goes to the leading bound', () {
      // "A medium length title" (168 pt) beside the pair: ink from 72.7.
      final f = _frame(168, capsules: [_back, _pair])!;
      expect(f.centered, isFalse);
      expect(f.left, 72);
      expect(f.width, 168);
      // "Hi" beside heart/share + Done: ink 73.7 - 87.3.
      expect(_frame(14, capsules: [_back, _pairDone])!.left, 72);
      // A long title over a back button alone: ink from 72.7.
      expect(_frame(263, capsules: [_back])!.left, 72);
    });

    test('a title truncates at the trailing bound', () {
      // Ellipsis ink ends at 268.3 against the pair (bound 270).
      final f = _frame(400, capsules: [_back, _pair])!;
      expect(f.left, 72);
      expect(f.width, 270 - 72);
      // Without trailing groups the side inset bounds it (ink to 379.7).
      expect(_frame(500, capsules: [_back])!.width, 386 - 72);
    });

    test('a capsule across the center bounds its own side', () {
      final f = _frame(60, capsules: [_back, (150.0, 386.0, false)])!;
      expect(f.left, 72);
      expect(f.width, 60);
    });

    test('no room drops the title', () {
      // Select All / Share / Organize from 77 next to the back button.
      expect(_frame(50, capsules: [_back, (77.0, 386.0, false)]), isNull);
    });

    test('right-to-left text mirrors the leading bound', () {
      final f = _frame(
        168,
        capsules: [(342.0, 386.0, false), (16.0, 120.0, true)],
        rtl: true,
      )!;
      expect(f.centered, isFalse);
      expect(f.left + f.width, 330);
    });
  });

  testWidgets('a wide trailing group never runs under the title', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    MorphBarButton text(String id) =>
        MorphBarButton(id: id, label: id, onPressed: () {});
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MorphNavigationBar(
          title: 'Message',
          subtitle: 'From Anna',
          leading: [
            MorphBarButtonGroup([MorphBarButton.back(onPressed: () {})]),
          ],
          trailing: [
            MorphBarButtonGroup([text('AA'), text('BB'), text('CC')]),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final title = tester.getRect(find.text('Message'));
    final button = tester.getRect(find.text('AA'));
    expect(
      button.left,
      lessThan(201),
      reason: 'the group straddles the center',
    );
    expect(title.right, lessThanOrEqualTo(button.left));
    expect(
      tester.getRect(find.text('From Anna')).right,
      lessThanOrEqualTo(button.left),
    );
  });
}
