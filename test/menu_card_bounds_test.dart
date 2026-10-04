import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/menu_motion.dart';
import 'package:morph/src/widgets/menu_entries.dart';

const _entries = <MorphMenuEntry>[
  MorphMenuItem(title: 'Copy'),
  MorphMenuItem(title: 'Share'),
  MorphSubmenu(
    title: 'More',
    children: [
      MorphMenuItem(title: 'Sub one'),
      MorphMenuItem(title: 'Sub two'),
      MorphSubmenu(
        title: 'Deeper',
        children: [
          MorphMenuItem(title: 'Deep one'),
          MorphSubmenu(
            title: 'Deepest',
            children: [MorphMenuItem(title: 'Last')],
          ),
        ],
      ),
    ],
  ),
  MorphMenuItem(title: 'Delete'),
];

MorphMenuMotion _motion(WidgetTester tester) =>
    tester.widget<MorphMenuLayer>(find.byType(MorphMenuLayer)).host.menuMotion!;

Finder _card(int index) => find.descendant(
  of: find.byType(MorphMenuLayer),
  matching: find.byKey(ValueKey<int>(index)),
);

Rect _rect(WidgetTester tester, int index) {
  final transform = find
      .descendant(of: _card(index), matching: find.byType(Transform))
      .first;
  final render = tester.renderObject<RenderTransform>(transform);
  final child = render.child!;
  return MatrixUtils.transformRect(
    child.getTransformTo(null),
    Offset.zero & child.size,
  );
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 16),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

Future<void> _openCard(WidgetTester tester, String title) async {
  await tester.tapAt(tester.getCenter(find.text(title).last));
  await _settle(tester);
}

void _dump(List<Map<String, Object?>> frames, String name) {
  final path = Platform.environment['MENU_FRAME_DUMP'];
  if (path == null) return;
  File('$path/$name.json').writeAsStringSync(jsonEncode(frames));
}

void main() {
  testWidgets('submenu taps do not flash a pill; held slides still highlight', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment(0, -0.6),
            child: MorphMenuButton(items: _entries),
          ),
        ),
      ),
    );
    Finder pill() => find.descendant(
      of: find.byType(MorphMenuLayer),
      matching: find.byWidgetPredicate((Widget widget) {
        if (widget is! DecoratedBox) return false;
        final decoration = widget.decoration;
        return decoration is BoxDecoration &&
            decoration.color == MorphMenuStyle.light.highlightColor;
      }),
    );
    await tester.tap(find.byType(MorphMenuButton));
    await _settle(tester);
    final tap = await tester.startGesture(tester.getCenter(find.text('More')));
    await tester.pump(const Duration(microseconds: 83333));
    expect(pill(), findsNothing);
    await tap.up();
    await _settle(tester);
    await tester.tapAt(const Offset(400, 580));
    await _settle(tester);
    final slide = await tester.startGesture(
      tester.getCenter(find.byType(MorphMenuButton)),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await slide.moveTo(tester.getCenter(find.text('More')));
    await tester.pump(const Duration(microseconds: 8333));
    expect(_motion(tester).isSliding, isTrue);
    expect(pill(), findsOneWidget);
    await slide.up();
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submenu closes without a horizontal discontinuity', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 177,
                top: 126,
                child: MorphMenuButton(items: _entries),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MorphMenuButton));
    await _settle(tester);
    await _openCard(tester, 'More');
    final frames = <Map<String, Object?>>[];
    await tester.tapAt(const Offset(201, 820));
    for (var i = 0; i < 100; i++) {
      if (find.byType(MorphMenuLayer).evaluate().isEmpty) break;
      final motion = _motion(tester);
      if (motion.cards.length < 2) break;
      final rect = _rect(tester, 1);
      frames.add({
        't': motion.time,
        'p': motion.progress,
        'rect': [rect.left, rect.top, rect.width, rect.height],
        'content': [motion.contentRect.left, motion.contentRect.top],
      });
      await tester.pump(const Duration(microseconds: 8333));
    }
    _dump(frames, 'close');
    var previous = Rect.fromLTWH(
      (frames.first['rect']! as List<double>)[0],
      0,
      (frames.first['rect']! as List<double>)[2],
      0,
    );
    for (final frame in frames.skip(1)) {
      final values = frame['rect']! as List<double>;
      final rect = Rect.fromLTWH(values[0], values[1], values[2], values[3]);
      expect(
        (rect.center.dx - previous.center.dx).abs(),
        lessThanOrEqualTo(0.5),
        reason: '$frame',
      );
      previous = rect;
    }
    expect(tester.takeException(), isNull);
  });

  for (final rtl in [false, true]) {
    for (final nested in [false, true]) {
      final name =
          'header-${rtl ? "rtl" : "ltr"}-${nested ? "nested" : "root"}';
      testWidgets('$name hands back without a horizontal jump', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            builder: (BuildContext context, Widget? child) =>
                Directionality(textDirection: rtl ? .rtl : .ltr, child: child!),
            home: const Scaffold(
              body: Align(
                alignment: Alignment(0, -0.6),
                child: MorphMenuButton(
                  items: [
                    MorphMenuItem(title: 'Selected', state: MorphMenuState.on),
                    MorphSubmenu(
                      title: 'More',
                      icon: Icons.folder,
                      children: [
                        MorphMenuItem(title: 'Child', state: MorphMenuState.on),
                        MorphSubmenu(
                          title: 'Deeper',
                          icon: Icons.folder,
                          children: [MorphMenuItem(title: 'Last')],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(MorphMenuButton));
        await _settle(tester);
        await _openCard(tester, 'More');
        final title = nested ? 'Deeper' : 'More';
        if (nested) await _openCard(tester, title);
        await tester.tapAt(tester.getCenter(find.text(title).last));
        final frames = <Map<String, Object?>>[];
        for (var i = 0; i < 120; i++) {
          final motion = _motion(tester);
          final rect = tester.getRect(find.text(title).last);
          final cards = <List<double>>[];
          for (var index = 0; index < motion.cards.length; index++) {
            final bounds = _rect(tester, index);
            cards.add([bounds.left, bounds.top, bounds.width, bounds.height]);
          }
          frames.add({
            't': motion.time,
            'cards': cards,
            'rect': [rect.left, rect.top, rect.width, rect.height],
          });
          await tester.pump(const Duration(microseconds: 8333));
        }
        _dump(frames, name);
        double? previous;
        for (final frame in frames) {
          final rect = frame['rect']! as List<double>;
          final edge = rtl ? rect[0] + rect[2] : rect[0];
          if (previous != null) {
            expect(
              (edge - previous).abs(),
              lessThanOrEqualTo(0.5),
              reason: '$frame',
            );
          }
          previous = edge;
        }
        expect(_motion(tester).cards.length, nested ? 2 : 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a dark card has its own platter past the root list', (
    WidgetTester tester,
  ) async {
    const key = ValueKey<String>('screen');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: const Scaffold(
            backgroundColor: Color(0xFF000000),
            body: Align(
              alignment: Alignment(0, -0.6),
              child: MorphMenuButton(items: _entries),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MorphMenuButton));
    await _settle(tester);
    await _openCard(tester, 'More');
    final root = _rect(tester, 0);
    final card = _rect(tester, 1);
    final point = Offset(card.left + 15, card.bottom - 20);
    expect(point.dy, greaterThan(root.bottom + 30));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final channels = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final at = 4 * (point.dy.round() * image.width + point.dx.round());
      final channels = [
        for (var channel = 0; channel < 3; channel++)
          pixels.getUint8(at + channel),
      ];
      image.dispose();
      return channels;
    });
    expect(channels, everyElement(inInclusiveRange(31, 35)));
  });

  testWidgets('nested platters escape the menu vessel clip', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment(0, -0.6),
            child: MorphMenuButton(items: _entries),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MorphMenuButton));
    await _settle(tester);
    final frames = <Map<String, Object?>>[];
    var depth = 0;
    for (final title in ['More', 'Deeper', 'Deepest']) {
      depth++;
      await tester.tapAt(tester.getCenter(find.text(title).last));
      for (var frame = 0; frame < 100; frame++) {
        final motion = _motion(tester);
        for (var index = 1; index < motion.cards.length; index++) {
          final rect = _rect(tester, index);
          final clips = <List<double>>[];
          tester.element(_card(index)).visitAncestorElements((Element element) {
            final render = element.renderObject;
            if (render is RenderClipRRect && render.clipBehavior != Clip.none) {
              final clip = MatrixUtils.transformRect(
                render.getTransformTo(null),
                Offset.zero & render.size,
              );
              clips.add([clip.left, clip.top, clip.width, clip.height]);
            }
            if (render is RenderClipRect && render.clipBehavior != Clip.none) {
              final clip = MatrixUtils.transformRect(
                render.getTransformTo(null),
                Offset.zero & render.size,
              );
              clips.add([clip.left, clip.top, clip.width, clip.height]);
            }
            return true;
          });
          frames.add({
            'level': title,
            't': motion.time,
            'index': index,
            'rect': [rect.left, rect.top, rect.width, rect.height],
            'clips': clips,
          });
        }
        await tester.pump(const Duration(microseconds: 8333));
      }
      await _settle(tester);
      final motion = _motion(tester);
      var scale = 1.0;
      for (var index = depth; index >= 0; index--) {
        expect(_rect(tester, index).width, closeTo(250 * scale, 0.02));
        scale *= 0.97;
      }
      expect(motion.rootBlob.rect.width, closeTo(_rect(tester, 0).width, 0.02));
    }
    _dump(frames, 'nested');
    for (final frame in frames) {
      expect(frame['clips'], isEmpty, reason: '$frame');
    }
    expect(tester.takeException(), isNull);
  });
}
