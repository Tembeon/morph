import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

const double _rowHeight = 40;
const double _dialogWidth = 300;

/// Rows of a fixed height under a notifier: the content changes size
/// on its own, without any shuttle rebuild.
Widget rows(ValueNotifier<int> count) {
  return ValueListenableBuilder<int>(
    valueListenable: count,
    builder: (BuildContext context, int n, Widget? _) => Column(
      mainAxisSize: .min,
      children: <Widget>[
        for (int i = 0; i < n; i++)
          SizedBox(height: _rowHeight, child: Text('row-$i')),
      ],
    ),
  );
}

class _Host extends StatelessWidget {
  const _Host({required this.onOpen, this.reducedMotion = false});

  final void Function(BuildContext context) onOpen;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: MorphScope(child: child!),
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const .all(40),
            child: MorphTag(
              id: 'btn',
              child: Builder(
                builder: (BuildContext context) => GestureDetector(
                  onTap: () => onOpen(context),
                  child: const SizedBox(
                    width: 120,
                    height: 40,
                    child: Text('open-me'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.takeException(), isNull);
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

void frame(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Whether the source tag currently renders hidden (its content rides
/// the shuttle).
bool tagHidden(WidgetTester tester) {
  final IgnorePointer ignore = tester.widget<IgnorePointer>(
    find
        .descendant(
          of: find.byType(MorphTag),
          matching: find.byType(IgnorePointer),
        )
        .first,
  );
  return ignore.ignoring;
}

void main() {
  testWidgets('a measured dialog opens to its content, and the launch never '
      'shows a guessed box', (WidgetTester tester) async {
    frame(tester);
    final ValueNotifier<int> count = ValueNotifier<int>(3);
    addTearDown(count.dispose);
    MorphFlight? flight;
    await tester.pumpWidget(
      _Host(
        onOpen: (BuildContext context) {
          flight = showMorphDialog(
            context,
            from: 'btn',
            width: _dialogWidth,
            fitContent: true,
            builder: (BuildContext context, MorphFlight flight) => rows(count),
          );
        },
      ),
    );
    await tester.tap(find.text('open-me'));
    // Frame 0: the shuttle is laid out but shown nowhere, and the
    // source is still visible - nothing sizes the box yet.
    await tester.pump();
    expect(flight!.target.isMeasured, isTrue);
    expect(tagHidden(tester), isFalse);
    final Iterable<Opacity> veils = tester
        .widgetList<Opacity>(
          find.ancestor(of: find.text('row-0'), matching: find.byType(Opacity)),
        )
        .where((Opacity o) => o.opacity == 0);
    expect(veils, isNotEmpty, reason: 'the staged shuttle is invisible');
    // The measurement landed after that frame and seeded the size.
    expect(flight!.contentSize, const Size(_dialogWidth, 3 * _rowHeight));
    // Frame 1: the source hides and the shuttle flies to the measured
    // box.
    await tester.pump();
    expect(tagHidden(tester), isTrue);
    expect(flight!.lastTargetRect.size, const Size(_dialogWidth, 120));
    await settle(tester);
    expect(flight!.lastTargetRect.size, const Size(_dialogWidth, 120));
    // The content sits inside the box at its natural size.
    final Rect row2 = tester.getRect(find.text('row-2'));
    expect(row2.bottom, moreOrLessEquals(flight!.lastTargetRect.bottom));
    flight!.close();
    await settle(tester);
    expect(flight!.isFinished, isTrue);
    expect(tagHidden(tester), isFalse);
  });

  testWidgets('content growth while open springs the surface to the new '
      'size and lands exactly; a shrink too', (WidgetTester tester) async {
    frame(tester);
    final ValueNotifier<int> count = ValueNotifier<int>(3);
    addTearDown(count.dispose);
    MorphFlight? flight;
    await tester.pumpWidget(
      _Host(
        onOpen: (BuildContext context) {
          flight = showMorphDialog(
            context,
            from: 'btn',
            width: _dialogWidth,
            fitContent: true,
            builder: (BuildContext context, MorphFlight flight) => rows(count),
          );
        },
      ),
    );
    await tester.tap(find.text('open-me'));
    await settle(tester);
    expect(flight!.lastTargetRect.height, 120);

    count.value = 6;
    // The rows relayout this frame; the measurement lands after it.
    await tester.pump();
    expect(flight!.measuredContentSize!.height, 240);
    expect(flight!.contentSize!.height, 120, reason: 'the spring starts here');
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 60));
    final double mid = flight!.lastTargetRect.height;
    expect(mid, greaterThan(120));
    expect(mid, lessThan(240));
    // Content at its natural size, the surface catching up: the last
    // row already exists and is laid out below the surface's edge.
    expect(find.text('row-5'), findsOneWidget);
    await settle(tester);
    expect(flight!.lastTargetRect.height, 240);
    expect(
      tester.getRect(find.text('row-5')).bottom,
      moreOrLessEquals(flight!.lastTargetRect.bottom),
    );

    count.value = 2;
    await tester.pump();
    // The first tick after a ticker start evaluates at t = 0.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 60));
    expect(flight!.lastTargetRect.height, lessThan(240));
    expect(flight!.lastTargetRect.height, greaterThan(80));
    await settle(tester);
    expect(flight!.lastTargetRect.height, 80);
    flight!.close();
    await settle(tester);
  });

  testWidgets('under reduced motion a size change rides the instant '
      'profile - short, critically damped, no cut', (
    WidgetTester tester,
  ) async {
    frame(tester);
    final ValueNotifier<int> count = ValueNotifier<int>(3);
    addTearDown(count.dispose);
    MorphFlight? flight;
    await tester.pumpWidget(
      _Host(
        reducedMotion: true,
        onOpen: (BuildContext context) {
          flight = showMorphDialog(
            context,
            from: 'btn',
            width: _dialogWidth,
            fitContent: true,
            builder: (BuildContext context, MorphFlight flight) => rows(count),
          );
        },
      ),
    );
    await tester.tap(find.text('open-me'));
    await settle(tester);
    expect(flight!.lastTargetRect.height, 120);
    count.value = 5;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 60));
    expect(flight!.lastTargetRect.height, greaterThan(120));
    expect(flight!.lastTargetRect.height, lessThan(200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(flight!.lastTargetRect.height, moreOrLessEquals(200, epsilon: 0.5));
    await settle(tester);
    expect(flight!.lastTargetRect.height, 200);
    flight!.close();
    await settle(tester);
  });

  testWidgets('a measured target keeps measuring on the settled route page', (
    WidgetTester tester,
  ) async {
    frame(tester);
    final ValueNotifier<int> count = ValueNotifier<int>(3);
    addTearDown(count.dispose);
    MorphFlight? flight;
    await tester.pumpWidget(
      _Host(
        onOpen: (BuildContext context) {
          showMorphRoute<void>(
            context,
            from: 'btn',
            target: MorphTargetSpec.dialog(
              width: _dialogWidth,
              fitContent: true,
            ),
            builder: (BuildContext context, MorphFlight f) {
              flight = f;
              return rows(count);
            },
          );
        },
      ),
    );
    await tester.tap(find.text('open-me'));
    await settle(tester);
    expect(flight!.routeOwnsContent.value, isTrue);
    expect(flight!.lastTargetRect.height, 120);
    count.value = 6;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 60));
    expect(flight!.lastTargetRect.height, greaterThan(120));
    expect(flight!.lastTargetRect.height, lessThan(240));
    await settle(tester);
    expect(flight!.lastTargetRect.height, 240);
    expect(
      tester.getRect(find.text('row-5')).bottom,
      moreOrLessEquals(flight!.lastTargetRect.bottom),
    );
    Navigator.of(tester.element(find.text('row-0'))).pop();
    await settle(tester);
    expect(find.text('row-0'), findsNothing);
  });

  testWidgets('repaint re-lays a fixed target without a spring tick', (
    WidgetTester tester,
  ) async {
    frame(tester);
    final ValueNotifier<double> top = ValueNotifier<double>(100);
    addTearDown(top.dispose);
    MorphFlight? flight;
    await tester.pumpWidget(
      _Host(
        onOpen: (BuildContext context) {
          flight = showMorph(
            context,
            from: 'btn',
            target: MorphTargetSpec(
              rectFor: (Size overlay, EdgeInsets padding) =>
                  Rect.fromLTWH(20, top.value, 200, 100),
              repaint: top,
            ),
            builder: (BuildContext context, MorphFlight flight) =>
                const Text('content'),
          );
        },
      ),
    );
    await tester.tap(find.text('open-me'));
    await settle(tester);
    expect(flight!.lastTargetRect.top, 100);
    expect(flight!.controller.isAnimating, isFalse);
    top.value = 300;
    await tester.pump();
    expect(flight!.lastTargetRect.top, 300);
    expect(tester.getTopLeft(find.text('content')).dy, 300);
    flight!.close();
    await settle(tester);
  });
}
