import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// Pushes and pops the five pages of the probe's `navseg` scene on its
/// schedule for a screen recording next to the native one: page 0 with a
/// large title and one trailing button, 1 with a back button and one
/// trailing button, 2 untitled with a Cancel button and a two-button
/// group, 3 with a back button only, 4 with a large title, a back button
/// and two trailing groups. Four pushes, then four pops, 1.6 s apart.
///
/// With `--dart-define=NAVSEG_SET=b` it runs the probe's set b instead
/// (`PROBE_SET=b`, groups born and dying within a side): 0 with a large
/// title and [1x], scrolled 200 points like `PROBE_ROOTSCROLL=200`; 1 with
/// [plus more] [1x]; 2 with [Show Preferences]; 3 with [heart] [Show
/// Preferences]; 4 with [heart bookmark] [share] [more].
///
/// Build it as a profile app (`flutter build ios --profile -t
/// integration_test/navseg_video_test.dart`), launch it with devicectl and
/// record the screen while it runs; it waits [_lead] before the first
/// push.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('navseg video', (WidgetTester tester) async {
    await MorphGlassRenderer.precache();
    final navigator = GlobalKey<NavigatorState>();
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark),
        builder: (BuildContext context, Widget? child) => MorphAdaptiveGlass(
          tier: MorphGlassTier.liquid,
          child: BackdropGroup(child: MorphScope(child: child!)),
        ),
        home: MorphNavigationStack(
          navigatorKey: navigator,
          home: const _Page(0),
        ),
      ),
    );
    if (_setB) {
      await tester.pump();
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(200);
    }
    await tester.pump(_lead);
    for (var page = 1; page <= 4; page++) {
      unawaited(
        navigator.currentState!.push(
          MorphNavigationRoute<void>(builder: (_) => _Page(page)),
        ),
      );
      await tester.pump(_gap);
    }
    for (var i = 0; i < 4; i++) {
      navigator.currentState!.pop();
      await tester.pump(_gap);
    }
    await tester.pump(const Duration(seconds: 2));
  });
}

const Duration _lead = Duration(seconds: 4);
const bool _setB = String.fromEnvironment('NAVSEG_SET') == 'b';
const Duration _gap = Duration(milliseconds: 1600);

MorphBarButton _icon(String id, IconData icon) => MorphBarButton(
  id: id,
  icon: Icon(icon),
  semanticLabel: id,
  onPressed: () {},
);

class _Page extends StatelessWidget {
  const _Page(this.page);

  final int page;

  static const List<Color> _stripes = [
    Color(0xD9FF3B30),
    Color(0xD9FF9500),
    Color(0xD9FFCC00),
    Color(0xD934C759),
    Color(0xD930B0C7),
    Color(0xD9007AFF),
    Color(0xD95856D6),
    Color(0xD9AF52DE),
    Color(0xD9FF2D55),
    Color(0xFF000000),
    Color(0xFFFFFFFF),
  ];

  @override
  Widget build(BuildContext context) {
    final slivers = [
      SliverList.builder(
        itemCount: 30,
        itemBuilder: (BuildContext context, int i) => Container(
          height: 44,
          color: _stripes[(i + page * 2) % _stripes.length],
        ),
      ),
    ];
    if (_setB) return _pageB(slivers);
    return switch (page) {
      0 => MorphNavigationScaffold(
        title: 'Root',
        largeTitle: true,
        backTitle: '',
        trailing: [
          MorphBarButtonGroup([_icon('plus', Icons.add)]),
        ],
        slivers: slivers,
      ),
      1 => MorphNavigationScaffold(
        title: 'Alpha',
        backTitle: '',
        trailing: [
          MorphBarButtonGroup([_icon('share', Icons.ios_share)]),
        ],
        slivers: slivers,
      ),
      2 => MorphNavigationScaffold(
        title: '',
        backTitle: '',
        leading: MorphBarButtonGroup([
          MorphBarButton(
            id: 'cancel',
            label: 'Cancel',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ]),
        trailing: [
          MorphBarButtonGroup([
            _icon('share2', Icons.ios_share),
            _icon('heart', Icons.favorite_border),
          ]),
        ],
        slivers: slivers,
      ),
      3 => MorphNavigationScaffold(
        title: 'Gamma',
        backTitle: '',
        slivers: slivers,
      ),
      _ => MorphNavigationScaffold(
        title: 'Delta',
        largeTitle: true,
        trailing: [
          MorphBarButtonGroup([_icon('heart4', Icons.favorite_border)]),
          MorphBarButtonGroup([
            MorphBarButton(id: 'done', label: 'Done', onPressed: () {}),
          ], prominent: true),
        ],
        slivers: slivers,
      ),
    };
  }

  Widget _pageB(List<Widget> slivers) {
    MorphBarButton text(String id, String label) =>
        MorphBarButton(id: id, label: label, onPressed: () {});
    final prefs = MorphBarButtonGroup([text('prefs$page', 'Show Preferences')]);
    return switch (page) {
      0 => MorphNavigationScaffold(
        title: 'One',
        largeTitle: true,
        backTitle: '',
        trailing: [
          MorphBarButtonGroup([text('x0', '1x')]),
        ],
        slivers: slivers,
      ),
      1 => MorphNavigationScaffold(
        title: 'Two',
        backTitle: '',
        trailing: [
          MorphBarButtonGroup([
            _icon('plus', Icons.add),
            _icon('more', Icons.more_horiz),
          ]),
          MorphBarButtonGroup([text('x1', '1x')]),
        ],
        slivers: slivers,
      ),
      2 => MorphNavigationScaffold(
        title: 'Three',
        backTitle: '',
        trailing: [prefs],
        slivers: slivers,
      ),
      3 => MorphNavigationScaffold(
        title: 'Four',
        backTitle: '',
        trailing: [
          MorphBarButtonGroup([_icon('heart3', Icons.favorite_border)]),
          prefs,
        ],
        slivers: slivers,
      ),
      _ => MorphNavigationScaffold(
        title: 'Five',
        trailing: [
          MorphBarButtonGroup([
            _icon('heart4', Icons.favorite_border),
            _icon('bookmark4', Icons.bookmark_border),
          ]),
          MorphBarButtonGroup([_icon('share4', Icons.ios_share)]),
          MorphBarButtonGroup([_icon('more4', Icons.more_horiz)]),
        ],
        slivers: slivers,
      ),
    };
  }
}
