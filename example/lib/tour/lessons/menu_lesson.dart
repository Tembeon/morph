import 'package:flutter/material.dart';

import 'package:morph/morph.dart';

import 'package:morph_example/ui/spring_button.dart';
import 'package:morph_example/ui/tug.dart';

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
  // The blend is the reach of the fusion - a distance in px, tuned per
  // scene (goo's 42 suits dock-scale bodies; button-scale UI wants
  // less). Here it demoes the floating-button-near-a-bar case: the
  // pills rest 17 px apart with blend 14 - just far enough to stay
  // provably separate and out of each other's launch fellowship - and
  // these pills ride a longer leash (cap 0.28) so a full tug can push
  // one into the other: contact, not just a neck.
  static const double _blend = 14;
  static const double _tugCap = 0.28;
  static const Rect _optionsHome = Rect.fromLTWH(29, 53, 132, 44);
  static const Rect _shareHome = Rect.fromLTWH(178, 53, 112, 44);
  static const MorphSurfaceSpec _menu = MorphSurfaceSpec(
    shape: RoundedRectangleBorder(borderRadius: .all(.circular(20))),
    color: Color(0xFF262038),
    elevation: 16,
  );

  static const List<(IconData, String)> _optionItems = <(IconData, String)>[
    (Icons.push_pin_outlined, 'Pin'),
    (Icons.drive_file_rename_outline_rounded, 'Rename'),
    (Icons.copy_rounded, 'Duplicate'),
    (Icons.ios_share_rounded, 'Share'),
    (Icons.delete_outline_rounded, 'Delete'),
  ];
  static const List<(IconData, String)> _shareItems = <(IconData, String)>[
    (Icons.wifi_tethering_rounded, 'AirDrop'),
    (Icons.link_rounded, 'Copy link'),
    (Icons.image_outlined, 'Save image'),
  ];

  String _lastAction = 'nothing yet';
  final Map<String, TugPull> _pulls = <String, TugPull>{};

  Rect _rectFor(String id, Rect home) {
    final TugPull? p = _pulls[id];
    if (p == null) {
      return home;
    }
    // The tug moves and stretches the REAL piece rect: the skin traces
    // the displaced mass, so pulling one pill toward the other grows a
    // genuine neck - geometry, not a paint effect.
    return Rect.fromCenter(
      center: home.center + p.offset,
      width: home.width * p.scaleX,
      height: home.height * p.scaleY,
    );
  }

  void _openMenu(
    BuildContext buttonContext, {
    required String label,
    required List<(IconData, String)> items,
    required bool dangerLast,
  }) {
    // The popover anchors to the button: capture its rect NOW and close
    // the target spec over it. A tugged pill anchors its menu wherever
    // it currently stands - the tag rect already carries the tug.
    final RenderBox box = buttonContext.findRenderObject()! as RenderBox;
    final Rect anchor = box.localToGlobal(.zero) & box.size;
    showMorph(
      buttonContext,
      motion: widget.motion,
      maxScrimOpacity: 0.2,
      semanticLabel: label,
      target: MorphTargetSpec.popover(
        anchor: anchor,
        size: Size(250, 48.0 * items.length + 24),
        surface: _menu,
      ),
      builder: (BuildContext context, MorphFlight flight) => _MenuContent(
        flight: flight,
        onAction: _onAction,
        items: items,
        dangerLast: dangerLast,
      ),
    );
  }

  void _onAction(String action) {
    if (mounted) {
      setState(() => _lastAction = action);
    }
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
          child: MorphSkin(
            blend: _blend,
            color: _glass,
            elevation: 3,
            pieces: <MorphPiece>[
              _pillPiece(
                id: 'menu-pill',
                home: _optionsHome,
                icon: Icons.tune_rounded,
                label: 'Options',
                items: _optionItems,
                dangerLast: true,
              ),
              _pillPiece(
                id: 'share-pill',
                home: _shareHome,
                icon: Icons.ios_share_rounded,
                label: 'Share',
                items: _shareItems,
                dangerLast: false,
              ),
            ],
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

  MorphPiece _pillPiece({
    required String id,
    required Rect home,
    required IconData icon,
    required String label,
    required List<(IconData, String)> items,
    required bool dangerLast,
  }) {
    final Rect rect = _rectFor(id, home);
    return MorphPiece.morphable(
      id: id,
      rect: rect,
      radius: rect.height / 2,
      child: Tug(
        motion: widget.motion,
        cap: _tugCap,
        onPull: (TugPull p) => setState(() => _pulls[id] = p),
        // The skin IS the surface ("one mass - one shadow"): the piece
        // content carries no Material of its own - a second surface
        // would split from the mass the moment the tug deforms it.
        child: Builder(
          builder: (BuildContext tapContext) => Semantics(
            button: true,
            label: label,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: .opaque,
                onTap: () => _openMenu(
                  tapContext,
                  label: '$label menu',
                  items: items,
                  dangerLast: dangerLast,
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: .min,
                    children: <Widget>[
                      Icon(icon, size: 17),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: .w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuContent extends StatelessWidget {
  const _MenuContent({
    required this.flight,
    required this.onAction,
    required this.items,
    required this.dangerLast,
  });

  final MorphFlight flight;
  final ValueChanged<String> onAction;
  final List<(IconData, String)> items;
  final bool dangerLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .symmetric(vertical: 10),
      child: Column(
        mainAxisSize: .min,
        children: <Widget>[
          for (int i = 0; i < items.length; i++)
            // Each row unfolds on its own sub-range of the ONE spring:
            // the cascade is the menu's opening, not a separate clock.
            MorphReveal(
              from: 0.3 + i * 0.1,
              to: 0.7 + i * 0.06,
              child: SpringButton(
                onPressed: () {
                  onAction(items[i].$2.toLowerCase());
                  flight.close();
                },
                child: Padding(
                  padding: const .symmetric(horizontal: 20, vertical: 11),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        items[i].$1,
                        size: 18,
                        color: dangerLast && i == items.length - 1
                            ? const Color(0xFFFF7A83)
                            : Colors.white.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        items[i].$2,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: dangerLast && i == items.length - 1
                              ? const Color(0xFFFF7A83)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
