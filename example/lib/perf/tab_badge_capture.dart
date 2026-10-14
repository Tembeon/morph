import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// Captures count and dot badges under a held and dragged liquid lens.
///
/// Build this entrypoint as an iOS release app and launch with devicectl.
/// PNGs and an explicit success marker are saved in tmp/tab-badges.
/// The eight-second lead leaves time to start the headless recorder.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final out = Directory('${Directory.systemTemp.path}/tab-badges');
  out.createSync(recursive: true);
  final result = File('${out.path}/result.json');
  await result.writeAsString(jsonEncode({'complete': false}));
  await MorphGlassRenderer.precache();
  if (!MorphGlassRenderer.liquidAvailable) {
    throw StateError('The capture requires the real liquid renderer.');
  }
  var selected = 0;
  final key = GlobalKey();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light),
      builder: (_, child) => MorphAdaptiveGlass(
        tier: MorphGlassTier.liquid,
        child: BackdropGroup(child: MorphScope(child: child!)),
      ),
      home: StatefulBuilder(
        builder: (_, set) => ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 21,
                child: Center(
                  child: MorphTabBar(
                    key: key,
                    items: const [
                      MorphTabItem(icon: Icons.home_rounded, label: 'Home'),
                      MorphTabItem(
                        icon: Icons.library_music_rounded,
                        label: 'Library',
                        badge: MorphBadge.count(3),
                      ),
                      MorphTabItem(
                        icon: Icons.radio_rounded,
                        label: 'Radio',
                        badge: MorphBadge.indicator(),
                      ),
                    ],
                    selected: selected,
                    onChanged: (value) => set(() => selected = value),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 8));
  Future<void> shot(String name) async {
    await WidgetsBinding.instance.endOfFrame;
    final bytes = await const MethodChannel(
      'plugins.flutter.io/integration_test',
    ).invokeMethod<List<int>>('captureScreenshot', {'name': name});
    if (bytes == null) {
      throw StateError('No screenshot for $name.');
    }
    await File('${out.path}/$name.png').writeAsBytes(bytes);
  }

  Duration stamp() =>
      Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
  const pointer = 101;
  final bar = key.currentContext!.findRenderObject()! as RenderBox;
  final number = bar.localToGlobal(bar.size.center(Offset.zero));
  // The measured three-tab pitch (tab-bar passport).
  final dot = number + const Offset(86, 0);
  await shot('rest');
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(pointer: pointer, position: number, timeStamp: stamp()),
  );
  await Future<void>.delayed(const Duration(seconds: 2));
  if (selected != 1) {
    throw StateError('The count tab did not select on contact.');
  }
  await shot('held-number');
  var previous = number;
  for (var i = 1; i <= 120; i++) {
    final point = Offset.lerp(number, dot, i / 120)!;
    GestureBinding.instance.handlePointerEvent(
      PointerMoveEvent(
        pointer: pointer,
        position: point,
        delta: point - previous,
        buttons: kPrimaryButton,
        timeStamp: stamp(),
      ),
    );
    previous = point;
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  await shot('held-dot');
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(pointer: pointer, position: dot, timeStamp: stamp()),
  );
  await Future<void>.delayed(const Duration(seconds: 2));
  if (selected != 2) {
    throw StateError('The dot tab did not select on release.');
  }
  await shot('returned');
  await result.writeAsString(
    jsonEncode({'complete': true, 'liquid_available': true}),
  );
}
