import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/menu_page.dart';

/// Records the gallery Options menu's More hand-back and nested platters
/// on the phone, after an eight-second recorder lead.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('gallery submenu bounds video', (WidgetTester tester) async {
    await MorphGlassRenderer.precache();
    runApp(const GalleryApp());
    await tester.pump(const Duration(seconds: 2));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final settings = GalleryGlassScope.of(
      tester.element(find.byType(Navigator)),
    );
    settings.appearance = ThemeMode.light;
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const Stack(
            children: [
              MenuPage(),
              Positioned(
                right: 72,
                top: 70,
                child: IgnorePointer(child: MorphActivityIndicator()),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 8));
    final clock = Stopwatch();
    clock.start();
    void mark(String label) =>
        debugPrint('MENU_GALLERY $label ${clock.elapsedMicroseconds / 1e6}');
    Future<void> tap(String title) async {
      mark(title);
      await tester.tapAt(tester.getCenter(find.text(title).last));
      await tester.pump(const Duration(seconds: 2));
    }

    final options = find.byWidgetPredicate(
      (Widget widget) =>
          widget is MorphMenuButton && widget.semanticLabel == 'Options',
    );
    mark('Options');
    await tester.tap(options);
    await tester.pump(const Duration(seconds: 2));
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -330),
    );
    await tester.pump(const Duration(seconds: 2));
    await tap('More');
    await tap('Move to');
    await tap('Move to');
    await tap('More');
    mark('outside');
    await tester.tapAt(const Offset(201, 840));
    await tester.pump(const Duration(seconds: 3));
    mark('done');
  });
}
