import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// Opens and closes a centered three-row menu on a schedule for a screen
/// recording, mirroring the probe's `center3-repeat` and
/// `center3-closemidopen` captures: the gallery's glass, the phone's
/// appearance, the button at the center of the screen.
///
/// Build it as a profile app (`flutter build ios --profile -t
/// integration_test/menu_video_test.dart`), launch it with devicectl and
/// record the screen while it runs; it waits [_lead] before the first tap.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('menu video', (WidgetTester tester) async {
    await LiquidGlass.precache();
    runApp(const GalleryApp());
    await tester.pump(const Duration(seconds: 2));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const _Page(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final button = tester.getCenter(find.byType(MorphMenuButton));
    final outside = Offset(
      tester.getSize(find.byType(Scaffold).last).width - 50,
      tester.getSize(find.byType(Scaffold).last).height - 120,
    );
    var pointer = 1;
    Future<void> tap(Offset at, int holdMs) async {
      final gesture = await tester.createGesture(pointer: pointer++);
      await gesture.down(at);
      await tester.pump(Duration(milliseconds: holdMs));
      await gesture.up();
    }

    await tester.pump(_lead);
    for (var i = 0; i < 4; i++) {
      await tap(button, 100);
      await tester.pump(const Duration(milliseconds: 1600));
      await tap(outside, 60);
      await tester.pump(const Duration(milliseconds: 1600));
    }
    for (var i = 0; i < 2; i++) {
      await tap(button, 100);
      await tester.pump(const Duration(milliseconds: 55));
      await tap(outside, 10);
      await tester.pump(const Duration(milliseconds: 1600));
    }
    await tester.pump(const Duration(seconds: 2));
  });
}

const _lead = Duration(
  seconds: int.fromEnvironment('VIDEO_LEAD', defaultValue: 8),
);

class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: galleryBackgroundColor(Theme.of(context).brightness),
      body: const Center(
        child: MorphMenuButton(
          items: [
            MorphMenuItem(title: 'Copy', icon: Icons.copy),
            MorphMenuItem(title: 'Share', icon: Icons.ios_share),
            MorphMenuItem(
              title: 'Delete',
              icon: Icons.delete_outline,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  }
}
