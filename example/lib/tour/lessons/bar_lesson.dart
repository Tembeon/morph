import 'package:material_ui/material_ui.dart';

import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';
import 'package:morph_example/tour/lessons/dialog_contents.dart';

/// The floating-bar case: a [MorphTabBar] whose selection is a liquid
/// lens moving exactly like iOS 27's UITabBar, with a send companion
/// beside it - a [MorphGlassButton] that is also a real morph source,
/// its compose dialog flying out of the glass you pressed.
///
/// The bar's lens selects on contact, stays lifted while the finger is
/// down, carries between tabs under a drag and lands on release; the
/// whole bar swells while pressed. Every one of those springs is
/// measured from the platform's own control.
class BarLesson extends StatefulWidget {
  /// Creates the chapter demo.
  const BarLesson({super.key});

  @override
  State<BarLesson> createState() => _BarLessonState();
}

class _BarLessonState extends State<BarLesson> {
  static const Color _glass = Color(0xFF2A2440);
  static const Color _accent = Color(0xFFA48BFF);
  static const double _sendSize = 62;

  static const List<MorphTabItem> _tabs = <MorphTabItem>[
    MorphTabItem(icon: Icons.library_music_rounded, label: 'Library'),
    MorphTabItem(icon: Icons.mail_rounded, label: 'Mail'),
    MorphTabItem(icon: Icons.person_rounded, label: 'Profile'),
  ];

  static const MorphTabBarStyle _barStyle = MorphTabBarStyle(
    barColor: Color(0xE62A2440),
    shadowColor: Color(0x52000000),
    platterColor: Color(0x24FFFFFF),
    liftedLensColor: Color(0x33FFFFFF),
    lensBorderColor: Color(0x40FFFFFF),
    selectedColor: _accent,
    color: Color(0xB3FFFFFF),
  );

  int _selected = 0;

  void _compose(BuildContext buttonContext) {
    showMorphDialog(
      buttonContext,
      from: 'bar-send',
      width: 306,
      height: 420,
      motion: MorphMotion.liquid,
      semanticLabel: 'New message',
      builder: (BuildContext context, MorphFlight flight) =>
          ComposeDialogContent(flight: flight),
    );
  }

  Widget _send() {
    return MorphTag(
      id: 'bar-send',
      spec: const MorphSurfaceSpec(
        shape: CircleBorder(),
        color: _glass,
        elevation: 0,
      ),
      child: Builder(
        builder: (BuildContext context) => MorphGlassButton(
          tint: _glass,
          padding: .zero,
          minSize: const Size.square(_sendSize),
          onPressed: () => _compose(context),
          child: const Icon(Icons.send_rounded, size: 22, color: _accent),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SceneScaffold(
      controls: const Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          PanelHint(
            'Touch a tab: the lens selects on contact and lifts off the '
            'bar while the finger is down. Drag along the bar and the '
            'lifted lens travels under the finger; let go and it lands '
            'on the tab beneath. The whole bar swells a little while '
            'pressed - all of it on springs measured from the iOS tab '
            'bar.',
          ),
          PanelHint(
            'The send button is a glass button with the measured press: '
            'a uniform lift that depends on its size. It is also a real '
            'morph source - the compose dialog flies out of it and lands '
            'back in it.',
          ),
        ],
      ),
      phone: PhoneFrame(
        app: (BuildContext context) => Stack(
          children: <Widget>[
            _Skeleton(tab: _tabs[_selected].label, seed: _selected),
            Positioned(
              left: 12,
              right: 12,
              bottom: 14,
              child: FittedBox(
                fit: .scaleDown,
                child: Row(
                  mainAxisSize: .min,
                  children: <Widget>[
                    MorphTabBar(
                      items: _tabs,
                      selected: _selected,
                      style: _barStyle,
                      onChanged: (int i) => setState(() => _selected = i),
                    ),
                    const SizedBox(width: 12),
                    _send(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The set dressing: a content skeleton so the bar reads as an app's
/// chrome, not an isolated toy.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.tab, required this.seed});

  final String tab;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        Padding(
          padding: const .fromLTRB(20, 12, 20, 10),
          child: Text(
            tab,
            style: const TextStyle(fontSize: 24, fontWeight: .w800),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const .fromLTRB(14, 0, 14, 96),
            itemCount: 7,
            itemBuilder: (BuildContext context, int index) => Padding(
              padding: const .only(bottom: 10),
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: .circular(14),
                  color: Colors.white.withValues(
                    alpha: 0.03 + 0.015 * ((index + seed) % 3),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
