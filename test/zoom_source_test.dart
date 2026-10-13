import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/widgets/navigation_stack.dart';
import 'package:morph/src/widgets/sheet.dart';
import 'package:morph/src/widgets/sheet_motion.dart';
import 'package:morph/src/widgets/zoom_source.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('zoom radius resolves the source $direction', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MorphScope(
          child: MaterialApp(
            builder: (_, child) =>
                Directionality(textDirection: direction, child: child!),
            home: Builder(
              builder: (c) {
                context = c;
                return const Center(
                  child: MorphTag(
                    id: 'source',
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadiusDirectional.only(
                        topStart: Radius.circular(8),
                        topEnd: Radius.circular(24),
                      ),
                    ),
                    child: SizedBox(width: 100, height: 80),
                  ),
                );
              },
            ),
          ),
        ),
      );
      final source = MorphZoomSource(MorphScope.of(context).tryTagOf('source'));
      expect(source.capture(context), isNotNull);
      expect(
        source.radius(const Size(100, 80)),
        direction == TextDirection.rtl ? 24 : 8,
      );
    });
  }

  testWidgets('a lost source freezes geometry and dissolves continuously', (
    tester,
  ) async {
    late BuildContext context;
    late StateSetter update;
    var show = true;
    await tester.pumpWidget(
      MorphScope(
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (c, setState) {
              context = c;
              update = setState;
              return Center(
                child: show
                    ? const MorphTag(
                        id: 'source',
                        child: SizedBox(width: 100, height: 80),
                      )
                    : const SizedBox(),
              );
            },
          ),
        ),
      ),
    );
    final source = MorphZoomSource(MorphScope.of(context).tryTagOf('source'));
    final rect = source.capture(context);
    source.hide();
    await tester.pump();
    update(() => show = false);
    await tester.pump();
    expect(source.capture(context), rect);
    expect(source.isLost, isTrue);
    expect(source.opacity(0.8, closing: true), 1);
    expect(source.opacity(0.6, closing: true), closeTo(0.5, 1e-10));
    expect(source.opacity(0.4, closing: true), 0);
    expect(source.opacity(0.8, closing: false), 1);
    source.reveal();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final sheet in [true, false]) {
    testWidgets(
      '${sheet ? 'sheet' : 'page'} dissolves after its source is removed',
      (tester) async {
        final nav = GlobalKey<NavigatorState>();
        late BuildContext context;
        late StateSetter update;
        var show = true;
        await tester.pumpWidget(
          MorphScope(
            child: MaterialApp(
              navigatorKey: nav,
              home: StatefulBuilder(
                builder: (c, setState) {
                  context = c;
                  update = setState;
                  return Center(
                    child: show
                        ? const MorphTag(
                            id: 'source',
                            child: SizedBox(
                              width: 100,
                              height: 80,
                              child: Text('replica'),
                            ),
                          )
                        : const SizedBox(),
                  );
                },
              ),
            ),
          ),
        );
        if (sheet) {
          unawaited(
            showMorphSheet<void>(
              context,
              from: 'source',
              detents: const [MorphSheetDetent.medium],
              builder: (_) => const Text('content'),
            ),
          );
        } else {
          final result = pushMorphZoom<void>(
            context,
            from: 'source',
            builder: (_) => const SizedBox.expand(child: Text('content')),
          );
          result.ignore();
        }
        await tester.pumpAndSettle();
        update(() => show = false);
        await tester.pump();
        await tester.pump();
        expect(find.text('content'), findsOneWidget);
        nav.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        final fades = tester.allRenderObjects.whereType<RenderOpacity>().map(
          (r) => r.opacity,
        );
        expect(fades.any((v) => v > 0 && v < 1), isTrue);
        expect(find.text('replica'), findsNothing);
        await tester.pumpAndSettle();
        expect(find.text('content'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('an open page drops its source replica and fades fully in', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MorphScope(
        child: MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const Center(
                child: MorphTag(
                  id: 'source',
                  child: SizedBox(width: 100, height: 80, child: Text('look')),
                ),
              );
            },
          ),
        ),
      ),
    );
    final result = pushMorphZoom<void>(
      context,
      from: 'source',
      builder: (_) => const SizedBox.expand(child: Text('content')),
    );
    result.ignore();
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.text('look', skipOffstage: false),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    final fades = <double>[];
    for (
      RenderObject? r = tester.renderObject(find.text('content'));
      r != null;
      r = r.parent
    ) {
      if (r is RenderOpacity) fades.add(r.opacity);
    }
    expect(fades, everyElement(1.0));
    expect(tester.takeException(), isNull);
  });

  for (final sheet in [true, false]) {
    testWidgets(
      '${sheet ? 'sheet' : 'page'} zoom fades its source look without '
      'rebuilding the crossfade',
      (tester) async {
        late BuildContext context;
        await tester.pumpWidget(
          MorphScope(
            child: MaterialApp(
              home: Builder(
                builder: (c) {
                  context = c;
                  return const Center(
                    child: MorphTag(
                      id: 'source',
                      child: SizedBox(
                        width: 100,
                        height: 80,
                        child: Text('look'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        final crossfade = sheet ? '_SheetZoomCrossfade' : '_ZoomCrossfade';
        var builds = 0;
        final previous = debugOnRebuildDirtyWidget;
        debugOnRebuildDirtyWidget = (Element e, bool _) {
          if (e.widget.runtimeType.toString() == crossfade) builds++;
        };
        addTearDown(() => debugOnRebuildDirtyWidget = previous);
        if (sheet) {
          unawaited(
            showMorphSheet<void>(
              context,
              from: 'source',
              detents: const [MorphSheetDetent.medium],
              builder: (_) => const Text('content'),
            ),
          );
        } else {
          pushMorphZoom<void>(
            context,
            from: 'source',
            builder: (_) => const SizedBox.expand(child: Text('content')),
          ).ignore();
        }
        await tester.pump();
        final looks = <double>{};
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          for (final r in tester.allRenderObjects.whereType<RenderOpacity>()) {
            if (r.opacity > 0 && r.opacity < 1) looks.add(r.opacity);
          }
        }
        await tester.pumpAndSettle();
        expect(looks.length, greaterThan(5));
        expect(builds, lessThanOrEqualTo(4));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final sheet in [true, false]) {
    testWidgets(
      '${sheet ? 'sheet' : 'page'} zoom replica takes a source rebuilt '
      'mid-close',
      (tester) async {
        final nav = GlobalKey<NavigatorState>();
        late BuildContext context;
        late StateSetter update;
        var label = 'before';
        await tester.pumpWidget(
          MorphScope(
            child: MaterialApp(
              navigatorKey: nav,
              home: StatefulBuilder(
                builder: (c, setState) {
                  context = c;
                  update = setState;
                  return Center(
                    child: MorphTag(
                      id: 'source',
                      child: SizedBox(
                        width: 100,
                        height: 80,
                        child: Text(label),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        if (sheet) {
          unawaited(
            showMorphSheet<void>(
              context,
              from: 'source',
              detents: const [MorphSheetDetent.medium],
              builder: (_) => const Text('content'),
            ),
          );
        } else {
          pushMorphZoom<void>(
            context,
            from: 'source',
            builder: (_) => const SizedBox.expand(child: Text('content')),
          ).ignore();
        }
        await tester.pumpAndSettle();
        nav.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        Finder replica(String text) => find.descendant(
          of: find.byType(FittedBox),
          matching: find.text(text, skipOffstage: false),
        );
        expect(replica('before'), findsOneWidget);
        update(() => label = 'after');
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        expect(replica('after'), findsOneWidget);
        expect(replica('before'), findsNothing);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
