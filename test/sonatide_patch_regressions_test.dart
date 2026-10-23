import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';

Widget _app(Widget child) => WidgetsApp(
  color: const Color(0xFF007AFF),
  pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
  ),
  home: Center(child: child),
);

void main() {
  for (final scrolling in [false, true]) {
    testWidgets('550 ms hold starts at contact inside scroll=$scrolling', (
      tester,
    ) async {
      var holds = 0;
      var taps = 0;
      var active = false;
      final target = MorphTouchTarget(
        onTap: () => taps++,
        onLongPress: () => holds++,
        builder: (context, state, child) {
          active = state.active;
          return child!;
        },
        child: const SizedBox(width: 140, height: 60),
      );
      await tester.pumpWidget(
        _app(
          scrolling
              ? ListView(children: [target, const SizedBox(height: 1600)])
              : target,
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MorphTouchTarget)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(active, !scrolling);
      await tester.pump(const Duration(milliseconds: 50));
      expect(active, isTrue);
      expect(holds, 0);
      await tester.pump(const Duration(milliseconds: 340));
      expect(holds, 0);
      await tester.pump(const Duration(milliseconds: 60));
      expect(holds, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(holds, 1);
      expect(taps, 0);
    });
  }

  for (final selected in <int?>[0, null]) {
    testWidgets('disabling preview cancels once with selection=$selected', (
      tester,
    ) async {
      var enabled = true;
      var cancels = 0;
      var activations = 0;
      int? preview;
      late StateSetter update;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SizedBox(
                width: 300,
                child: MorphSegmentedControl(
                  segments: [
                    const MorphSegment('A'),
                    MorphSegment('B', enabled: enabled),
                  ],
                  selectedIndex: selected,
                  onChanged: null,
                  onActivated: (_) => activations++,
                  onPreviewChanged: (index) => setState(() => preview = index),
                  onPreviewCancelled: () => setState(() => cancels++),
                ),
              );
            },
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('B')),
      );
      await tester.pump();
      expect(preview, 1);
      update(() => enabled = false);
      await tester.pump();
      expect(preview, isNull);
      expect(cancels, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(activations, 0);
      expect(cancels, 1);
      expect(tester.takeException(), isNull);

      update(() => enabled = true);
      await tester.pump();
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(preview, isNull);
      expect(activations, 1);
      expect(cancels, 1);
    });
  }
}
