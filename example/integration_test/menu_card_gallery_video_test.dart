import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/menu_page.dart';

/// Records the gallery Options menu's More hand-back and nested platters
/// on the phone, after an eight-second recorder lead. Parent scroll offsets
/// are saved to the app's tmp/menu_gallery_scroll.json.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('gallery submenu bounds video', (WidgetTester tester) async {
    await MorphGlassRenderer.precache();
    runApp(const GalleryApp());
    await tester.pump(const Duration(seconds: 2));
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    final settings = GalleryGlassScope.of(
      tester.element(find.byType(Navigator).first),
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
    final offsets = <Map<String, Object?>>[];
    var rootOffset = 0.0;
    ScrollController scroll() => tester
        .widget<CustomScrollView>(find.byType(CustomScrollView).last)
        .controller!;
    void record(String label) => offsets.add({
      'phase': label,
      'elapsed': clock.elapsedMicroseconds / 1e6,
      'offset': scroll().offset,
    });
    Future<void> parentDrag() async {
      final viewport = tester.getRect(find.byType(CustomScrollView).last);
      final title = find.text('Desktop').evaluate().isEmpty
          ? 'Rename'
          : 'Desktop';
      final offset = scroll().offset;
      mark('parent drag');
      await tester.dragFrom(
        Offset(viewport.center.dx, viewport.top + 90),
        const Offset(0, -60),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(scroll().offset, closeTo(offset, 0.5));
      expect(find.text(title), findsOneWidget);
      record('parent drag');
    }

    Future<void> parentTap(int cards) async {
      final viewport = tester.getRect(find.byType(CustomScrollView).last);
      mark('parent tap');
      await tester.tapAt(Offset(viewport.center.dx, viewport.top + 90));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Desktop'), findsNothing);
      expect(find.text('Rename'), cards == 2 ? findsOneWidget : findsNothing);
      expect(scroll().offset, closeTo(rootOffset, 0.5));
      record('parent tap to $cards cards');
    }

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
    record('scrolled root');
    rootOffset = scroll().offset;
    await tap('More');
    expect(scroll().offset, closeTo(rootOffset, 0.5));
    record('More open');
    await parentDrag();
    await tap('Move to');
    record('Move to open');
    await parentDrag();
    await parentTap(2);
    await parentTap(1);
    await tap('More');
    await tap('Move to');
    expect(scroll().offset, closeTo(rootOffset, 0.5));
    File(
      '${Directory.systemTemp.path}/menu_gallery_scroll.json',
    ).writeAsStringSync(jsonEncode(offsets));
    mark('outside');
    await tester.tapAt(const Offset(201, 840));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(CustomScrollView), findsNothing);
    mark('done');
  });
}
