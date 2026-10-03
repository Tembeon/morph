import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/liquid_glass.dart';

/// The probe's search and date picker scenes (tool/ios_reference
/// Extras.swift: `x3search`, `x3date`) rebuilt with morph's widgets in the
/// gallery's glass, for XCUITest to drive with real touches and the real
/// keyboard: `ExtrasUITests.testX3Video` with `PROBE_BUNDLE` set to this
/// app runs the same schedule on it as on the native scenes while
/// MorphRecorder films the screen.
///
/// Build it as a profile app (`flutter build ios --profile -t
/// integration_test/search_date_scenes.dart`). The app opens on a board
/// of scene buttons the UI test taps by position: a row per scene
/// ([scenes]: the toolbar search, the tab bar search without and with
/// activation, the date, time and date-and-time pickers) 70 points apart
/// from 150 points down, light at x 100 and dark at x 300. Every scene
/// keeps a spinner turning at the top trailing corner, as the probe's
/// scenes do under PROBE_SPINNER, so the recorder never sees a still
/// screen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await precacheLiquidGlass();
  final navigatorKey = GlobalKey<NavigatorState>();
  runApp(GalleryApp(navigatorKey: navigatorKey));
  WidgetsBinding.instance.addPostFrameCallback((Duration _) {
    navigatorKey.currentState?.push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const _Board(),
        transitionDuration: Duration.zero,
      ),
    );
  });
}

/// The scenes on the board, top to bottom.
const List<String> scenes = [
  'search',
  'tab',
  'tabauto',
  'date',
  'time',
  'both',
];

Widget _scene(String name) => switch (name) {
  'tab' || 'tabauto' => const _TabPage(),
  'search' => const _SearchPage(),
  'time' => const _DatePage(mode: MorphDatePickerMode.time),
  'both' => const _DatePage(mode: MorphDatePickerMode.dateAndTime),
  _ => const _DatePage(mode: MorphDatePickerMode.date),
};

class _Board extends StatelessWidget {
  const _Board();

  void _open(BuildContext context, String name, {required bool dark}) {
    GalleryGlassScope.of(context).appearance = dark
        ? ThemeMode.dark
        : ThemeMode.light;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        pageBuilder: (BuildContext context, _, _) => Stack(
          children: [
            Positioned.fill(child: _scene(name)),
            Positioned(
              left: MediaQuery.sizeOf(context).width - 30 - 10,
              top: 64 - 10,
              width: 20,
              height: 20,
              child: const MorphActivityIndicator(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          for (var i = 0; i < scenes.length; i++)
            for (final dark in [false, true])
              Positioned(
                left: (dark ? 300 : 100) - 75,
                top: 150 + 70.0 * i - 30,
                width: 150,
                height: 60,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _open(context, scenes[i], dark: dark),
                  child: ColoredBox(
                    color: dark
                        ? const Color(0xFF333333)
                        : const Color(0xFFDDDDDD),
                    child: Center(child: Text(scenes[i])),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

void _nothing() {}

/// The probe's toolbar scene: a large title, forty rows, a toolbar with a
/// filter button, the search field and a compose button.
class _SearchPage extends StatelessWidget {
  const _SearchPage();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    return Scaffold(
      backgroundColor: color,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: _Rows(dark: dark)),
          const Positioned.fill(
            child: MorphSearchToolbar(
              leading: [
                MorphBarButton(
                  id: 'filter',
                  icon: Icon(Icons.filter_list),
                  semanticLabel: 'Filter',
                  onPressed: _nothing,
                ),
              ],
              trailing: [
                MorphBarButton(
                  id: 'compose',
                  icon: Icon(Icons.edit_outlined),
                  semanticLabel: 'Compose',
                  onPressed: _nothing,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final text = dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    final line = dark ? const Color(0x5C545458) : const Color(0x4A3C3C43);
    final top = MediaQuery.paddingOf(context).top;
    return ListView.builder(
      padding: EdgeInsets.only(top: top, bottom: 120),
      itemCount: 41,
      itemBuilder: (BuildContext context, int i) {
        if (i == 0) {
          return Padding(
            padding: const .fromLTRB(16, 52, 16, 8),
            child: Text(
              'Search',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
          );
        }
        return Container(
          height: 44,
          margin: const .only(left: 20),
          alignment: .centerLeft,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: line, width: 0.33)),
          ),
          child: Text(
            'Item ${i - 1}',
            style: TextStyle(fontSize: 17, color: text),
          ),
        );
      },
    );
  }
}

/// The probe's tab scene: Home and Library tabs and a search tab over a
/// page that names the tab.
class _TabPage extends StatefulWidget {
  const _TabPage();

  @override
  State<_TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<_TabPage> {
  int _tab = 0;
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: _searching
                ? _Rows(dark: dark)
                : Center(
                    child: Text(
                      _tab == 0 ? 'Home' : 'Library',
                      style: TextStyle(
                        fontSize: 17,
                        color: dark
                            ? const Color(0xFFFFFFFF)
                            : const Color(0xFF000000),
                      ),
                    ),
                  ),
          ),
          Positioned.fill(
            child: MorphSearchTabBar(
              items: const [
                MorphTabItem(icon: Icons.home_outlined, label: 'Home'),
                MorphTabItem(icon: Icons.library_books, label: 'Library'),
              ],
              selected: _tab,
              onChanged: (int i) => setState(() => _tab = i),
              searching: _searching,
              onSearchingChanged: (bool on) => setState(() => _searching = on),
            ),
          ),
        ],
      ),
    );
  }
}

/// The probe's date scene: one compact picker centered 300 pt from the
/// top on the grouped background, 3 October 2026 7:41 as the value (what
/// the probe's UTC picker shows) and as today.
class _DatePage extends StatefulWidget {
  const _DatePage({required this.mode});

  final MorphDatePickerMode mode;

  @override
  State<_DatePage> createState() => _DatePageState();
}

class _DatePageState extends State<_DatePage> {
  DateTime _value = DateTime(2026, 10, 3, 7, 41);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: galleryBackgroundColor(Theme.of(context).brightness),
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 600,
            child: Center(
              child: MorphDatePicker(
                value: _value,
                mode: widget.mode,
                today: DateTime(2026, 10, 3),
                onChanged: (DateTime v) => setState(() => _value = v),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
