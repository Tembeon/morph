import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show Icons;
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';

/// The widgets theme: an accent over every accented control, per-control
/// looks, high contrast, reduced motion and haptics.
///
/// The page installs its own [MorphTheme] over the gallery's
/// theme, so its accent and haptics stay on this page. Increase Contrast
/// and Reduce Motion are shown side by side with the standard controls by
/// overriding [MediaQueryData.highContrast] and
/// [MediaQueryData.disableAnimations] for one column.
class ThemingPage extends StatefulWidget {
  /// Creates the page.
  const ThemingPage({super.key});

  @override
  State<ThemingPage> createState() => _ThemingPageState();
}

class _ThemingPageState extends State<ThemingPage> {
  Color? _accent = galleryAccentColors[1].$2;
  bool? _haptics;
  bool _ownLooks = true;
  bool? _appleMetrics;

  bool _on = true;
  double _value = 0.6;
  int _segment = 0;
  int _tab = 0;
  int _page = 1;
  double _count = 2;
  DateTime _date = DateTime(2026, 10, 14);

  static const _metrics = <bool?, String>{
    null: 'Platform',
    true: 'Apple',
    false: 'Plain',
  };

  static const _specimen = <(String, TextStyle)>[
    ('Large title', MorphTypography.largeTitle),
    ('Title', MorphTypography.title),
    ('Body', MorphTypography.body),
    ('Button', MorphTypography.button),
    ('Bar button', MorphTypography.barButton),
    ('Menu item', MorphTypography.menuItem),
    ('Alert title', MorphTypography.alertTitle),
    ('Alert message', MorphTypography.alertMessage),
    ('Search field', MorphTypography.searchField),
    ('List subtitle', MorphTypography.listSubtitle),
    ('Segment', MorphTypography.segment),
    ('Footer', MorphTypography.listFooter),
    ('Tab label', MorphTypography.tabLabel),
  ];

  List<Widget> _options(BuildContext context) {
    final ambient = MorphTheme.maybeOf(context);
    return [
      MorphListSection(
        header: const Text('Theme scope'),
        footer: const Text(
          'A MorphTheme over this page replaces the gallery '
          'theme here: its accent tints every accented control, and its '
          'haptics switch silences them.',
        ),
        children: [
          GalleryColorChoice(
            label: 'Accent',
            value: _accent,
            onChanged: (Color? c) => setState(() => _accent = c),
          ),
          GalleryToggle(
            label: 'Haptics',
            value: _haptics ?? ambient?.haptics ?? true,
            onChanged: (bool v) => setState(() => _haptics = v),
          ),
        ],
      ),
      MorphListSection(
        header: const Text('Looks'),
        children: [
          GalleryToggle(
            label: 'Own appearances',
            value: _ownLooks,
            onChanged: (bool v) => setState(() => _ownLooks = v),
          ),
          GalleryChoice<bool?>(
            label: 'Metrics',
            options: _metrics,
            value: _appleMetrics,
            onChanged: (bool? v) => setState(() => _appleMetrics = v),
          ),
        ],
      ),
    ];
  }

  MorphThemeData _theme(BuildContext context) =>
      MorphTheme.of(context).copyWith(tint: _accent, haptics: _haptics);

  Widget _card(BuildContext context, Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: galleryCardColor(context),
      borderRadius: const .all(.circular(26)),
    ),
    child: Padding(padding: const .all(16), child: child),
  );

  Widget _accented(BuildContext context) {
    T? on<T extends Function>(T callback) =>
        GalleryGlassScope.enabled(context, callback);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        _card(
          context,
          Column(
            crossAxisAlignment: .stretch,
            children: [
              MorphSlider(
                value: _value,
                semanticLabel: 'Accent slider',
                onChanged: on((double v) => setState(() => _value = v)),
              ),
              const SizedBox(height: 16),
              MorphProgressView(value: _value, semanticLabel: 'Progress'),
              const SizedBox(height: 16),
              Wrap(
                alignment: .spaceBetween,
                crossAxisAlignment: .center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  MorphGlassButton.prominent(
                    onPressed: on(() {}),
                    child: const Text('Accent button'),
                  ),
                  MorphDatePicker(
                    value: _date,
                    onChanged: on((DateTime d) => setState(() => _date = d)),
                    semanticLabel: 'Accent date',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Builder(
                builder: (BuildContext context) => SizedBox(
                  height: 44,
                  child: MorphGlassButton(
                    onPressed: on(
                      () => showMorphAlert(
                        context,
                        title: 'Keep the accent?',
                        message: 'The preferred action takes the accent.',
                        actions: const [
                          MorphAlertAction(title: 'Undo', style: .cancel),
                          MorphAlertAction(title: 'Keep', isPreferred: true),
                        ],
                      ),
                    ),
                    child: const Text('Alert with the accent'),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        MorphTabBar(
          items: const [
            MorphTabItem(icon: Icons.palette_outlined, label: 'Colors'),
            MorphTabItem(icon: Icons.text_fields, label: 'Type'),
            MorphTabItem(icon: Icons.contrast, label: 'Contrast'),
          ],
          selected: _tab,
          onChanged: on((int i) => setState(() => _tab = i)),
        ),
        const SizedBox(height: 8),
        const MorphListSection(
          children: [
            MorphListRow(
              leading: Icon(Icons.brush_outlined),
              title: Text('A row icon takes the accent'),
              accessory: .checkmark,
            ),
          ],
        ),
      ],
    );
  }

  Widget _ownAppearances(BuildContext context) {
    T? on<T extends Function>(T callback) =>
        GalleryGlassScope.enabled(context, callback);
    const orange = Color(0xFFFF9500);
    const pink = Color(0xFFFF2D55);
    final own = _ownLooks;
    final switchBase = MorphSwitchAppearance.resolve(context, null);
    return _card(
      context,
      Column(
        crossAxisAlignment: .stretch,
        children: [
          Row(
            children: [
              MorphSwitch(
                value: _on,
                semanticLabel: 'Own switch',
                appearance: own
                    ? MorphSwitchAppearance(
                        activeTrackColor: orange,
                        inactiveTrackColor: switchBase.inactiveTrackColor,
                        thumbColor: switchBase.thumbColor,
                        disabledOpacity: switchBase.disabledOpacity,
                      )
                    : null,
                onChanged: on((bool v) => setState(() => _on = v)),
              ),
              const Spacer(),
              MorphGlassButton.prominent(
                onPressed: on(() {}),
                appearance: own
                    ? MorphGlassButtonAppearance.resolve(
                        context,
                        null,
                      ).copyWith(prominentColor: pink)
                    : null,
                child: const Text('Pink'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          MorphSlider(
            value: _value,
            semanticLabel: 'Own slider',
            appearance: own
                ? MorphSliderAppearance.resolve(
                    context,
                    null,
                  ).copyWith(activeTrackColor: orange)
                : null,
            onChanged: on((double v) => setState(() => _value = v)),
          ),
          const SizedBox(height: 16),
          MorphProgressView(
            value: _value,
            semanticLabel: 'Own progress',
            appearance: own
                ? MorphProgressViewAppearance.resolve(
                    context,
                    null,
                  ).copyWith(activeTrackColor: pink)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _column(String label, List<Widget> children) => Expanded(
    child: Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(label, style: const TextStyle(fontWeight: .w600)),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );

  List<Widget> _sample(BuildContext context, String name) {
    T? on<T extends Function>(T callback) =>
        GalleryGlassScope.enabled(context, callback);
    return [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: MorphSwitch(
          value: _on,
          semanticLabel: '$name switch',
          onChanged: on((bool v) => setState(() => _on = v)),
        ),
      ),
      const SizedBox(height: 14),
      MorphSegmentedControl(
        segments: const [MorphSegment('One'), MorphSegment('Two')],
        selectedIndex: _segment,
        onChanged: on((int i) => setState(() => _segment = i)),
      ),
      const SizedBox(height: 14),
      MorphSlider(
        value: _value,
        semanticLabel: '$name slider',
        onChanged: on((double v) => setState(() => _value = v)),
      ),
      const SizedBox(height: 14),
      MorphProgressView(value: _value, semanticLabel: '$name progress'),
      const SizedBox(height: 14),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: MorphStepper(
          value: _count,
          max: 9,
          decrementLabel: '$name decrement',
          incrementLabel: '$name increment',
          onChanged: on((double v) => setState(() => _count = v)),
        ),
      ),
      const SizedBox(height: 14),
      Center(
        child: MorphPageControl(
          count: 4,
          page: _page,
          semanticLabel: '$name pages',
          onChanged: on((int i) => setState(() => _page = i)),
        ),
      ),
    ];
  }

  Widget _sideBySide(
    BuildContext context, {
    required String label,
    required MediaQueryData Function(MediaQueryData) change,
  }) {
    final media = MediaQuery.of(context);
    final standard = media.copyWith(
      highContrast: false,
      disableAnimations: false,
    );
    return _card(
      context,
      Row(
        crossAxisAlignment: .start,
        children: [
          MediaQuery(
            data: standard,
            child: Builder(
              builder: (BuildContext context) =>
                  _column('Standard', _sample(context, 'Standard')),
            ),
          ),
          const SizedBox(width: 16),
          MediaQuery(
            data: change(standard),
            child: Builder(
              builder: (BuildContext context) =>
                  _column(label, _sample(context, label)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typography(BuildContext context) {
    final look = MorphListAppearance.resolve(context, null);
    return MorphListSection(
      header: const Text('MorphTypography'),
      footer: const Text(
        'Apple metrics add the optical size, the weight axis and SF '
        'tracking CoreText applies to the system font; Platform picks them '
        'on iOS and macOS only.',
      ),
      children: [
        for (final (name, style) in _specimen)
          MorphListRow(
            title: Text(
              name,
              style: MorphTypography.resolve(
                style.copyWith(color: look.titleColor),
                apple: _appleMetrics,
              ),
            ),
            detail: Text(
              '${style.fontSize!.round()} pt '
              '${(MorphTypography.weightAxis(style.fontWeight!) ?? style.fontWeight!.value).round()}',
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MorphTheme(
      data: _theme(context),
      child: Builder(
        builder: (BuildContext context) => GalleryPage(
          title: 'Theming',
          options: _options,
          slivers: [
            SliverPadding(
              padding: const .fromLTRB(16, 0, 16, 0),
              sliver: SliverList.list(
                children: [
                  const GalleryCaption('Accent from the theme scope'),
                  _accented(context),
                  const GalleryCaption('Each control with its own appearance'),
                  _ownAppearances(context),
                  const GalleryCaption('Increase Contrast, side by side'),
                  _sideBySide(
                    context,
                    label: 'High contrast',
                    change: (MediaQueryData m) =>
                        m.copyWith(highContrast: true),
                  ),
                  const GalleryCaption('Reduce Motion, side by side'),
                  _sideBySide(
                    context,
                    label: 'Reduced',
                    change: (MediaQueryData m) =>
                        m.copyWith(disableAnimations: true),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(child: _typography(context)),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}
