import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

void main() {
  Widget host() {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const .all(24),
            child: MorphTag(
              id: 'player',
              shape: const RoundedRectangleBorder(
                borderRadius: .all(.circular(16)),
              ),
              surfaceColor: const Color(0xFF222222),
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showMorphDialog(
                    context,
                    from: 'player',
                    width: 400,
                    height: 400,
                    motion: .glacial,
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Padding(
                          padding: .all(40),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: MorphSharedElement(
                              id: 'cover',
                              child: SizedBox(
                                width: 200,
                                height: 200,
                                child: ColoredBox(
                                  color: Color(0xFF7C5CFF),
                                  child: Text('art'),
                                ),
                              ),
                            ),
                          ),
                        ),
                  ),
                  child: const Row(
                    mainAxisSize: .min,
                    children: <Widget>[
                      MorphSharedElement(
                        id: 'cover',
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: ColoredBox(
                            color: Color(0xFF7C5CFF),
                            child: Text('art'),
                          ),
                        ),
                      ),
                      Text('mini'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the cover flies between its endpoint rects', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    final Rect sourceCover = tester.getRect(
      find.byType(MorphSharedElement).first,
    );

    await tester.tap(find.text('mini'));
    await tester.pump();
    // Two glacial-flight frames in: the flying layer must exist and sit
    // between the endpoints, larger than the source and smaller than
    // the target.
    await tester.pump(const Duration(milliseconds: 300));
    final Finder flying = find.byKey(const ValueKey<Object>('cover'));
    expect(flying, findsOneWidget);
    final Rect mid = tester.getRect(flying);
    expect(mid.width, greaterThan(sourceCover.width));
    expect(mid.width, lessThan(200));
    expect(tester.takeException(), isNull);

    // Settle fully: the flying layer hands back to the real target
    // element.
    for (int i = 0; i < 600; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(flying, findsNothing);
    expect(tester.takeException(), isNull);

    // Close through to the latch and the end: no exceptions, the live
    // button is back with its marker rendered normally.
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    scope.flightOf('player')!.close();
    for (int i = 0; i < 900; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(tester.takeException(), isNull);
    expect(find.text('mini'), findsOneWidget);
  });

  testWidgets('fade none: the target side flies alone at full opacity', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Center(
            child: MorphTag(
              id: 'solo',
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showMorphDialog(
                    context,
                    from: 'solo',
                    width: 400,
                    height: 400,
                    motion: .glacial,
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Center(
                          child: MorphSharedElement(
                            id: 'badge',
                            child: SizedBox(
                              width: 180,
                              height: 60,
                              child: Text('badge-target'),
                            ),
                          ),
                        ),
                  ),
                  child: const MorphSharedElement(
                    id: 'badge',
                    // One side declaring no-fade covers the pair.
                    fade: .none,
                    child: SizedBox(
                      width: 90,
                      height: 30,
                      child: Text('badge-source'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('badge-source'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final Finder flying = find.byKey(const ValueKey<Object>('badge'));
    expect(flying, findsOneWidget);
    // Solo mode: only the TARGET copy rides the flying frame, at full
    // opacity for the whole flight - no fade-through dip.
    expect(
      find.descendant(of: flying, matching: find.text('badge-target')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: flying, matching: find.text('badge-source')),
      findsNothing,
    );
    final Opacity fader = tester.widget<Opacity>(
      find.descendant(of: flying, matching: find.byType(Opacity)).first,
    );
    expect(fader.opacity, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the launch never leaves the element visible nowhere', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.tap(find.text('mini'));

    // Frame by frame through the launch window: at EVERY frame the
    // element must be visible somewhere - as a live marker (the first
    // shuttle frame: the pair registers during its build but cannot
    // measure until its layout, so the ghost marker must stay
    // visible) or as the flying layer (every frame after). Markers
    // hiding on registration alone left the element nowhere for one
    // frame - a blink on every launch.
    for (int f = 0; f < 4; f++) {
      await tester.pump(const Duration(milliseconds: 8));
      double best = 0;
      for (final Element e in find.text('art').evaluate()) {
        double opacity = 1;
        e.visitAncestorElements((Element ancestor) {
          final Widget w = ancestor.widget;
          if (w is Opacity) {
            opacity *= w.opacity;
          }
          if (w is FadeTransition) {
            opacity *= w.opacity.value;
          }
          return true;
        });
        if (opacity > best) {
          best = opacity;
        }
      }
      expect(
        best,
        greaterThan(0.9),
        reason: 'frame $f: the shared element vanished from every copy',
      );
    }
    // And the handoff is real: by now the flying layer owns the
    // element.
    expect(find.byKey(const ValueKey<Object>('cover')), findsOneWidget);

    for (int i = 0; i < 600; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unpaired id degrades to plain rendering', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Center(
            child: MorphTag(
              id: 'solo',
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showMorphDialog(
                    context,
                    from: 'solo',
                    builder: (BuildContext context, MorphFlight flight) =>
                        const MorphSharedElement(
                          id: 'orphan',
                          child: Text('alone'),
                        ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    for (int i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(find.byKey(const ValueKey<Object>('orphan')), findsNothing);
    expect(find.text('alone'), findsOneWidget);
  });
}
