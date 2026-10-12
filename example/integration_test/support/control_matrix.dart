/// The control matrix: every control alone on one fixed page, every action
/// timed in a window of its own, so a bench names what one control costs in
/// one action instead of what a whole gallery page costs.
///
/// Scene names are `m/<control>/<action>`; `m/empty/frames` is the floor:
/// the same page drawing frames with no control on it. Select cells with the
/// audit's scene filter (`AUDIT_SCENES=m/sheet/*,m/empty/*`).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// What a matrix action needs from the audit that runs it.
abstract interface class MatrixDriver {
  /// The tester that drives the app.
  WidgetTester get tester;

  /// Pumps frames for [ms] milliseconds.
  Future<void> settle([int ms]);

  /// A finger down at [from], moved along [path], then lifted.
  Future<void> finger(Offset from, List<Offset> path, {Duration holdBefore});

  /// A tap at [at].
  Future<void> tap(Offset at);

  /// Times [body] as the scene [name], with the audit's repeats.
  Future<void> measure(String name, Future<void> Function() body);
}

/// One control of the matrix and its timed actions.
class MatrixControl {
  /// Creates a control named [name], built by [build], timed in [actions].
  const MatrixControl(this.name, this.build, this.actions);

  /// The scene segment after `m/`.
  final String name;

  /// Builds the control; null for a presentation the actions open.
  final Widget Function()? build;

  /// The timed actions by name; each leaves the control as it found it.
  final Map<String, Future<void> Function(MatrixDriver driver)> actions;
}

/// The page every cell is shown on: still content under the control, so
/// glass reads the same backdrop in every cell.
class MatrixStage extends StatefulWidget {
  /// Creates the stage.
  const MatrixStage({super.key});

  /// The control on the stage; null shows the bare page.
  static final ValueNotifier<Widget?> control = ValueNotifier(null);

  /// Whether the floor ticker draws a frame every vsync (the empty cell's
  /// frames).
  static final ValueNotifier<bool> ticking = ValueNotifier(false);

  /// A context inside the stage, for presenting sheets and alerts.
  static BuildContext? context;

  @override
  State<MatrixStage> createState() => _MatrixStageState();
}

class _MatrixStageState extends State<MatrixStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floor = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void initState() {
    super.initState();
    MatrixStage.ticking.addListener(_tick);
  }

  void _tick() {
    if (MatrixStage.ticking.value) {
      _floor.repeat();
    } else {
      _floor.stop();
    }
  }

  @override
  void dispose() {
    MatrixStage.ticking.removeListener(_tick);
    _floor.dispose();
    MatrixStage.context = null;
    super.dispose();
  }

  static const List<Color> _stripes = [
    Color(0xFF1E5AA8),
    Color(0xFFE0A030),
    Color(0xFF2E8B57),
    Color(0xFFC03A4A),
    Color(0xFF6A4FB0),
    Color(0xFFDDDDDD),
  ];

  @override
  Widget build(BuildContext context) {
    MatrixStage.context = context;
    // The page sits straight under the app, with no Material: its text
    // takes an explicit style instead of the framework's fallback.
    return DefaultTextStyle(
      style: const TextStyle(
        color: Color(0xFF000000),
        fontSize: 15,
        decoration: TextDecoration.none,
      ),
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                for (var i = 0; i < 24; i++)
                  Expanded(
                    child: ColoredBox(
                      color: _stripes[i % _stripes.length],
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Text('Row $i - the page under the control'),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // One device pixel the floor ticker repaints: frames with nothing
            // else on them.
            Positioned(
              left: 0,
              top: 0,
              width: 1,
              height: 1,
              child: FadeTransition(
                opacity: _floor,
                child: const ColoredBox(color: Color(0xFF000000)),
              ),
            ),
            Center(
              child: ValueListenableBuilder<Widget?>(
                valueListenable: MatrixStage.control,
                builder: (BuildContext context, Widget? control, Widget? _) =>
                    control ?? const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A control that keeps its own value, as an app would.
class _Holder<T> extends StatefulWidget {
  const _Holder(this.initial, this.build);

  final T initial;
  final Widget Function(T value, ValueChanged<T> onChanged) build;

  @override
  State<_Holder<T>> createState() => _HolderState<T>();
}

class _HolderState<T> extends State<_Holder<T>> {
  late T _value = widget.initial;

  @override
  Widget build(BuildContext context) =>
      widget.build(_value, (T v) => setState(() => _value = v));
}

MorphBarButton _barIcon(String id) => MorphBarButton(
  id: id,
  icon: const SizedBox.square(dimension: 24),
  semanticLabel: id,
  onPressed: () {},
);

Rect _rectOf(MatrixDriver d, Finder finder) => d.tester.getRect(finder.first);

List<Offset> _line(Offset a, Offset b, int n) => [
  for (var i = 1; i <= n; i++) Offset.lerp(a, b, i / n)!,
];

Offset _textCenter(MatrixDriver d, Type type, String text) =>
    d.tester.getCenter(
      find.descendant(of: find.byType(type), matching: find.text(text)).first,
    );

/// Every control of the matrix, the empty floor first.
final List<MatrixControl> matrixControls = [
  MatrixControl('empty', null, {
    'frames': (d) async {
      MatrixStage.ticking.value = true;
      await d.settle(1500);
      MatrixStage.ticking.value = false;
    },
  }),
  MatrixControl(
    'glass-button',
    () => SizedBox(
      width: 160,
      height: 48,
      child: MorphGlassButton(onPressed: () {}, child: const Text('Button')),
    ),
    {
      'tap': (d) async {
        await d.tap(d.tester.getCenter(find.byType(MorphGlassButton)));
        await d.settle(900);
      },
      'press-drag': (d) async {
        final c = d.tester.getCenter(find.byType(MorphGlassButton));
        await d.finger(c, _line(c, c + const Offset(60, 20), 30));
        await d.settle(900);
      },
    },
  ),
  MatrixControl(
    'segmented',
    () => SizedBox(
      width: 300,
      child: _Holder<int>(
        0,
        (v, set) => MorphSegmentedControl(
          segments: const ['One', 'Two', 'Three'],
          selected: v,
          onChanged: set,
        ),
      ),
    ),
    {
      'tap': (d) async {
        await d.tap(_textCenter(d, MorphSegmentedControl, 'Three'));
        await d.settle(900);
        await d.tap(_textCenter(d, MorphSegmentedControl, 'One'));
        await d.settle(900);
      },
      'drag': (d) async {
        final a = _textCenter(d, MorphSegmentedControl, 'One');
        final b = _textCenter(d, MorphSegmentedControl, 'Three');
        await d.finger(a, _line(a, b, 40));
        await d.settle(900);
        await d.finger(b, _line(b, a, 40));
        await d.settle(900);
      },
    },
  ),
  MatrixControl(
    'switch',
    () =>
        _Holder<bool>(false, (v, set) => MorphSwitch(value: v, onChanged: set)),
    {
      'tap': (d) async {
        for (var i = 0; i < 2; i++) {
          await d.tap(d.tester.getCenter(find.byType(MorphSwitch)));
          await d.settle(900);
        }
      },
      'drag': (d) async {
        final r = _rectOf(d, find.byType(MorphSwitch));
        final a = Offset(r.left + 14, r.center.dy);
        final b = Offset(r.right - 14, r.center.dy);
        await d.finger(a, _line(a, b, 30));
        await d.settle(900);
        await d.finger(b, _line(b, a, 30));
        await d.settle(900);
      },
    },
  ),
  MatrixControl(
    'slider',
    () => SizedBox(
      width: 300,
      child: _Holder<double>(
        0.2,
        (v, set) => MorphSlider(value: v, onChanged: set),
      ),
    ),
    {
      'drag': (d) async {
        final r = _rectOf(d, find.byType(MorphSlider));
        final a = Offset(r.left + r.width * 0.2, r.center.dy);
        final b = Offset(r.left + r.width * 0.8, r.center.dy);
        await d.finger(a, _line(a, b, 40));
        await d.settle(900);
        await d.finger(b, _line(b, a, 40));
        await d.settle(900);
      },
    },
  ),
  MatrixControl(
    'stepper',
    () => _Holder<double>(
      3,
      (v, set) => MorphStepper(value: v, max: 10, onChanged: set),
    ),
    {
      'tap': (d) async {
        final r = _rectOf(d, find.byType(MorphStepper));
        await d.tap(Offset(r.right - r.width / 4, r.center.dy));
        await d.settle(900);
        await d.tap(Offset(r.left + r.width / 4, r.center.dy));
        await d.settle(900);
      },
    },
  ),
  MatrixControl(
    'tab-bar',
    () => _Holder<int>(
      0,
      (v, set) => MorphTabBar(
        items: const [
          MorphTabItem(icon: Icons.home_rounded, label: 'Home'),
          MorphTabItem(icon: Icons.library_music_rounded, label: 'Library'),
          MorphTabItem(icon: Icons.radio_rounded, label: 'Radio'),
        ],
        selected: v,
        onChanged: set,
      ),
    ),
    {
      'tap': (d) async {
        await d.tap(_textCenter(d, MorphTabBar, 'Radio'));
        await d.settle(900);
        await d.tap(_textCenter(d, MorphTabBar, 'Home'));
        await d.settle(900);
      },
      'drag': (d) async {
        final a = _textCenter(d, MorphTabBar, 'Home');
        final b = _textCenter(d, MorphTabBar, 'Radio');
        await d.finger(
          a,
          _line(a, b, 40),
          holdBefore: const Duration(milliseconds: 300),
        );
        await d.settle(900);
        await d.tap(a);
        await d.settle(900);
      },
    },
  ),
  MatrixControl(
    'menu',
    () => MorphMenuButton(
      items: [
        for (final title in const ['Copy', 'Share', 'Rename', 'Delete'])
          MorphMenuItem(title: title, onSelected: () {}),
      ],
      child: const Text('Menu'),
    ),
    {
      'open-close': (d) async {
        await d.tap(d.tester.getCenter(find.byType(MorphMenuButton)));
        await d.settle(900);
        await d.tap(const Offset(20, 120));
        await d.settle(900);
      },
      'held': (d) async {
        await d.tap(d.tester.getCenter(find.byType(MorphMenuButton)));
        await d.settle(900);
        final row = d.tester.getCenter(find.text('Share').last);
        final rename = d.tester.getCenter(find.text('Rename').last);
        await d.finger(
          row,
          _line(row, rename, 20),
          holdBefore: const Duration(milliseconds: 600),
        );
        await d.settle(900);
        await d.tap(const Offset(20, 120));
        await d.settle(900);
      },
    },
  ),
  MatrixControl(
    'search',
    () => const SizedBox(width: 360, child: MorphSearchField()),
    {
      'press': (d) async {
        final field = d.tester.getCenter(find.byType(MorphSearchField));
        await d.finger(field, [
          for (var i = 0; i < 30; i++) field,
        ], holdBefore: const Duration(milliseconds: 16));
        await d.settle(900);
      },
    },
  ),
  MatrixControl(
    'nav-bar',
    () => SizedBox.expand(
      child: MorphNavigationStack(
        home: MorphNavigationScaffold(
          title: 'Inbox',
          largeTitle: true,
          trailing: [
            MorphBarButtonGroup([_barIcon('add'), _barIcon('more')]),
          ],
          toolbarLeading: [
            MorphBarButtonGroup([_barIcon('filter')], id: 'tbL'),
          ],
          slivers: [
            SliverList.builder(
              itemCount: 60,
              itemBuilder: (BuildContext context, int i) => SizedBox(
                height: 44,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Row $i'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    {
      'scroll': (d) async {
        final size =
            d.tester.view.physicalSize / d.tester.view.devicePixelRatio;
        final a = Offset(size.width / 2, size.height * 0.7);
        final b = Offset(size.width / 2, size.height * 0.35);
        await d.finger(a, _line(a, b, 40));
        await d.settle(900);
        await d.finger(b, _line(b, a, 40));
        await d.settle(900);
      },
    },
  ),
  MatrixControl('sheet', null, {
    'open-close': (d) async {
      presentMorphSheet<void>(
        MatrixStage.context!,
        detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
        grabberVisible: true,
        builder: (BuildContext context) => const SizedBox.expand(),
      ).ignore();
      await d.settle(900);
      await d.tap(const Offset(200, 80));
      await d.settle(900);
    },
    'drag': (d) async {
      presentMorphSheet<void>(
        MatrixStage.context!,
        detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
        grabberVisible: true,
        builder: (BuildContext context) => const SizedBox.expand(),
      ).ignore();
      await d.settle(900);
      final size = d.tester.view.physicalSize / d.tester.view.devicePixelRatio;
      final a = Offset(size.width / 2, size.height * 0.55);
      await d.finger(a, _line(a, a - const Offset(0, 250), 30));
      await d.settle(900);
      await d.finger(
        a - const Offset(0, 250),
        _line(a - const Offset(0, 250), a, 30),
      );
      await d.settle(900);
      await d.tap(const Offset(200, 80));
      await d.settle(900);
    },
  }),
  MatrixControl('alert', null, {
    'open-close': (d) async {
      showMorphAlert(
        MatrixStage.context!,
        title: 'Title',
        message: 'A message in the alert.',
        actions: const [
          MorphAlertAction(
            title: 'Cancel',
            style: MorphAlertActionStyle.cancel,
          ),
          MorphAlertAction(title: 'OK'),
        ],
      ).ignore();
      await d.settle(900);
      await d.tap(d.tester.getCenter(find.text('OK')));
      await d.settle(900);
    },
  }),
  MatrixControl(
    'date-picker',
    () => _Holder<DateTime>(
      DateTime(2026, 10, 12),
      (v, set) => MorphDatePicker(
        value: v,
        today: DateTime(2026, 10, 12),
        onChanged: set,
      ),
    ),
    {
      'open-close': (d) async {
        await d.tap(d.tester.getCenter(find.byType(MorphDatePicker)));
        await d.settle(900);
        await d.tap(const Offset(20, 120));
        await d.settle(900);
      },
    },
  ),
];

/// Runs every cell whose scene name passes [selected], timed by [driver].
Future<void> runControlMatrix(
  MatrixDriver driver,
  bool Function(String scene) selected,
) async {
  for (final control in matrixControls) {
    final cells = [
      for (final action in control.actions.keys)
        if (selected('m/${control.name}/$action')) action,
    ];
    if (cells.isEmpty) continue;
    MatrixStage.control.value = control.build?.call();
    await driver.settle(600);
    for (final action in cells) {
      await driver.measure(
        'm/${control.name}/$action',
        () => control.actions[action]!(driver),
      );
    }
    MatrixStage.control.value = null;
    await driver.settle(300);
  }
}
