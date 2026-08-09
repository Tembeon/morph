import 'package:flutter/material.dart';

import 'package:morph/widgets.dart';
import 'package:motor/motor.dart';

/// A gooey dock: five tabs fused by one liquid skin, with a selection
/// blob riding a spring between slots - the neck stretches toward
/// the new tab, rips, and the blob lands with the spring's own
/// character. Tapping mid-flight retargets with velocity carry-over:
/// the whole system-wide interruption philosophy in one tap bar.
///
/// The blob rides its piece geometry channel: the spring tick writes
/// an offset and the skin re-traces - no widget rebuilds per frame.
/// setState fires only on the actual selection change (icon tints).
class GooDockExample extends StatefulWidget {
  /// Creates the chapter demo.
  const GooDockExample({super.key, required this.motion});

  /// Motion profile of the demo springs and flights.
  final MorphMotion motion;

  @override
  State<GooDockExample> createState() => _GooDockExampleState();
}

class _GooDockExampleState extends State<GooDockExample>
    with SingleTickerProviderStateMixin {
  static const List<IconData> _icons = <IconData>[
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.add_circle_outline_rounded,
    Icons.favorite_rounded,
    Icons.person_rounded,
  ];

  static const double _slot = 84;
  static const double _dockHeight = 72;

  late final SingleMotionController _x = SingleMotionController(
    motion: widget.motion.closeMotion,
    vsync: this,
    initialValue: _slotCenter(0),
  );
  final MorphPieceChannel _blob = MorphPieceChannel();
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    // The spring drives the channel, the channel drives the mass: the
    // dock's per-frame path never touches the widget tree.
    _x.addListener(
      () => _blob.update(offset: Offset(_x.value - _slotCenter(0), 0)),
    );
  }

  static double _slotCenter(int index) => _slot * index + _slot / 2;

  void _select(int index) {
    if (index != _selected) {
      setState(() => _selected = index);
    }
    // Retarget from the CURRENT position and velocity - the same
    // interruption contract as the flights (SingleMotionController
    // carries the velocity over on its own).
    _x
      ..motion = widget.motion.closeMotion
      ..animateTo(_slotCenter(index));
  }

  @override
  void dispose() {
    _x.dispose();
    _blob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double width = _slot * 5;
    return Align(
      alignment: const Alignment(0, 0.7),
      child: SizedBox(
        width: width,
        height: _dockHeight + 40,
        child: MorphSkin(
          blend: 26,
          color: const Color(0xFF241F35),
          elevation: 4,
          pieces: <MorphPiece>[
            // The dock body: one long stadium.
            const MorphPiece(
              id: 'dock',
              rect: .fromLTWH(0, 20, width, _dockHeight),
              radius: _dockHeight / 2,
              solid: true,
            ),
            // The selection blob: pure mass on a spring, delivered
            // through the geometry channel. Slightly proud of the dock
            // so the bulge reads on the silhouette.
            MorphPiece(
              id: 'blob',
              rect: .fromCenter(
                center: Offset(_slotCenter(0), 20 + _dockHeight / 2 - 14),
                width: 56,
                height: 56,
              ),
              radius: 28,
              channel: _blob,
            ),
            // Tabs are contentful but massless: the dock provides the
            // mass, the icons just sit on it.
            for (int i = 0; i < _icons.length; i++)
              MorphPiece(
                id: 'tab-$i',
                rect: .fromLTWH(_slot * i, 20, _slot, _dockHeight),
                solid: false,
                child: IconButton(
                  onPressed: () => _select(i),
                  icon: Icon(
                    _icons[i],
                    size: 26,
                    color: i == _selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
