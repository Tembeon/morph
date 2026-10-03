import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/menu_page.dart';

/// Opens and dismisses menus for a screen recording beside the probe's
/// `MenuAnchorUITests`: a bottom-centre button with ten rows, a top-left
/// one with ten, the top corners and the centre with three rows, placed as the probe places
/// them (20 pt from the safe area's sides, 80 below its top, 20 above its
/// bottom), then the gallery's Menu page with its bottom-centre ten-row
/// button.
///
/// Build it as a profile app (`flutter build ios --profile -t
/// integration_test/menu_anchor_video_test.dart`), launch it with
/// devicectl and record the screen; it waits [_lead] before the first
/// scene.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('menu anchor video', (WidgetTester tester) async {
    await LiquidGlass.precache();
    runApp(const GalleryApp());
    await tester.pump(const Duration(seconds: 2));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    var pointer = 1;
    Future<void> tap(Offset at) async {
      final gesture = await tester.createGesture(pointer: pointer++);
      await gesture.down(at);
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.up();
    }

    Future<void> play(Finder button) async {
      final center = tester.getCenter(button);
      final size = tester.getSize(find.byType(Scaffold).last);
      final outside = Offset(
        center.dx < size.width / 2 ? size.width - 30 : 30,
        center.dy < size.height / 2 ? size.height - 60 : 120,
      );
      for (var i = 0; i < 2; i++) {
        await tap(center);
        await tester.pump(const Duration(milliseconds: 1500));
        await tap(outside);
        await tester.pump(const Duration(milliseconds: 1500));
      }
    }

    await tester.pump(_lead);
    for (final (alignment, items) in _scenes) {
      unawaited(
        navigator.push(
          PageRouteBuilder<void>(
            pageBuilder: (context, _, _) =>
                _Page(alignment: alignment, items: items),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await play(find.byType(MorphMenuButton).last);
      navigator.pop();
      await tester.pump(const Duration(seconds: 1));
    }
    unawaited(
      navigator.push(
        PageRouteBuilder<void>(
          pageBuilder: (context, _, _) => const MenuPage(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await play(
      find.byWidgetPredicate(
        (Widget w) => w is MorphMenuButton && w.items.length == 10,
      ),
    );
    await tester.pump(const Duration(seconds: 2));
  });
}

const _lead = Duration(
  seconds: int.fromEnvironment('VIDEO_LEAD', defaultValue: 8),
);

const _scenes = [
  (Alignment.bottomCenter, 10),
  (Alignment.topLeft, 10),
  (Alignment.topLeft, 3),
  (Alignment.topRight, 3),
  (Alignment.center, 3),
  (Alignment.bottomCenter, 3),
];

const _titles = [
  'Copy',
  'Share',
  'Delete',
  'Rename',
  'Duplicate',
  'Move',
  'Favorite',
  'Pin',
  'Archive',
  'Print',
];

class _Page extends StatelessWidget {
  const _Page({required this.alignment, required this.items});

  final Alignment alignment;
  final int items;

  @override
  Widget build(BuildContext context) {
    final button = MorphMenuButton(
      items: [
        for (final title in _titles.take(items))
          MorphMenuItem(
            title: title,
            icon: Icons.circle_outlined,
            destructive: title == 'Delete',
          ),
      ],
    );
    return Scaffold(
      backgroundColor: galleryBackgroundColor(Theme.of(context).brightness),
      appBar: const GalleryBar(title: 'Menu'),
      body: alignment == Alignment.center
          ? Center(child: button)
          : SafeArea(
              child: Align(
                alignment: alignment,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: alignment.y < 0 ? 80 : 0,
                    bottom: alignment.y > 0 ? 20 : 0,
                  ),
                  child: button,
                ),
              ),
            ),
    );
  }
}
