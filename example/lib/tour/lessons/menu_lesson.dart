import 'package:flutter/material.dart';

import 'package:morph/widgets.dart';

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
  // provably separate and out of each other's launch fellowship - and
  // they ride a longer leash (cap 0.28) so a full tug can push one
  // into the other: contact, not just a neck.
  static const double _blend = 14;
  static const double _tugCap = 0.28;

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

  // Pulls live in a notifier, not in setState: a tug reports on every
  // frame of a drag, and only the piece RECTS depend on it - the pill
  // content below is built once and reused, so a drag re-traces the
  // skin without rebuilding the lesson subtree.
  final ValueNotifier<Map<String, TugPull>> _pulls =
      ValueNotifier<Map<String, TugPull>>(const <String, TugPull>{});

  late final List<Widget> _contents = <Widget>[
    for (final _Pill pill in _pills) _pillContent(pill),
  ];

  String _lastAction = 'nothing yet';

  @override
  void dispose() {
    _pulls.dispose();
    super.dispose();
  }

  Rect _rectFor(_Pill pill) {
    final TugPull? p = _pulls.value[pill.id];
    if (p == null) {
      return pill.home;
    }
    // The tug moves and stretches the REAL piece rect: the skin traces
    // the displaced mass, so pulling one pill toward the other grows a
    // genuine neck - geometry, not a paint effect.
    return Rect.fromCenter(
      center: pill.home.center + p.offset,
      width: pill.home.width * p.scaleX,
      height: pill.home.height * p.scaleY,
    );
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
      cap: _tugCap,
      onPull: (TugPull p) =>
          _pulls.value = <String, TugPull>{..._pulls.value, pill.id: p},
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
    return Column(
      mainAxisAlignment: .center,
      children: <Widget>[
        // One skin, two morphable pieces: the tug (data mode) moves
        // the real piece rects, so dragging a pill toward its neighbor
        // necks the two into one body - and each pill still morphs
        // into its own menu from wherever it stands.
        SizedBox(
          width: 320,
          height: 150,
          child: ListenableBuilder(
            listenable: _pulls,
            builder: (BuildContext context, Widget? child) => MorphSkin(
              blend: _blend,
              color: _glass,
              elevation: 3,
              pieces: <MorphPiece>[
                for (int i = 0; i < _pills.length; i++)
                  MorphPiece.morphable(
                    id: _pills[i].id,
                    rect: _rectFor(_pills[i]),
                    radius: _rectFor(_pills[i]).height / 2,
                    child: _contents[i],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'last action: $_lastAction',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'the pills ride a leash: tug one into the other, then tap',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }
}
