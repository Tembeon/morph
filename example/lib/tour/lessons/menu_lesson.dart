import 'package:flutter/material.dart';

import 'package:morph/morph.dart';

import 'package:morph_example/ui/morph_surface.dart';
import 'package:morph_example/ui/spring_button.dart';

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
  static const MorphSurfaceSpec _pill = MorphSurfaceSpec(
    shape: StadiumBorder(),
    color: Color(0xFF2A2440),
    elevation: 3,
  );
  static const MorphSurfaceSpec _menu = MorphSurfaceSpec(
    shape: RoundedRectangleBorder(borderRadius: .all(.circular(20))),
    color: Color(0xFF262038),
    elevation: 16,
  );

  String _lastAction = 'nothing yet';

  void _openMenu(BuildContext buttonContext) {
    // The popover anchors to the button: capture its rect NOW and close
    // the target spec over it. Placement is app policy - the engine
    // only needs a rect per frame.
    final RenderBox box = buttonContext.findRenderObject()! as RenderBox;
    final Rect anchor = box.localToGlobal(.zero) & box.size;
    showMorph(
      buttonContext,
      motion: widget.motion,
      maxScrimOpacity: 0.2,
      semanticLabel: 'Options menu',
      target: MorphTargetSpec.popover(
        anchor: anchor,
        size: const Size(250, 264),
        surface: _menu,
      ),
      builder: (BuildContext context, MorphFlight flight) =>
          _MenuContent(flight: flight, onAction: _onAction),
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
        MorphTag(
          id: 'menu-pill',
          spec: _pill,
          child: MorphSurface(
            onTap: _openMenu,
            child: const Padding(
              padding: .symmetric(horizontal: 22, vertical: 13),
              child: Row(
                mainAxisSize: .min,
                children: <Widget>[
                  Icon(Icons.tune_rounded, size: 17),
                  SizedBox(width: 8),
                  Text(
                    'Options',
                    style: TextStyle(fontSize: 13.5, fontWeight: .w600),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'last action: $_lastAction',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }
}

class _MenuContent extends StatelessWidget {
  const _MenuContent({required this.flight, required this.onAction});

  final MorphFlight flight;
  final ValueChanged<String> onAction;

  static const List<(IconData, String)> _items = <(IconData, String)>[
    (Icons.push_pin_outlined, 'Pin'),
    (Icons.drive_file_rename_outline_rounded, 'Rename'),
    (Icons.copy_rounded, 'Duplicate'),
    (Icons.ios_share_rounded, 'Share'),
    (Icons.delete_outline_rounded, 'Delete'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .symmetric(vertical: 10),
      child: Column(
        mainAxisSize: .min,
        children: <Widget>[
          for (int i = 0; i < _items.length; i++)
            // Each row unfolds on its own sub-range of the ONE spring:
            // the cascade is the menu's opening, not a separate clock.
            MorphReveal(
              from: 0.3 + i * 0.1,
              to: 0.7 + i * 0.06,
              child: SpringButton(
                onPressed: () {
                  onAction(_items[i].$2.toLowerCase());
                  flight.close();
                },
                child: Padding(
                  padding: const .symmetric(horizontal: 20, vertical: 11),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        _items[i].$1,
                        size: 18,
                        color: i == _items.length - 1
                            ? const Color(0xFFFF7A83)
                            : Colors.white.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        _items[i].$2,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: i == _items.length - 1
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
