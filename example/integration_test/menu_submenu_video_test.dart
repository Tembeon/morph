import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// Plays the probe's `MenuAPIUITests.testMenuFilm` schedule on a morph
/// menu for a screen recording beside the native film: the probe's `sub`
/// menu (Copy, Share, More > (Sub one, Sub two, Deeper > (Deep one, Deep
/// two)), Delete) under a 48 pt glass button centered 150 pt from the
/// top, dark then light. Per appearance: open, More, the card's header
/// (back), outside; open, More, outside; open, More, Sub one; open,
/// More, Deeper, outside - at the probe's touch times.
///
/// Build it as a profile app (`flutter build ios --profile -t
/// integration_test/menu_submenu_video_test.dart`), launch it with
/// devicectl and record the screen; it waits [_lead] before the first
/// pass.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('menu submenu video', (WidgetTester tester) async {
    await MorphGlassRenderer.precache();
    runApp(const GalleryApp());
    await tester.pump(const Duration(seconds: 2));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final settings = GalleryGlassScope.of(
      tester.element(find.byType(Navigator)),
    );
    var pointer = 1;
    final clock = Stopwatch();
    clock.start();
    Future<void> until(double seconds) async {
      final left = seconds * 1000 - clock.elapsedMilliseconds;
      if (left > 0) await tester.pump(Duration(milliseconds: left.round()));
    }

    Future<void> tap(double at, Offset position) async {
      await until(at);
      final gesture = await tester.createGesture(pointer: pointer++);
      await gesture.down(position);
      await until(at + 0.083);
      await gesture.up();
    }

    await tester.pump(_lead);
    for (final mode in const [ThemeMode.dark, ThemeMode.light]) {
      settings.appearance = mode;
      unawaited(
        navigator.push(
          PageRouteBuilder<void>(
            pageBuilder: (context, _, _) => const _Page(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      clock.reset();
      for (final (at, position) in _schedule) {
        await tap(at, position);
      }
      await until(_schedule.last.$1 + 2);
      navigator.pop();
      await tester.pump(const Duration(seconds: 1));
    }
  });
}

const _lead = Duration(
  seconds: int.fromEnvironment('VIDEO_LEAD', defaultValue: 8),
);

const _button = Offset(201, 150);
const _more = Offset(201, 238);
const _outside = Offset(201, 820);

const _schedule = [
  (0.0, _button),
  (1.810, _more),
  (3.621, Offset(201, 232.67)),
  (5.433, _outside),
  (7.547, _button),
  (9.354, _more),
  (11.165, _outside),
  (13.279, _button),
  (15.089, _more),
  (16.902, Offset(201, 294.67)),
  (19.012, _button),
  (20.826, _more),
  (22.639, Offset(201, 378.67)),
  (24.444, _outside),
];

class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: galleryBackgroundColor(Theme.of(context).brightness),
      body: Stack(
        children: [
          Positioned(
            left: _button.dx - 24,
            top: _button.dy - 24,
            child: const SizedBox(
              width: 48,
              height: 48,
              child: MorphMenuButton(
                items: [
                  MorphMenuItem(title: 'Copy', icon: Icons.copy),
                  MorphMenuItem(title: 'Share', icon: Icons.ios_share),
                  MorphSubmenu(
                    title: 'More',
                    icon: Icons.folder_outlined,
                    children: [
                      MorphMenuItem(
                        title: 'Sub one',
                        icon: Icons.looks_one_outlined,
                      ),
                      MorphMenuItem(
                        title: 'Sub two',
                        icon: Icons.looks_two_outlined,
                      ),
                      MorphSubmenu(
                        title: 'Deeper',
                        icon: Icons.more_horiz,
                        children: [
                          MorphMenuItem(title: 'Deep one'),
                          MorphMenuItem(title: 'Deep two'),
                        ],
                      ),
                    ],
                  ),
                  MorphMenuItem(
                    title: 'Delete',
                    icon: Icons.delete_outline,
                    destructive: true,
                  ),
                ],
              ),
            ),
          ),
          Positioned(right: 18, top: top + 8, child: const _Spinner()),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const MorphActivityIndicator();
}
