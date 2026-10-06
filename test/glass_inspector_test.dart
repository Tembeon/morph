import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/internal/backdrop_capture_debug.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/widgets.dart';

Widget _button(double left, String label) => Positioned(
  left: left,
  top: 40,
  width: 80,
  height: 44,
  child: MorphGlassButton(onPressed: () {}, child: Text(label)),
);

Widget _app(Widget scene, {bool inspector = false, bool enabled = true}) {
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(platform: TargetPlatform.iOS, brightness: .dark),
    home: MorphAdaptiveGlass(
      tier: MorphGlassTier.fake,
      child: ColoredBox(color: const Color(0xFF406080), child: scene),
    ),
  );
  return inspector ? MorphGlassInspector(enabled: enabled, child: app) : app;
}

Widget _row({bool container = false, bool clipped = false}) {
  Widget buttons = Stack(
    children: [for (var i = 0; i < 4; i++) _button(20 + i * 90.0, '$i')],
  );
  if (clipped) buttons = ClipRRect(child: buttons);
  return container ? MorphGlassContainer(child: buttons) : buttons;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() => isLocalTest = true);
  tearDownAll(() => isLocalTest = false);

  testWidgets('separate resting buttons: one filter each and a hint to '
      'group them', (WidgetTester tester) async {
    await tester.pumpWidget(_app(_row()));
    await _settle(tester);
    final census = MorphGlassInspector.census();
    expect(census.filters, 4);
    expect(census.owners.values.fold(0, (int a, int b) => a + b), 4);
    expect(census.owners.keys.single, contains('MorphGlassButton'));
    expect(census.hints, hasLength(1));
    expect(census.hints.single.layers, 4);
    expect(census.hints.single.saves, 3);
    expect(census.hints.single.keptOutBy, isNull);
    expect(census.hints.single.where, startsWith('Stack'));
  });

  testWidgets('the same buttons in a container: one filter, no hint', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_row(container: true)));
    await _settle(tester);
    final census = MorphGlassInspector.census();
    expect(census.filters, 1);
    expect(census.owners.keys.single, contains('MorphGlassContainer'));
    expect(census.hints, isEmpty);
  });

  testWidgets('a clip between a container and its buttons is named', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_row(container: true, clipped: true)));
    await _settle(tester);
    final census = MorphGlassInspector.census();
    expect(census.filters, 4);
    expect(census.hints, hasLength(1));
    expect(census.hints.single.keptOutBy, 'ClipRRect');
    expect(census.hints.single.layers, 4);
    expect(census.hints.single.where, startsWith('MorphGlassContainer'));
  });

  testWidgets('a container around a scroll view joins nothing in it: the '
      'viewport keeps the buttons out', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        MorphGlassContainer(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: 200, child: _row())),
            ],
          ),
        ),
      ),
    );
    await _settle(tester);
    final census = MorphGlassInspector.census();
    expect(census.filters, 4);
    expect(census.hints.single.keptOutBy, 'Viewport');
  });

  testWidgets('a list section shades its rows\' buttons in one layer', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        MorphListSection(
          children: [
            for (var i = 0; i < 3; i++)
              MorphListRow(
                title: Text('Row $i'),
                trailing: SizedBox(
                  width: 72,
                  height: 34,
                  child: MorphGlassButton(onPressed: () {}, child: Text('$i')),
                ),
              ),
          ],
        ),
      ),
    );
    await _settle(tester);
    final census = MorphGlassInspector.census();
    expect(census.filters, 1);
    expect(census.owners.keys.single, contains('MorphListSection'));
    expect(census.hints, isEmpty);
  });

  testWidgets('a pressed button gets no hint: only resting glass joins', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(Stack(children: [_button(20, 'a'), _button(120, 'b')])),
    );
    await _settle(tester);
    expect(MorphGlassInspector.census().hints, hasLength(1));
    final gesture = await tester.startGesture(const Offset(60, 62));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(MorphGlassInspector.census().hints, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the overlay shows the counts and the hint, and follows them', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_row(), inspector: true));
    await _settle(tester);
    expect(find.textContaining('glass: 4 filters'), findsOneWidget);
    expect(
      find.textContaining('could share one MorphGlassContainer'),
      findsOneWidget,
    );
    await tester.pumpWidget(_app(_row(container: true), inspector: true));
    await _settle(tester);
    expect(find.textContaining('glass: 1 filters'), findsOneWidget);
    expect(find.textContaining('hint:'), findsNothing);
  });

  testWidgets('a settled overlay schedules no frames', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_row(), inspector: true));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a disabled inspector builds its child alone and leaves the '
      'owner registry as it found it', (WidgetTester tester) async {
    expect(GlassLayerOwners.owners, isNull);
    await tester.pumpWidget(_app(_row(), inspector: true, enabled: false));
    await _settle(tester);
    expect(find.textContaining('glass:'), findsNothing);
    final inspector = tester.element(find.byType(MorphGlassInspector));
    Widget? child;
    inspector.visitChildren((Element e) => child = e.widget);
    expect(child, isA<MaterialApp>());
    expect(GlassLayerOwners.owners, isNull);
    await tester.pumpWidget(_app(_row(), inspector: true));
    await _settle(tester);
    expect(GlassLayerOwners.owners, isNotNull);
    await tester.pumpWidget(const SizedBox());
    expect(GlassLayerOwners.owners, isNull);
  });
}
