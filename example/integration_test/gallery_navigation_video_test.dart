import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// The owner's scenario on the gallery for a screen recording: the home
/// scrolled 250 points (its scroll edge effect on under the bar), the
/// Navigation page pushed - a back button, [plus more] and the slow-motion
/// button [1x] - and popped back, three times, 2.4 s apart.
///
/// Build it as a profile app (`flutter build ios --profile -t
/// integration_test/gallery_navigation_video_test.dart`), launch it with
/// devicectl and record the screen while it runs; it waits [_lead] before
/// the first push.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('gallery navigation video', (WidgetTester tester) async {
    await MorphGlassRenderer.precache();
    final navigator = GlobalKey<NavigatorState>();
    runApp(GalleryApp(navigatorKey: navigator));
    await tester.pump(const Duration(seconds: 1));
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(250);
    await tester.pump(_lead);
    final entry = galleryEntries.firstWhere((e) => e.title == 'Navigation');
    for (var i = 0; i < 3; i++) {
      unawaited(
        navigator.currentState!.push(
          MorphNavigationRoute<void>(builder: entry.builder),
        ),
      );
      await tester.pump(_gap);
      navigator.currentState!.pop();
      await tester.pump(_gap);
    }
    await tester.pump(const Duration(seconds: 2));
  });
}

const Duration _lead = Duration(seconds: 4);
const Duration _gap = Duration(milliseconds: 2400);
