import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

final Map<String, Object?> _fixture =
    (jsonDecode(
              File(
                'test/fixtures/ios27-device/disabled/disabled.json',
              ).readAsStringSync(),
            )
            as Map)
        .cast<String, Object?>();

Map<String, Object?> _control(String name) =>
    ((_fixture['controls']! as Map)[name]! as Map).cast<String, Object?>();

Color _rgba(Object? value) {
  final v = (value! as List).cast<num>();
  return Color.from(
    alpha: v[3].toDouble(),
    red: v[0].toDouble(),
    green: v[1].toDouble(),
    blue: v[2].toDouble(),
  );
}

Color _appearance(Object? table, Brightness brightness) =>
    _rgba((table! as Map)[brightness == Brightness.dark ? 'dark' : 'light']);

Color _tertiaryLabel(Brightness b) =>
    _appearance((_fixture['colors']! as Map)['tertiaryLabel'], b);

Color _systemGray4(Brightness b) =>
    _appearance((_fixture['colors']! as Map)['systemGray4'], b);

Matcher _sameColor(Color expected) => predicate<Color>(
  (Color c) =>
      (c.a - expected.a).abs() < 1 / 255 &&
      (c.r - expected.r).abs() < 1 / 255 &&
      (c.g - expected.g).abs() < 1 / 255 &&
      (c.b - expected.b).abs() < 1 / 255,
  'the color $expected',
);

/// The 8-bit sRGB of [top] composited over the opaque [bottom].
List<double> _over(Color top, List<double> bottom) => [
  for (final (i, c) in [top.r, top.g, top.b].indexed)
    c * 255 * top.a + bottom[i] * (1 - top.a),
];

const _shotKey = ValueKey<String>('shot');

Widget _scene(
  Widget child, {
  Brightness brightness = Brightness.light,
  Color background = const Color(0xFFF2F2F7),
  Size size = const Size(360, 120),
  MorphGlassPainter? glass,
}) {
  Widget content = Center(
    child: RepaintBoundary(
      key: _shotKey,
      child: ColoredBox(
        color: background,
        child: SizedBox.fromSize(
          size: size,
          child: Center(child: child),
        ),
      ),
    ),
  );
  if (glass != null) content = MorphGlass(painter: glass, child: content);
  return MediaQuery(
    data: MediaQueryData(platformBrightness: brightness),
    child: Directionality(textDirection: TextDirection.ltr, child: content),
  );
}

class _Shot {
  _Shot(this.width, this.bytes);

  final int width;
  final Uint8List bytes;

  List<double> at(int x, int y) {
    final i = (y * width + x) * 4;
    return [
      bytes[i].toDouble(),
      bytes[i + 1].toDouble(),
      bytes[i + 2].toDouble(),
    ];
  }
}

Future<_Shot> _shoot(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_shotKey),
  );
  final shot = await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    final data = await image.toByteData();
    final width = image.width;
    image.dispose();
    return _Shot(width, data!.buffer.asUint8List());
  });
  return shot!;
}

/// Asserts that every pixel of [disabled] is [opacity] of [enabled] over
/// [background], as one layer: the disabled rule UIKit applies to the
/// segmented control, the switch and the slider.
void _expectOneLayer(
  _Shot enabled,
  _Shot disabled,
  double opacity,
  Color background,
) {
  final bg = [background.r * 255, background.g * 255, background.b * 255];
  var worst = 0.0;
  var differs = 0;
  for (var i = 0; i < enabled.bytes.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      final e = enabled.bytes[i + c].toDouble();
      if ((e - bg[c]).abs() > 2) differs++;
      final want = opacity * e + (1 - opacity) * bg[c];
      final error = (disabled.bytes[i + c] - want).abs();
      if (error > worst) worst = error;
    }
  }
  expect(differs, greaterThan(100), reason: 'the control drew something');
  expect(worst, lessThanOrEqualTo(1.5), reason: '8-bit rounding, twice');
}

class _Recorder extends MorphGlassPainter {
  final List<MorphGlassSurface> surfaces = [];

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) {
    surfaces.add(surface);
    return const SizedBox.expand();
  }

  @override
  Widget buildFill(BuildContext context, MorphGlassSurface surface) {
    surfaces.add(surface);
    return super.buildFill(context, surface);
  }
}

void main() {
  group('one layer at half opacity', () {
    final cases = <String, Widget Function({required bool enabled})>{
      'segmented': ({required bool enabled}) => SizedBox(
        width: 300,
        child: MorphSegmentedControl(
          segments: const ['Day', 'Night', 'All'],
          selected: 0,
          onChanged: enabled ? (int _) {} : null,
        ),
      ),
      'switch': ({required bool enabled}) =>
          MorphSwitch(value: true, onChanged: enabled ? (bool _) {} : null),
      'slider': ({required bool enabled}) => SizedBox(
        width: 300,
        child: MorphSlider(
          value: 0.4,
          ticks: 5,
          onChanged: enabled ? (double _) {} : null,
        ),
      ),
    };
    for (final MapEntry(key: name, value: build) in cases.entries) {
      for (final brightness in Brightness.values) {
        testWidgets('$name, ${brightness.name}: the device rule', (
          tester,
        ) async {
          final opacity = (_control(name)['opacity']! as num).toDouble();
          final background = brightness == Brightness.dark
              ? const Color(0xFF000000)
              : const Color(0xFFF2F2F7);
          await tester.pumpWidget(
            _scene(
              build(enabled: true),
              brightness: brightness,
              background: background,
            ),
          );
          final enabled = await _shoot(tester);
          await tester.pumpWidget(
            _scene(
              build(enabled: false),
              brightness: brightness,
              background: background,
            ),
          );
          final disabled = await _shoot(tester);
          _expectOneLayer(enabled, disabled, opacity, background);
        });
      }
    }
  });

  group('no disabled look', () {
    final cases = <String, Widget Function({required bool enabled})>{
      'stepper': ({required bool enabled}) => MorphStepper(
        value: 3,
        max: 9,
        onChanged: enabled ? (double _) {} : null,
      ),
      'page_control': ({required bool enabled}) => MorphPageControl(
        count: 5,
        page: 1,
        onChanged: enabled ? (int _) {} : null,
      ),
      'tab_bar_item': ({required bool enabled}) => SizedBox(
        width: 360,
        child: MorphTabBar(
          items: [
            const MorphTabItem(icon: IconData(0xe318), label: 'One'),
            const MorphTabItem(icon: IconData(0xe318), label: 'Two'),
            MorphTabItem(
              icon: const IconData(0xe318),
              label: 'Three',
              enabled: enabled,
            ),
          ],
          selected: 0,
          onChanged: (int _) {},
        ),
      ),
    };
    for (final MapEntry(key: name, value: build) in cases.entries) {
      testWidgets('$name draws the same pixels disabled', (tester) async {
        expect((_control(name)['opacity']! as num).toDouble(), 1.0);
        await tester.pumpWidget(_scene(build(enabled: true)));
        final enabled = await _shoot(tester);
        await tester.pumpWidget(_scene(build(enabled: false)));
        final disabled = await _shoot(tester);
        expect(disabled.bytes, enabled.bytes);
      });
    }
  });

  group('stepper', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: a half at its limit draws its glyph in '
          'tertiaryLabel, enabled or not', (tester) async {
        final limit = _appearance(
          _control('stepper')['limit_half_glyph'],
          brightness,
        );
        final style = brightness == Brightness.dark
            ? MorphStepperStyle.dark
            : MorphStepperStyle.light;
        expect(style.limitForegroundColor, _sameColor(limit));
        expect(style.dividerColor, _sameColor(_tertiaryLabel(brightness)));
        final background = brightness == Brightness.dark
            ? const Color(0xFF000000)
            : const Color(0xFFF2F2F7);
        final bg = [background.r * 255, background.g * 255, background.b * 255];
        final fill = _over(style.backgroundColor, bg);
        final glyph = _over(limit, fill);
        for (final enabled in [true, false]) {
          await tester.pumpWidget(
            _scene(
              MorphStepper(
                value: 0,
                max: 9,
                onChanged: enabled ? (double _) {} : null,
              ),
              brightness: brightness,
              background: background,
            ),
          );
          final shot = await _shoot(tester);
          final origin =
              tester.getTopLeft(find.byType(MorphStepper)) -
              tester.getTopLeft(find.byKey(_shotKey));
          final minus = shot.at(
            (origin.dx + 23.5).floor(),
            (origin.dy + 15.5).floor(),
          );
          for (var c = 0; c < 3; c++) {
            expect(minus[c], closeTo(glyph[c], 1.5));
          }
        }
      });
    }

    testWidgets('the pressed half: light draws black 8 percent over its '
        'fill, dark replaces the fill', (tester) async {
      for (final brightness in Brightness.values) {
        final background = brightness == Brightness.dark
            ? const Color(0xFF242424)
            : const Color(0xFFF2F2F7);
        final bg = [background.r * 255, background.g * 255, background.b * 255];
        final style = brightness == Brightness.dark
            ? MorphStepperStyle.dark
            : MorphStepperStyle.light;
        await tester.pumpWidget(
          _scene(
            MorphStepper(value: 3, max: 9, onChanged: (double _) {}),
            brightness: brightness,
            background: background,
          ),
        );
        final gesture = await tester.startGesture(
          tester.getTopLeft(find.byType(MorphStepper)) + const Offset(80, 6),
        );
        await tester.pump();
        final shot = await _shoot(tester);
        await gesture.up();
        await tester.pump();
        final origin =
            tester.getTopLeft(find.byType(MorphStepper)) -
            tester.getTopLeft(find.byKey(_shotKey));
        final pressed = shot.at(
          (origin.dx + 80).floor(),
          (origin.dy + 6).floor(),
        );
        final under = style.pressedReplacesFill
            ? bg
            : _over(style.backgroundColor, bg);
        final want = _over(MorphStepper.pressedOverlay, under);
        for (var c = 0; c < 3; c++) {
          expect(pressed[c], closeTo(want[c], 1.5), reason: brightness.name);
        }
      }
    });
  });

  group('glass button', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: content tertiaryLabel, glass '
          'unchanged; prominent tint systemGray4', (tester) async {
        final recorder = _Recorder();
        Color? clear;
        Color? prominent;
        await tester.pumpWidget(
          _scene(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MorphGlassButton(
                  onPressed: null,
                  child: Builder(
                    builder: (BuildContext context) {
                      clear = DefaultTextStyle.of(context).style.color;
                      return const Text('Glass');
                    },
                  ),
                ),
                MorphGlassButton(
                  onPressed: null,
                  tint: const Color(0xFF0088FF),
                  child: Builder(
                    builder: (BuildContext context) {
                      prominent = IconTheme.of(context).color;
                      return const Text('Glass');
                    },
                  ),
                ),
              ],
            ),
            brightness: brightness,
            glass: recorder,
          ),
        );
        final content = _appearance(
          _control('glass_button')['content'],
          brightness,
        );
        expect(clear, _sameColor(content));
        expect(
          prominent,
          _sameColor(
            _appearance(
              _control('prominent_glass_button')['content'],
              brightness,
            ),
          ),
        );
        final style = brightness == Brightness.dark
            ? MorphGlassButtonStyle.dark
            : MorphGlassButtonStyle.light;
        final buttons = [
          for (final s in recorder.surfaces)
            if (s.kind == MorphGlassKind.button) s.color,
        ];
        expect(buttons.first, style.fillColor);
        expect(buttons.last, _sameColor(_systemGray4(brightness)));
        expect(
          find.ancestor(
            of: find.text('Glass').first,
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );
      });
    }

    testWidgets('a disabled button ignores a hold', (tester) async {
      await tester.pumpWidget(
        _scene(const MorphGlassButton(onPressed: null, child: Text('Glass'))),
      );
      final before = tester.getRect(find.text('Glass'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Glass')),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getRect(find.text('Glass')), before);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await gesture.up();
    });
  });

  group('menu button', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: the glyph turns tertiaryLabel and a '
          'tap does not open', (tester) async {
        Color? glyph;
        final recorder = _Recorder();
        await tester.pumpWidget(
          _scene(
            MorphMenuButton(
              enabled: false,
              items: const [MorphMenuItem(title: 'Copy')],
              child: Builder(
                builder: (BuildContext context) {
                  glyph = IconTheme.of(context).color;
                  return const SizedBox.square(dimension: 20);
                },
              ),
            ),
            brightness: brightness,
            size: const Size(360, 300),
            glass: recorder,
          ),
        );
        expect(
          glyph,
          _sameColor(
            _appearance(_control('menu_button')['content'], brightness),
          ),
        );
        final style = brightness == Brightness.dark
            ? MorphMenuStyle.dark
            : MorphMenuStyle.light;
        expect(
          recorder.surfaces
              .where((s) => s.kind == MorphGlassKind.button)
              .first
              .color,
          style.glassColor,
        );
        await tester.tap(find.byType(MorphMenuButton));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Copy'), findsNothing);
      });
    }

    test('the light menu material renders 249, 249, 255 over the grouped '
        'background, as the light date picker overlay does', () {
      for (final color in [
        MorphMenuStyle.light.glassColor,
        MorphDatePickerStyle.light.platterColor,
      ]) {
        expect(color, const Color(0xF2F9F9FF));
        final shown = _over(color, [242, 242, 247]);
        expect(shown[0], closeTo(249, 0.5));
        expect(shown[1], closeTo(249, 0.5));
        expect(shown[2], closeTo(255, 0.5));
      }
      expect(MorphMenuStyle.dark.glassColor, const Color(0xF2222222));
      expect(MorphDatePickerStyle.dark.platterColor, const Color(0xF2222222));
    });
  });

  group('bar items', () {
    test('the disabled colors render the measured peaks over the capsule', () {
      final peaks = (_control('bar_item_plain')['rendered_peak']! as Map)
          .cast<String, Object?>();
      for (final brightness in Brightness.values) {
        final row = (peaks[brightness.name]! as Map).cast<String, Object?>();
        final capsule = switch (row['capsule']) {
          final num n => n.toDouble(),
          final List<Object?> l => (l.first! as num).toDouble(),
          _ => throw StateError('capsule'),
        };
        final style = brightness == Brightness.dark
            ? MorphBarStyle.dark
            : MorphBarStyle.light;
        for (final (kind, color) in [
          ('icon', style.disabledIconColor),
          ('text', style.disabledLabelColor),
        ]) {
          final enabled = (row['${kind}_enabled']! as num).toDouble();
          final disabled = (row['${kind}_disabled']! as num).toDouble();
          final shown = capsule + color.a * (enabled - capsule);
          expect(shown, closeTo(disabled, 1.5), reason: '$brightness $kind');
        }
        expect(
          style.disabledProminentColor,
          _sameColor(_systemGray4(brightness)),
        );
      }
    });

    testWidgets('plain items take the disabled colors, a prominent capsule '
        'of disabled items turns systemGray4 with a white glyph, and a tap '
        'does nothing', (tester) async {
      tester.view.physicalSize = const Size(402, 874) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final recorder = _Recorder();
      Color? icon;
      await tester.pumpWidget(
        MaterialApp(
          home: MorphGlass(
            painter: recorder,
            child: Align(
              alignment: Alignment.topCenter,
              child: MorphNavigationBar(
                title: 'Inbox',
                leading: const MorphBarButtonGroup([
                  MorphBarButton(id: 'edit', label: 'Edit'),
                ]),
                trailing: [
                  MorphBarButtonGroup([
                    MorphBarButton(
                      id: 'add',
                      semanticLabel: 'add',
                      icon: Builder(
                        builder: (BuildContext context) {
                          icon = IconTheme.of(context).color;
                          return const SizedBox.square(dimension: 24);
                        },
                      ),
                    ),
                  ]),
                  const MorphBarButtonGroup([
                    MorphBarButton(id: 'done', label: 'Done'),
                  ], prominent: true),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      const style = MorphBarStyle.light;
      expect(icon, style.disabledIconColor);
      expect(
        tester.widget<Text>(find.text('Edit')).style?.color,
        style.disabledLabelColor,
      );
      expect(
        tester.widget<Text>(find.text('Done')).style?.color,
        style.prominentForegroundColor,
      );
      final colors = {
        for (final s in recorder.surfaces)
          if (s.kind == MorphGlassKind.button) s.color,
      };
      expect(colors, contains(style.disabledProminentColor));
      expect(colors, isNot(contains(style.prominentColor)));
      expect(colors, contains(style.capsuleColor));
      expect(
        tester
            .widgetList<Opacity>(
              find.ancestor(
                of: find.text('Edit'),
                matching: find.byType(Opacity),
              ),
            )
            .every((Opacity o) => o.opacity == 1),
        isTrue,
      );
    });
  });

  group('search field', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: a flat fill without glass', (
        tester,
      ) async {
        final recorder = _Recorder();
        final background = brightness == Brightness.dark
            ? const Color(0xFF000000)
            : const Color(0xFFF2F2F7);
        await tester.pumpWidget(
          _scene(
            const SizedBox(width: 300, child: MorphSearchField(enabled: false)),
            brightness: brightness,
            background: background,
            glass: recorder,
          ),
        );
        expect(recorder.surfaces, isEmpty);
        final fill = _appearance(_control('search_field')['fill'], brightness);
        final style = brightness == Brightness.dark
            ? MorphSearchFieldStyle.dark
            : MorphSearchFieldStyle.light;
        expect(style.disabledFillColor, _sameColor(fill));
        final shot = await _shoot(tester);
        final field = tester
            .getRect(find.byType(MorphSearchField))
            .shift(-tester.getTopLeft(find.byKey(_shotKey)));
        final body = shot.at(
          (field.right - 40).floor(),
          field.center.dy.floor(),
        );
        final want =
            ((_control('search_field')['pixels']! as Map)[brightness.name]!
                    as Map)['body_disabled']!
                as List;
        for (var c = 0; c < 3; c++) {
          expect(body[c], closeTo((want[c]! as num).toDouble(), 1.0));
        }
        await tester.tap(find.byType(MorphSearchField));
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isFalse, reason: 'no lift');
        expect(FocusManager.instance.primaryFocus?.context, isNull);
      });
    }
  });

  group('date picker', () {
    testWidgets('disabled labels keep their text and lose the capsule', (
      tester,
    ) async {
      final date = DateTime(2026, 9, 21, 16, 13);
      await tester.pumpWidget(
        _scene(
          MorphDatePicker(value: date, onChanged: null),
          size: const Size(360, 80),
        ),
      );
      final shot = await _shoot(tester);
      final origin = tester.getTopLeft(find.byKey(_shotKey));
      final label = tester.getRect(find.byType(MorphDatePicker)).shift(-origin);
      final edge = shot.at((label.left + 3).floor(), label.center.dy.floor());
      expect(edge, [242.0, 242.0, 247.0]);
      final removed = _appearance(
        _control('date_picker_labels')['removed_fill'],
        Brightness.light,
      );
      expect(MorphDatePickerStyle.light.labelFillColor, _sameColor(removed));
    });
  });

  group('alerts', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: a disabled action is tertiaryLabel, '
          'destructive too; a disabled preferred action loses the accent '
          'and keeps semibold', (tester) async {
        final title = _appearance(
          _control('alert_action')['title'],
          brightness,
        );
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Builder(
              builder: (BuildContext c) {
                context = c;
                return const SizedBox.expand();
              },
            ),
          ),
        );
        final style = MorphAlertStyle.resolve(context, null);
        expect(style.disabledLabelColor, _sameColor(title));
        unawaited(
          showMorphAlert(
            context,
            title: 'Rename',
            actions: const [
              MorphAlertAction(
                title: 'Delete',
                style: .destructive,
                enabled: false,
              ),
              MorphAlertAction(title: 'OK', isPreferred: true, enabled: false),
            ],
          ),
        );
        await tester.pumpAndSettle();
        final delete = tester.widget<Text>(find.text('Delete'));
        expect(delete.style?.color, _sameColor(title));
        final ok = tester.widget<Text>(find.text('OK'));
        expect(ok.style?.color, _sameColor(title));
        expect(ok.style?.fontWeight, FontWeight.w600);
        final fill = tester
            .widgetList<Container>(
              find.ancestor(
                of: find.text('OK'),
                matching: find.byType(Container),
              ),
            )
            .map((Container c) => c.decoration)
            .whereType<ShapeDecoration>()
            .first
            .color;
        expect(fill, style.buttonColor);
      });
    }
  });

  testWidgets('a touch on a disabled tab swells the bar but neither selects '
      'nor moves the lens', (tester) async {
    final changes = <int>[];
    await tester.pumpWidget(
      _scene(
        SizedBox(
          width: 360,
          child: MorphTabBar(
            items: const [
              MorphTabItem(icon: IconData(0xe318), label: 'One'),
              MorphTabItem(icon: IconData(0xe318), label: 'Two'),
              MorphTabItem(
                icon: IconData(0xe318),
                label: 'Three',
                enabled: false,
              ),
            ],
            selected: 0,
            onChanged: changes.add,
          ),
        ),
      ),
    );
    final rest = tester.getRect(find.text('One'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Three')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final held = tester.getRect(find.text('One'));

    expect(held.width, greaterThan(rest.width), reason: 'the bar swells');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    final after = tester.getRect(find.text('One'));
    expect((after.center - rest.center).distance, lessThan(0.5));
    expect(after.width, closeTo(rest.width, 0.1));
  });

  for (final (name, control) in <(String, Widget)>[
    ('switch', const MorphSwitch(value: false, onChanged: null)),
    (
      'slider',
      const SizedBox(
        width: 300,
        child: MorphSlider(value: 0.5, onChanged: null),
      ),
    ),
    ('stepper', const MorphStepper(value: 3, onChanged: null)),
    (
      'segmented',
      const SizedBox(
        width: 300,
        child: MorphSegmentedControl(
          segments: ['A', 'B'],
          selected: 0,
          onChanged: null,
        ),
      ),
    ),
    (
      'prominent glass button',
      const MorphGlassButton(
        onPressed: null,
        tint: Color(0xFF0088FF),
        child: Text('Go'),
      ),
    ),
  ]) {
    testWidgets('a disabled $name shows no reaction to a 0.8 s hold', (
      tester,
    ) async {
      await tester.pumpWidget(_scene(control));
      final before = await _shoot(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_shotKey)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.binding.hasScheduledFrame, isFalse);
      final held = await _shoot(tester);
      expect(held.bytes, before.bytes);
      await gesture.up();
    });
  }

  test('the activity indicator is 0x99EBEBF5 in dark', () {
    expect(MorphActivityIndicatorStyle.dark.color, const Color(0x99EBEBF5));
    expect(MorphActivityIndicatorStyle.light.color, const Color(0x993C3C43));
  });
}
