import 'package:flutter/material.dart';

import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';

/// One pill of the demo: identity, geometry, chrome and its menu.
typedef _Pill = ({
  String id,
  Rect home,
  IconData icon,
  String label,
  List<(IconData, String)> items,
  bool dangerLast,
});

/// The iOS 26 staple: a button that becomes ITS OWN menu. The pill's
/// surface expands into the popover (anchored to where the button
/// stands - a custom MorphTargetSpec closing over the button's rect),
/// the items cascade in on the same spring, and closing collapses the
/// menu back into the pill. Identity is never broken: the thing you
/// tapped is the thing you use.
class MenuLesson extends StatefulWidget {
  /// Creates the chapter demo.
  const MenuLesson({super.key, required this.motion});

  /// Motion profile of the demo springs and flights.
  final MorphMotion motion;

  @override
  State<MenuLesson> createState() => _MenuLessonState();
}

class _MenuLessonState extends State<MenuLesson> {
  static const Color _glass = Color(0xFF2A2440);
  static const MorphSurfaceSpec _menu = MorphSurfaceSpec(
    shape: RoundedRectangleBorder(borderRadius: .all(.circular(20))),
    color: Color(0xFF262038),
    elevation: 16,
  );

  // The blend is the reach of the fusion - a distance in px, tuned per
  // scene (goo's 42 suits dock-scale bodies; button-scale UI wants
  // less). Here it demoes the floating-button-near-a-bar case: the
  // pills rest 17 px apart with blend 14 - just far enough to stay
  // provably separate and out of each other's launch fellowship, and
  // close enough that a real pull's few px of travel brings the gap
  // under the blend: the skin necks them into one body. The tether
  // itself rides the package defaults - the liquid-glass reference
  // feel - and the panel knobs expose the material for calibration.
  static const double _blend = 14;

  double _give = 0.05;
  double _stretch = 0.08;
  double _jiggle = 0.003;
  double _pressGrow = 4;

  static const List<_Pill> _pills = <_Pill>[
    (
      id: 'menu-pill',
      home: Rect.fromLTWH(29, 53, 132, 44),
      icon: Icons.tune_rounded,
      label: 'Options',
      items: <(IconData, String)>[
        (Icons.push_pin_outlined, 'Pin'),
        (Icons.drive_file_rename_outline_rounded, 'Rename'),
        (Icons.copy_rounded, 'Duplicate'),
        (Icons.ios_share_rounded, 'Share'),
        (Icons.delete_outline_rounded, 'Delete'),
      ],
      dangerLast: true,
    ),
    (
      id: 'share-pill',
      home: Rect.fromLTWH(178, 53, 112, 44),
      icon: Icons.ios_share_rounded,
      label: 'Share',
      items: <(IconData, String)>[
        (Icons.wifi_tethering_rounded, 'AirDrop'),
        (Icons.link_rounded, 'Copy link'),
        (Icons.image_outlined, 'Save image'),
      ],
      dangerLast: false,
    ),
  ];

  // Each pill's tug writes its geometry channel directly: the skin
  // re-traces the displaced mass on every frame of a drag with no
  // lesson rebuild at all - only the material knobs rebuild the pills.
  final Map<String, MorphPieceChannel> _channels = <String, MorphPieceChannel>{
    for (final _Pill pill in _pills) pill.id: MorphPieceChannel(),
  };

  String _lastAction = 'nothing yet';

  @override
  void dispose() {
    for (final MorphPieceChannel channel in _channels.values) {
      channel.dispose();
    }
    super.dispose();
  }

  void _openMenu(BuildContext buttonContext, _Pill pill) {
    // One call: the popover anchors to the button's CURRENT box (a
    // tugged pill opens its menu wherever it stands), rows cascade on
    // the flight's own spring.
    showMorphMenu(
      buttonContext,
      motion: widget.motion,
      semanticLabel: '${pill.label} menu',
      surface: _menu,
      items: <MorphMenuItem>[
        for (int i = 0; i < pill.items.length; i++)
          MorphMenuItem(
            icon: pill.items[i].$1,
            label: pill.items[i].$2,
            tint: pill.dangerLast && i == pill.items.length - 1
                ? const Color(0xFFFF7A83)
                : null,
            onSelected: () => _onAction(pill.items[i].$2.toLowerCase()),
          ),
      ],
    );
  }

  void _onAction(String action) {
    if (mounted) {
      setState(() => _lastAction = action);
    }
  }

  Widget _pillContent(_Pill pill) {
    return Tug(
      motion: widget.motion,
      give: _give,
      stretch: _stretch,
      jiggle: _jiggle,
      pressGrow: _pressGrow,
      channel: _channels[pill.id],
      // The skin IS the surface ("one mass - one shadow"): the piece
      // content carries no Material of its own - a second surface
      // would split from the mass the moment the tug deforms it.
      child: MorphTapTarget(
        label: pill.label,
        onTap: (BuildContext buttonContext) => _openMenu(buttonContext, pill),
        child: Center(
          child: Row(
            mainAxisSize: .min,
            children: <Widget>[
              Icon(pill.icon, size: 17),
              const SizedBox(width: 8),
              Text(
                pill.label,
                style: const TextStyle(fontSize: 13.5, fontWeight: .w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SceneScaffold(
      controls: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          const PanelHint(
            'Tap a pill: its own surface expands into the popover, '
            'anchored to wherever the pill currently stands - the thing '
            'you touch becomes the menu you use. Rows cascade on the '
            'same spring.',
          ),
          const PanelHint(
            'The pills ride a leash (Tug in channel mode): heavy from '
            'the first pixel, the flesh answers more than the body '
            'moves. Drag one toward the other and the skin necks them '
            'into one body - real mass, not a paint effect.',
          ),
          PanelSection(
            label: 'MATERIAL',
            child: Column(
              children: <Widget>[
                PanelKnob(
                  label: 'give',
                  value: _give,
                  min: 0.02,
                  max: 0.2,
                  format: (double v) => v.toStringAsFixed(3),
                  onChanged: (double v) => setState(() => _give = v),
                ),
                PanelKnob(
                  label: 'stretch',
                  value: _stretch,
                  min: 0,
                  max: 0.25,
                  format: (double v) => v.toStringAsFixed(3),
                  onChanged: (double v) => setState(() => _stretch = v),
                ),
                PanelKnob(
                  label: 'jiggle',
                  value: _jiggle,
                  min: 0,
                  max: 0.008,
                  format: (double v) => '${(v * 1000).toStringAsFixed(1)}ms',
                  onChanged: (double v) => setState(() => _jiggle = v),
                ),
                PanelKnob(
                  label: 'press',
                  value: _pressGrow,
                  min: -6,
                  max: 10,
                  format: (double v) => '${v.toStringAsFixed(1)}px',
                  onChanged: (double v) => setState(() => _pressGrow = v),
                ),
              ],
            ),
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
            // One skin, two morphable pieces: the tug (channel mode)
            // moves the real piece mass through its geometry channel,
            // so dragging a pill toward its neighbor necks the two into
            // one body - and each pill still morphs into its own menu
            // from wherever it stands.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: SizedBox(
                  width: 320,
                  height: 150,
                  child: MorphSkin(
                    blend: _blend,
                    color: _glass,
                    elevation: 3,
                    contentFilterQuality: FilterQuality.high,
                    pieces: <MorphPiece>[
                      for (int i = 0; i < _pills.length; i++)
                        MorphPiece.morphable(
                          id: _pills[i].id,
                          rect: _pills[i].home,
                          radius: _pills[i].home.height / 2,
                          channel: _channels[_pills[i].id],
                          child: _pillContent(_pills[i]),
                        ),
                    ],
                  ),
                ),
              ),
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
