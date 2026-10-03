import 'package:material_ui/material_ui.dart';

import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';

/// The iOS 26 staple: a button that becomes ITS OWN menu. A photo app's
/// floating toolbar carries a glass button and two menu buttons; a tap
/// on a menu button morphs its glass into the menu (a hold opens it too,
/// and lets the finger slide onto a row and pick it on release), and
/// closing absorbs the menu back into the button. Identity is never
/// broken: the thing you tapped is the thing you use.
///
/// Every spring here is UIKit's own, measured: [MorphGlassButton]'s
/// size-dependent lift and [MorphMenuButton]'s `liquidMorph` tuning.
class MenuLesson extends StatefulWidget {
  /// Creates the chapter demo.
  const MenuLesson({super.key});

  @override
  State<MenuLesson> createState() => _MenuLessonState();
}

class _MenuLessonState extends State<MenuLesson> {
  static const Color _glass = Color(0xFF2A2440);
  static const Color _danger = Color(0xFFFF7A83);

  static const MorphMenuStyle _menu = MorphMenuStyle(
    glassColor: Color(0xF2302A44),
    shadowColor: Color(0x66000000),
    textStyle: TextStyle(
      fontSize: 17,
      letterSpacing: -0.4,
      color: Color(0xFFFFFFFF),
    ),
    iconColor: Color(0xFFFFFFFF),
    destructiveColor: _danger,
    highlightColor: Color(0x24FFFFFF),
  );

  static const List<(IconData, String)> _options = <(IconData, String)>[
    (Icons.push_pin_outlined, 'Pin'),
    (Icons.drive_file_rename_outline_rounded, 'Rename'),
    (Icons.copy_rounded, 'Duplicate'),
    (Icons.delete_outline_rounded, 'Delete'),
  ];

  static const List<(IconData, String)> _share = <(IconData, String)>[
    (Icons.wifi_tethering_rounded, 'AirDrop'),
    (Icons.link_rounded, 'Copy link'),
    (Icons.image_outlined, 'Save image'),
  ];

  String _lastAction = 'nothing yet';
  bool _selecting = false;

  void _onAction(String action) {
    if (mounted) {
      setState(() => _lastAction = action);
    }
  }

  List<MorphMenuItem> _items(List<(IconData, String)> rows) {
    return <MorphMenuItem>[
      for (final (IconData icon, String title) in rows)
        MorphMenuItem(
          title: title,
          icon: icon,
          destructive: title == 'Delete',
          onSelected: () => _onAction(title.toLowerCase()),
        ),
    ];
  }

  Widget _toolbar() {
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        MorphGlassButton(
          tint: _glass,
          minSize: const Size(0, 48),
          onPressed: () {
            setState(() => _selecting = !_selecting);
            _onAction(_selecting ? 'select' : 'done');
          },
          child: Text(_selecting ? 'Done' : 'Select'),
        ),
        const SizedBox(width: 12),
        MorphMenuButton(
          style: _menu,
          semanticLabel: 'Share',
          items: _items(_share),
          child: const Icon(
            Icons.ios_share_rounded,
            size: 20,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        MorphMenuButton(
          style: _menu,
          semanticLabel: 'Options',
          items: _items(_options),
          child: const Icon(Icons.tune_rounded, size: 20, color: Colors.white),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SceneScaffold(
      controls: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          const PanelHint(
            'Tap a round button: its own glass grows into the menu, '
            'anchored where the button stands - the thing you touch '
            'becomes the menu you use. Below the middle of the screen it '
            'opens upward with its rows reversed.',
          ),
          const PanelHint(
            'Hold instead of tapping: the menu opens under the finger, '
            'slide onto a row and let go to pick it. Every spring is '
            'measured from UIKit - the press lift depends on the '
            'button\'s size, the morph is the liquidMorph tuning.',
          ),
          PanelSection(
            label: 'LAST ACTION',
            child: Text(
              _lastAction,
              style: const TextStyle(fontSize: 12.5, fontWeight: .w600),
            ),
          ),
        ],
      ),
      phone: PhoneFrame(
        app: (BuildContext context) => Stack(
          children: <Widget>[
            const _Gallery(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(child: _toolbar()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The set dressing: a photo grid the toolbar pills float over.
class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        const Padding(
          padding: .fromLTRB(20, 12, 20, 10),
          child: Text(
            'Recents',
            style: TextStyle(fontSize: 24, fontWeight: .w800),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const .fromLTRB(14, 0, 14, 130),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: 15,
            itemBuilder: (BuildContext context, int index) {
              final Color a = Color.lerp(
                const Color(0xFF7C5CFF),
                const Color(0xFF4CC5B8),
                (index % 7) / 6,
              )!;
              final Color b = Color.lerp(
                const Color(0xFF2A2440),
                const Color(0xFF1C3A45),
                ((index * 3) % 5) / 4,
              )!;
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: .circular(10),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      a.withValues(alpha: 0.35),
                      b.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
