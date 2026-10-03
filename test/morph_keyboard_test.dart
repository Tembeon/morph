import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

const double _keyboard = 300;

class _Host extends StatelessWidget {
  const _Host({required this.onOpen});

  final void Function(BuildContext context) onOpen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
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

/// Content that reports the keyboard inset it sees.
Widget probe(ValueChanged<double> onInsets) {
  return Builder(
    builder: (BuildContext context) {
      onInsets(MediaQuery.viewInsetsOf(context).bottom);
      return const Text('content');
    },
  );
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

void keyboard(WidgetTester tester, double height) {
  tester.view.viewInsets = FakeViewPadding(bottom: height);
}

void main() {
  testWidgets('a sheet docks above the keyboard and its content sees no '
      'keyboard', (WidgetTester tester) async {
    frame(tester);
    keyboard(tester, _keyboard);
    double? seen;
    MorphFlight? flight;
    await tester.pumpWidget(
      _Host(
        onOpen: (BuildContext context) {
          flight = showMorphSheet(
            context,
            from: 'btn',
            height: 200,
            builder: (BuildContext context, MorphFlight flight) =>
                probe((double v) => seen = v),
          );
        },
      ),
    );
    await tester.tap(find.text('open-me'));
    await settle(tester);
    expect(flight!.lastTargetRect.bottom, 600 - _keyboard - 14);
    expect(flight!.lastTargetRect.height, 200);
    expect(seen, 0);
    flight!.close();
    await settle(tester);
  });

  testWidgets('a dialog centers in the room the keyboard leaves and caps '
      'its fixed height to that room', (WidgetTester tester) async {
    frame(tester);
    keyboard(tester, _keyboard);
    double? seen;
    MorphFlight? flight;
    Future<void> open(double height) async {
      await tester.pumpWidget(
        _Host(
          onOpen: (BuildContext context) {
            flight = showMorphDialog(
              context,
              from: 'btn',
              width: 200,
              height: height,
              builder: (BuildContext context, MorphFlight flight) =>
                  probe((double v) => seen = v),
            );
          },
        ),
      );
      await tester.tap(find.text('open-me'));
      await settle(tester);
    }

    await open(200);
    expect(flight!.lastTargetRect.center.dy, (600 - _keyboard) / 2);
    expect(seen, 0);
    flight!.close();
    await settle(tester);

    // A requested 360 px cannot fit above the keyboard with 24 px margins,
    // so the fixed dialog caps at the available 252 px instead of handing
    // its content an avoidable keyboard overlap.
    await open(360);
    expect(flight!.lastTargetRect, const Rect.fromLTWH(100, 24, 200, 252));
    expect(seen, 0);
    flight!.close();
    await settle(tester);
  });

  testWidgets('a nested overlay receives only the keyboard strip that '
      'actually intersects it', (WidgetTester tester) async {
    frame(tester);
    keyboard(tester, _keyboard);
    double? seen;
    MorphFlight? flight;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: <Widget>[
              Positioned(
                left: 50,
                right: 50,
                top: 100,
                bottom: 100,
                child: Navigator(
                  onGenerateRoute: (RouteSettings settings) =>
                      MaterialPageRoute<void>(
                        settings: settings,
                        builder: (BuildContext context) => Center(
                          child: MorphTag(
                            id: 'nested-button',
                            child: Builder(
                              builder: (BuildContext context) => TextButton(
                                onPressed: () => flight = showMorphDialog(
                                  context,
                                  from: 'nested-button',
                                  width: 200,
                                  height: 120,
                                  builder:
                                      (
                                        BuildContext context,
                                        MorphFlight flight,
                                      ) => probe((double v) => seen = v),
                                ),
                                child: const Text('open-nested'),
                              ),
                            ),
                          ),
                        ),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-nested'));
    await settle(tester);

    // The overlay is global y=100..500 and the keyboard y=300..600:
    // only 200 px overlap it. The dialog therefore centers at local y=100,
    // global y=200. Raw window insets would incorrectly center it at 150.
    expect(flight!.lastTargetRect.center.dy, 100);
    expect(tester.getCenter(find.text('content')).dy, 200);
    expect(seen, 0);
    flight!.close();
    await settle(tester);
  });

  testWidgets('a fullscreen target ignores the keyboard and passes the '
      'insets through', (WidgetTester tester) async {
    frame(tester);
    keyboard(tester, _keyboard);
    double? seen;
    MorphFlight? flight;
    await tester.pumpWidget(
      _Host(
        onOpen: (BuildContext context) {
          flight = showMorph(
            context,
            from: 'btn',
            target: MorphTargetSpec.fullscreen(),
            builder: (BuildContext context, MorphFlight flight) =>
                probe((double v) => seen = v),
          );
        },
      ),
    );
    await tester.tap(find.text('open-me'));
    await settle(tester);
    expect(flight!.lastTargetRect, const Rect.fromLTWH(0, 0, 400, 600));
    expect(seen, _keyboard);
    flight!.close();
    await settle(tester);
  });

  testWidgets('the keyboard appearing under an open sheet moves it - the '
      'target is live', (WidgetTester tester) async {
    frame(tester);
    double? seen;
    MorphFlight? flight;
    await tester.pumpWidget(
      _Host(
        onOpen: (BuildContext context) {
          flight = showMorphSheet(
            context,
            from: 'btn',
            height: 200,
            builder: (BuildContext context, MorphFlight flight) =>
                probe((double v) => seen = v),
          );
        },
      ),
    );
    await tester.tap(find.text('open-me'));
    await settle(tester);
    expect(flight!.lastTargetRect.bottom, 600 - 14);
    keyboard(tester, _keyboard);
    await tester.pump();
    await tester.pump();
    expect(flight!.lastTargetRect.bottom, 600 - _keyboard - 14);
    expect(tester.getRect(find.text('content')).bottom, lessThan(300));
    expect(seen, 0);
    keyboard(tester, 0);
    await tester.pump();
    await tester.pump();
    expect(flight!.lastTargetRect.bottom, 600 - 14);
    flight!.close();
    await settle(tester);
  });

  testWidgets('the settled route page honors the keyboard the same way', (
    WidgetTester tester,
  ) async {
    frame(tester);
    double? seen;
    MorphFlight? flight;
    await tester.pumpWidget(
      _Host(
        onOpen: (BuildContext context) {
          showMorphRoute<void>(
            context,
            from: 'btn',
            target: MorphTargetSpec.sheet(height: 200),
            builder: (BuildContext context, MorphFlight f) {
              flight = f;
              return probe((double v) => seen = v);
            },
          );
        },
      ),
    );
    await tester.tap(find.text('open-me'));
    await settle(tester);
    expect(flight!.routeOwnsContent.value, isTrue);
    expect(flight!.lastTargetRect.bottom, 600 - 14);
    keyboard(tester, _keyboard);
    await tester.pump();
    await tester.pump();
    expect(flight!.lastTargetRect.bottom, 600 - _keyboard - 14);
    expect(seen, 0);
    Navigator.of(tester.element(find.text('content'))).pop();
    await settle(tester);
    expect(find.text('content'), findsNothing);
  });
}
