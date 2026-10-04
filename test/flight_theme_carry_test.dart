import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

void main() {
  Future<BuildContext> pumpPage(
    WidgetTester tester, {
    required ValueNotifier<MorphGlassPainter?> painter,
    List<MorphGlassPainter?>? ghost,
  }) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    BuildContext? source;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: ValueListenableBuilder<MorphGlassPainter?>(
          valueListenable: painter,
          builder: (BuildContext context, MorphGlassPainter? glass, _) {
            if (glass == null) return const SizedBox.shrink();
            return MorphGlass(
              painter: glass,
              child: Scaffold(
                body: Center(
                  child: MorphTag(
                    id: 'button',
                    child: Builder(
                      builder: (BuildContext context) {
                        source ??= context;
                        return MorphGlassButton(
                          onPressed: () {},
                          child: ghost == null
                              ? const Text('Open')
                              : _Probe(ghost, size: 24),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    return source!;
  }

  testWidgets('a dialog flight draws its ghost with the source page glass', (
    WidgetTester tester,
  ) async {
    final glass = _Recorder();
    final painter = ValueNotifier<MorphGlassPainter?>(glass);
    addTearDown(painter.dispose);
    final ghost = <MorphGlassPainter?>[];
    final source = await pumpPage(tester, painter: painter, ghost: ghost);
    expect(glass.outsideRoutes, 0);
    ghost.clear();
    showMorphDialog(
      source,
      from: 'button',
      builder: (BuildContext context, MorphFlight flight) =>
          const SizedBox.expand(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(glass.outsideRoutes, greaterThan(0));
    expect(ghost, isNotEmpty);
    expect(ghost, everyElement(same(glass)));
  });

  testWidgets('dialog content draws with the source glass', (
    WidgetTester tester,
  ) async {
    final glass = _Recorder();
    final painter = ValueNotifier<MorphGlassPainter?>(glass);
    addTearDown(painter.dispose);
    final seen = <MorphGlassPainter?>[];
    final source = await pumpPage(tester, painter: painter);
    showMorphDialog(
      source,
      from: 'button',
      builder: (BuildContext context, MorphFlight flight) => _Probe(seen),
    );
    await tester.pumpAndSettle();
    expect(seen, isNotEmpty);
    expect(seen, everyElement(same(glass)));
  });

  testWidgets('open dialog content follows a painter swap at its source', (
    WidgetTester tester,
  ) async {
    final glass = _Recorder();
    final painter = ValueNotifier<MorphGlassPainter?>(glass);
    addTearDown(painter.dispose);
    final seen = <MorphGlassPainter?>[];
    final source = await pumpPage(tester, painter: painter);
    showMorphDialog(
      source,
      from: 'button',
      builder: (BuildContext context, MorphFlight flight) => _Probe(seen),
    );
    await tester.pumpAndSettle();
    final swapped = _Recorder();
    painter.value = swapped;
    await tester.pump();
    await tester.pump();
    expect(seen.last, same(swapped));
  });

  testWidgets('dialog content keeps the last glass once the source is gone', (
    WidgetTester tester,
  ) async {
    final glass = _Recorder();
    final painter = ValueNotifier<MorphGlassPainter?>(glass);
    addTearDown(painter.dispose);
    final seen = <MorphGlassPainter?>[];
    final source = await pumpPage(tester, painter: painter);
    final flight = showMorphDialog(
      source,
      from: 'button',
      builder: (BuildContext context, MorphFlight flight) => _Probe(seen),
    );
    await tester.pumpAndSettle();
    painter.value = null;
    await tester.pump();
    await tester.pump();
    flight.markNeedsBuild();
    await tester.pump();
    expect(flight.isSourceLost, isTrue);
    expect(seen.last, same(glass));
    flight.close();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a morph route draws its ghost and page with the source glass', (
    WidgetTester tester,
  ) async {
    final glass = _Recorder();
    final painter = ValueNotifier<MorphGlassPainter?>(glass);
    addTearDown(painter.dispose);
    final ghost = <MorphGlassPainter?>[];
    final seen = <MorphGlassPainter?>[];
    final source = await pumpPage(tester, painter: painter, ghost: ghost);
    ghost.clear();
    final before = glass.inPopup;
    unawaited(
      showMorphRoute<void>(
        source,
        from: 'button',
        builder: (BuildContext context, MorphFlight flight) => _Probe(seen),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(glass.outsideRoutes, greaterThan(0));
    expect(ghost, isNotEmpty);
    expect(ghost, everyElement(same(glass)));
    await tester.pumpAndSettle();
    final flight = MorphScope.of(source).flightOf('button')!;
    expect(flight.routeOwnsContent.value, isTrue);
    expect(seen, isNotEmpty);
    expect(seen, everyElement(same(glass)));
    expect(glass.inPopup, before);
    Navigator.of(source).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('flight content takes the source theme, as popup routes do', (
    WidgetTester tester,
  ) async {
    final glass = _Recorder();
    final painter = ValueNotifier<MorphGlassPainter?>(glass);
    addTearDown(painter.dispose);
    BuildContext? source;
    Color? seen;
    final green = ThemeData(colorScheme: .fromSeed(seedColor: Colors.green));
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Theme(
          data: green,
          child: Center(
            child: MorphTag(
              id: 'button',
              child: Builder(
                builder: (BuildContext context) {
                  source ??= context;
                  return const SizedBox(width: 80, height: 40);
                },
              ),
            ),
          ),
        ),
      ),
    );
    showMorphDialog(
      source!,
      from: 'button',
      builder: (BuildContext context, MorphFlight flight) => Builder(
        builder: (BuildContext context) {
          seen = Theme.of(context).colorScheme.primary;
          return const SizedBox.expand();
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(seen, green.colorScheme.primary);
    expect(
      seen,
      isNot(
        Theme.of(tester.element(find.byType(Navigator))).colorScheme.primary,
      ),
    );
  });
}

class _Recorder extends MorphGlassPainter {
  int outsideRoutes = 0;
  int inPopup = 0;

  void _record(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null) {
      outsideRoutes++;
    } else if (route is PopupRoute<Object?>) {
      inPopup++;
    }
  }

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) {
    _record(context);
    return const SizedBox.expand();
  }

  @override
  Widget buildBody(
    BuildContext context,
    MorphGlassOutline outline,
    List<MorphGlassSurface> surfaces,
  ) {
    _record(context);
    return const SizedBox.expand();
  }
}

class _Probe extends StatelessWidget {
  const _Probe(this.seen, {this.size});

  final List<MorphGlassPainter?> seen;
  final double? size;

  @override
  Widget build(BuildContext context) {
    seen.add(MorphGlass.maybeOf(context));
    final size = this.size;
    return size == null
        ? const SizedBox.expand()
        : SizedBox(width: size, height: size);
  }
}
