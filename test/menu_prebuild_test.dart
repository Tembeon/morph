import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/internal/multi_shader_builder.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/menu_host.dart';
import 'package:morph/widgets.dart';

Widget _app(Widget child) => MaterialApp(
  builder: (BuildContext context, Widget? child) => MorphScope(child: child!),
  home: Scaffold(
    body: Align(alignment: const Alignment(0, -0.6), child: child),
  ),
);

final _items = [
  for (final title in const [
    'Copy',
    'Share',
    'Rename',
    'Duplicate',
    'Move',
    'Tag',
    'Pin',
    'Archive',
    'Print',
  ])
    MorphMenuItem(title: title, icon: Icons.copy, onSelected: () {}),
  MorphMenuItem(title: 'Delete', destructive: true, onSelected: () {}),
];

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text, skipOffstage: false));

RenderRepaintBoundary _rows(WidgetTester tester) =>
    tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(
            of: find.text('Copy', skipOffstage: false),
            matching: find.byType(RepaintBoundary, skipOffstage: false),
          )
          .first,
    );

Future<void> _frames(WidgetTester tester, int milliseconds) async {
  for (var i = 0; i < milliseconds; i += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

const _rich = <MorphMenuEntry>[
  MorphMenuSection(
    elementSize: MorphMenuElementSize.small,
    children: [
      MorphMenuItem(title: 'Cut', icon: Icons.content_cut),
      MorphMenuItem(title: 'Copy', icon: Icons.copy),
      MorphMenuItem(title: 'Paste', icon: Icons.content_paste),
    ],
  ),
  MorphMenuSection(
    title: 'Sort by',
    children: [
      MorphMenuItem(title: 'Name', state: MorphMenuState.on),
      MorphMenuItem(title: 'Date', subtitle: 'Newest first'),
    ],
  ),
  MorphSubmenu(
    title: 'More',
    icon: Icons.folder_outlined,
    children: [
      MorphMenuItem(title: 'Rename'),
      MorphMenuItem(title: 'Duplicate'),
    ],
  ),
  MorphMenuItem(title: 'Delete', destructive: true),
];

String _hash(Uint32List words) {
  var a = 0x811c9dc5;
  var b = 0x01000193;
  for (final w in words) {
    a = ((a ^ w) * 0x01000193) & 0xFFFFFFFF;
    b = ((b + w) * 0x9E3779B1) & 0xFFFFFFFF;
  }
  return '${a.toRadixString(16)}${b.toRadixString(16)}';
}

/// Every frame of a press on the button, its opening, a submenu and the
/// close, as hashes of the whole screen.
Future<List<String>> _record(WidgetTester tester, MorphGlassTier tier) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(platform: TargetPlatform.iOS),
      builder: (BuildContext context, Widget? child) => MorphAdaptiveGlass(
        tier: tier,
        child: MorphScope(child: child!),
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        body: Stack(
          children: [
            for (var i = 0; i < 12; i++)
              Positioned(
                left: 0,
                right: 0,
                top: i * 80.0,
                height: 40,
                child: ColoredBox(color: Color(0xFF000000 | (i * 0x153F7B))),
              ),
            const Align(
              alignment: Alignment(0, -0.4),
              child: MorphMenuButton(items: _rich),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final images = <ui.Image>[];
  var active = true;
  void capture(Duration _) {
    if (!active) return;
    tester.binding.addPostFrameCallback((Duration _) {
      if (!active) return;
      final root = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
      images.add(root.toImageSync(const Rect.fromLTWH(0, 0, 402, 874)));
    });
  }

  tester.binding.addPersistentFrameCallback(capture);
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(MorphMenuButton)),
  );
  await _frames(tester, 64);
  await gesture.up();
  await _frames(tester, 900);
  await tester.tapAt(tester.getCenter(find.text('More').last));
  await _frames(tester, 700);
  await tester.tapAt(const Offset(20, 840));
  await _frames(tester, 1200);
  active = false;
  final hashes = await tester.runAsync(() async {
    final out = <String>[];
    for (final image in images) {
      final data = await image.toByteData();
      out.add(_hash(data!.buffer.asUint32List()));
      image.dispose();
    }
    return out;
  });
  await tester.pumpAndSettle();
  return hashes!;
}

void main() {
  setUpAll(() async {
    isLocalTest = true;
    await MultiShaderBuilder.precacheShaders([
      ShaderKeys.fakeGlassSurface,
      ShaderKeys.liquidGlassRender,
      ShaderKeys.liquidGlassMaterialRender,
      ShaderKeys.liquidGlassTintRender,
    ]);
  });
  tearDownAll(() => isLocalTest = false);

  for (final tier in MorphGlassTier.values) {
    testWidgets('rows built ahead draw the frames built at the opening draw: '
        '${tier.name}', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => MorphMenuController.debugPrebuild = true);
      MorphMenuController.debugPrebuild = false;
      final reference = await _record(tester, tier);
      MorphMenuController.debugPrebuild = true;
      final frames = await _record(tester, tier);
      expect(frames.length, reference.length);
      expect(frames, orderedEquals(reference));
    });
  }

  testWidgets('a press builds the rows out of sight and the opening moves '
      'them into the menu', (WidgetTester tester) async {
    await tester.pumpWidget(_app(MorphMenuButton(items: _items)));
    expect(find.text('Copy', skipOffstage: false), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MorphMenuButton)),
    );
    await _frames(tester, 48);
    expect(find.text('Copy', skipOffstage: false), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    await _frames(tester, 32);
    final before = {
      for (final item in _items) item.title: _paragraph(tester, item.title),
    };
    final boundary = _rows(tester);
    await gesture.up();
    var waited = 0;
    while (find.byType(MorphMenuLayer).evaluate().isEmpty && waited < 400) {
      await tester.pump(const Duration(milliseconds: 16));
      waited += 16;
    }
    expect(find.byType(MorphMenuLayer), findsOneWidget);
    expect(identical(_rows(tester), boundary), isTrue);
    await _frames(tester, 400);
    expect(find.text('Copy').hitTestable(), findsOneWidget);
    for (final item in _items) {
      expect(
        identical(_paragraph(tester, item.title), before[item.title]),
        isTrue,
      );
    }
    await tester.tapAt(const Offset(10, 590));
    await tester.pumpAndSettle();
    expect(find.text('Copy', skipOffstage: false), findsNothing);
  });

  testWidgets('a press that slides away drops the rows built for it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(MorphMenuButton(items: _items)));
    final center = tester.getCenter(find.byType(MorphMenuButton));
    final gesture = await tester.startGesture(center);
    await _frames(tester, 80);
    expect(find.text('Copy', skipOffstage: false), findsOneWidget);
    await gesture.moveTo(center + const Offset(0, 200));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.text('Copy', skipOffstage: false), findsNothing);
  });

  testWidgets('a press on the button right after a landing opens again', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(MorphMenuButton(items: _items)));
    final button = find.byType(MorphMenuButton);
    for (var i = 0; i < 3; i++) {
      await tester.tap(button);
      await _frames(tester, 700);
      expect(find.text('Copy'), findsOneWidget);
      await tester.tapAt(const Offset(10, 590));
      for (var k = 0; k < 60; k++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
