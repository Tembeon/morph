// This device oracle switches the renderer and drives its internal bar row.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/pass/final_pass.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart';
import 'package:morph/src/widgets/bar_items.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/scope.dart';

/// Captures button silhouettes at rest, while lifting and while held.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final out = Directory('${Directory.systemTemp.path}/button-shapes');
  out.createSync(recursive: true);
  await File(
    '${out.path}/result.json',
  ).writeAsString(jsonEncode({'complete': false}));
  await MorphTheme.precacheGlass();
  await GlassFinalPass.precacheAnalyticShaders();
  if (!MorphTheme.liquidGlassAvailable) {
    throw StateError('The capture requires liquid glass.');
  }
  final keys = List.generate(6, (_) => GlobalKey());
  final widths = [44.0, 120.0];
  final mode = ValueNotifier('changes');
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light),
      builder: (_, child) => MorphTheme(
        data: const MorphThemeData(glass: .tier(MorphGlassTier.liquid)),
        child: BackdropGroup(child: MorphScope(child: child!)),
      ),
      home: ColoredBox(
        color: const Color(0xFFE8EDF4),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder(
                valueListenable: mode,
                builder: (_, value, _) => Text(value),
              ),
              for (var i = 0; i < widths.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: MorphGlassButton(
                    key: keys[i],
                    padding: EdgeInsets.zero,
                    minSize: Size(widths[i], 44),
                    onPressed: () {},
                    child: SizedBox(
                      width: widths[i],
                      height: 44,
                      child: const Icon(Icons.add),
                    ),
                  ),
                ),
              for (var i = 2; i < keys.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: SizedBox(
                    key: keys[i],
                    width: 340,
                    height: 64,
                    child: MorphBarItems(
                      metrics: i < 4
                          ? MorphBarMetrics.navigation
                          : MorphBarMetrics.toolbar,
                      top: 10,
                      leadingInset: 28,
                      trailingInset: 28,
                      groups: [
                        MorphPlacedGroup(
                          MorphBarButtonGroup([
                            MorphBarButton(
                              id: 'button-$i',
                              label: i.isOdd ? 'Options' : null,
                              icon: i.isEven ? const Icon(Icons.add) : null,
                              onPressed: () {},
                            ),
                          ], id: 'group-$i'),
                          MorphBarSide.leading,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  final geometry = <String, Object?>{};
  Future<void> shot(String name) async {
    await WidgetsBinding.instance.endOfFrame;
    final bytes = await const MethodChannel(
      'plugins.flutter.io/integration_test',
    ).invokeMethod<List<int>>('captureScreenshot', {'name': name});
    if (bytes == null) throw StateError('No screenshot $name');
    await File('${out.path}/$name.png').writeAsBytes(bytes);
  }

  Duration stamp() =>
      Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
  for (final name in ['changes', 'matte', 'analytic']) {
    RenderLiquidGlassLayer.debugAnalyticGeometry = name != 'matte';
    RenderLiquidGlassLayer.debugAnalyticMode = name == 'analytic'
        ? AnalyticGeometryMode.always
        : AnalyticGeometryMode.changes;
    mode.value = name;
    await Future<void>.delayed(const Duration(seconds: 2));
    final positions = <Offset>[];
    for (var i = 0; i < keys.length; i++) {
      final box = keys[i].currentContext!.findRenderObject()! as RenderBox;
      positions.add(
        box.localToGlobal(
          i < 2
              ? box.size.center(Offset.zero)
              : Offset(50, 10 + (i < 4 ? 44 : 48) / 2),
        ),
      );
      geometry['$name-$i'] = {
        'size': [box.size.width, box.size.height],
        'center': [positions.last.dx, positions.last.dy],
      };
    }
    await shot('$name-rest');
    for (var i = 0; i < positions.length; i++) {
      GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(
          pointer: 101 + i,
          position: positions[i],
          timeStamp: stamp(),
        ),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await shot('$name-lifting');
    await Future<void>.delayed(const Duration(seconds: 2));
    await shot('$name-held');
    for (var i = 0; i < positions.length; i++) {
      GestureBinding.instance.handlePointerEvent(
        PointerUpEvent(
          pointer: 101 + i,
          position: positions[i],
          timeStamp: stamp(),
        ),
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await shot('$name-returned');
  }
  await File(
    '${out.path}/result.json',
  ).writeAsString(jsonEncode({'complete': true, 'geometry': geometry}));
}
