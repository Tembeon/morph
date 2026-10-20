import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';

final _link = MorphSourceLink();

Widget _app(Widget source) => MaterialApp(
  home: Scaffold(
    body: Stack(
      children: [
        Positioned(
          left: 131,
          top: 276,
          width: 140,
          height: 48,
          child: MorphSource(
            link: _link,
            shape: const StadiumBorder(),
            child: source,
          ),
        ),
      ],
    ),
  ),
);

Widget _sheet(BuildContext context) => const ColoredBox(
  key: ValueKey<String>('content'),
  color: Color(0xFF00C800),
);

/// The rendered aspect of the paragraph [finder] finds, or null while it
/// draws nothing.
double? _aspect(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return null;
  final rect = tester.getRect(finder);
  return rect.height > 0.5 ? rect.width / rect.height : null;
}

void main() {
  testWidgets('a sheet zooms out of a glass button and back without '
      'stretching the button', (WidgetTester tester) async {
    late BuildContext page;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (BuildContext context) {
            page = context;
            return MorphGlassButton(
              onPressed: () {},
              child: const Text('Source'),
            );
          },
        ),
      ),
    );
    final rest = _aspect(tester, find.text('Source'))!;
    unawaited(
      showMorphSheet<void>(
        page,
        from: _link,
        detents: const [MorphSheetDetent.medium],
        builder: _sheet,
      ),
    );
    final seen = <double>[];
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final element in find.text('Source').evaluate()) {
        final aspect = _aspect(tester, find.byWidget(element.widget).first);
        if (aspect != null) seen.add(aspect);
      }
    }
    expect(find.byKey(const ValueKey<String>('content')), findsOneWidget);
    Navigator.of(page).pop();
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final element in find.text('Source').evaluate()) {
        final aspect = _aspect(tester, find.byWidget(element.widget).first);
        if (aspect != null) seen.add(aspect);
      }
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('content')), findsNothing);
    expect(seen, isNotEmpty);
    for (final aspect in seen) {
      expect(
        aspect,
        closeTo(rest, rest * 0.02),
        reason: 'the look scales uniformly, as UIKit draws it',
      );
    }
    expect(_aspect(tester, find.text('Source')), closeTo(rest, 0.001));
  });

  testWidgets('the first frame of the zoom draws the source glass the '
      'source no longer draws', (WidgetTester tester) async {
    late BuildContext page;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (BuildContext context) {
            page = context;
            return MorphGlassButton(
              onPressed: () {},
              child: const Text('Source'),
            );
          },
        ),
      ),
    );
    unawaited(
      showMorphSheet<void>(
        page,
        from: _link,
        detents: const [MorphSheetDetent.medium],
        builder: _sheet,
      ),
    );
    await tester.pump();
    final zoom = find.byWidgetPredicate(
      (Widget widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == '_LiquidZoomFlatPainter',
    );
    expect(
      tester.renderObject(zoom),
      paints
        ..rsuperellipse()
        ..rrect(
          rrect: RRect.fromRectAndRadius(
            const Rect.fromLTWH(131, 276, 140, 48),
            const Radius.circular(24),
          ),
        ),
    );
  });
}
