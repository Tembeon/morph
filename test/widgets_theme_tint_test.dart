import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as material;
import 'package:morph/widgets.dart';

const _tint = Color(0xFFFF2D55);

typedef _Resolved = ({
  MorphSliderAppearance slider,
  MorphProgressViewAppearance progress,
  MorphTabBarAppearance tabBar,
  MorphBarAppearance bar,
  MorphDatePickerAppearance datePicker,
  MorphAlertAppearance alert,
  MorphListAppearance list,
  MorphGlassButtonAppearance glassButton,
});

_Resolved _resolve(BuildContext context) => (
  slider: MorphSliderAppearance.resolve(context, null),
  progress: MorphProgressViewAppearance.resolve(context, null),
  tabBar: MorphTabBarAppearance.resolve(context, null),
  bar: MorphBarAppearance.resolve(context, null),
  datePicker: MorphDatePickerAppearance.resolve(context, null),
  alert: MorphAlertAppearance.resolve(context, null),
  list: MorphListAppearance.resolve(context, null),
  glassButton: MorphGlassButtonAppearance.resolve(context, null),
);

Widget _probe(void Function(BuildContext context) read) => Builder(
  builder: (context) {
    read(context);
    return const SizedBox();
  },
);

void main() {
  testWidgets('the theme tint replaces every built-in accent', (tester) async {
    late _Resolved r;
    await tester.pumpWidget(
      MorphWidgetsThemeScope(
        data: const MorphWidgetsTheme(tint: _tint),
        child: _probe((context) => r = _resolve(context)),
      ),
    );
    expect(r.slider.activeTrackColor, _tint);
    expect(r.progress.activeTrackColor, _tint);
    expect(r.tabBar.selectedColor, _tint);
    expect(r.bar.prominentColor, _tint);
    expect(r.datePicker.accentColor, _tint);
    expect(
      r.datePicker.todayFillColor,
      _tint.withValues(alpha: MorphDatePickerAppearance.light.todayFillColor.a),
    );
    expect(r.alert.preferredColor, _tint);
    expect(r.list.iconColor, _tint);
    expect(r.glassButton.prominentColor, _tint);
    expect(
      r.slider.inactiveTrackColor,
      MorphSliderAppearance.light.inactiveTrackColor,
    );
  });

  testWidgets('without a tint the tables are the measured ones', (
    tester,
  ) async {
    late _Resolved r;
    await tester.pumpWidget(
      MorphWidgetsThemeScope(
        data: const MorphWidgetsTheme(),
        child: _probe((context) => r = _resolve(context)),
      ),
    );
    expect(r.slider, same(MorphSliderAppearance.light));
    expect(r.tabBar, same(MorphTabBarAppearance.light));
    expect(r.alert, same(MorphAlertAppearance.light));
  });

  testWidgets('a tinted table is shared while the tint holds', (tester) async {
    final seen = <MorphSliderAppearance>[];
    Widget scene(int n) => MorphWidgetsThemeScope(
      key: ValueKey(n),
      data: const MorphWidgetsTheme(tint: _tint),
      child: _probe(
        (context) => seen.add(MorphSliderAppearance.resolve(context, null)),
      ),
    );
    await tester.pumpWidget(scene(0));
    await tester.pumpWidget(scene(1));
    expect(seen, hasLength(2));
    expect(seen.first, same(seen.last));
  });

  testWidgets('an appearance and an explicit color win over the tint', (
    tester,
  ) async {
    const own = MorphSliderAppearance(activeTrackColor: Color(0xFF00FF00));
    late MorphSliderAppearance themed;
    late MorphSliderAppearance explicit;
    await tester.pumpWidget(
      MorphWidgetsThemeScope(
        data: const MorphWidgetsTheme(tint: _tint, slider: own),
        child: _probe((context) {
          themed = MorphSliderAppearance.resolve(context, null);
          explicit = MorphSliderAppearance.resolve(
            context,
            MorphSliderAppearance.dark,
          );
        }),
      ),
    );
    expect(themed, same(own));
    expect(explicit, same(MorphSliderAppearance.dark));
  });

  testWidgets('the nearer of a scope and a Material theme wins', (
    tester,
  ) async {
    const scoped = Color(0xFF111111);
    const themed = Color(0xFF222222);
    late MorphSliderAppearance inner;
    late MorphSliderAppearance outer;
    late MorphSliderAppearance bare;
    await tester.pumpWidget(
      MorphWidgetsThemeScope(
        data: const MorphWidgetsTheme(tint: scoped),
        child: Column(
          children: [
            material.Theme(
              data: material.ThemeData.light().copyWith(
                extensions: const [MorphWidgetsTheme(tint: themed)],
              ),
              child: _probe(
                (context) =>
                    inner = MorphSliderAppearance.resolve(context, null),
              ),
            ),
            material.Theme(
              data: material.ThemeData.light(),
              child: _probe(
                (context) =>
                    bare = MorphSliderAppearance.resolve(context, null),
              ),
            ),
            _probe(
              (context) => outer = MorphSliderAppearance.resolve(context, null),
            ),
          ],
        ),
      ),
    );
    expect(inner.activeTrackColor, themed);
    expect(bare.activeTrackColor, scoped);
    expect(outer.activeTrackColor, scoped);
  });

  testWidgets('the slider paints the ambient tint', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MorphWidgetsThemeScope(
          data: const MorphWidgetsTheme(tint: _tint),
          child: Center(
            child: SizedBox(
              width: 200,
              child: MorphSlider(value: 0.5, onChanged: (_) {}),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('lerp blends the tint', () {
    const a = MorphWidgetsTheme(tint: Color(0xFF000000));
    const b = MorphWidgetsTheme(tint: Color(0xFFFFFFFF));
    expect(a.lerp(b, 0.5).tint, Color.lerp(a.tint, b.tint, 0.5));
    expect(a.lerp(b, 0).tint, a.tint);
  });
}
