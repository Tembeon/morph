import 'package:flutter/material.dart';

import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';
import 'package:morph_example/ui/pill_physics.dart';
import 'package:motor/motor.dart';

/// The liquid-selection scene: a feed app whose tab dock is one fused
/// mass, with the selection blob gliding between slots on the
/// reference pill spring - the neck stretches toward the new tab,
/// rips, and the blob deforms by its own ACCELERATION ([MorphSquash]):
/// the launch stretches it along the travel, the arrival squashes it,
/// and the same force model keeps working through every mid-flight
/// retarget (velocity carry-over included).
///
/// The blob rides its piece geometry channel: the scene's ticker
/// samples the spring, feeds the squash tracker and writes the channel
/// - no widget rebuilds per frame. setState fires only on the actual
/// selection change (icon tints and the feed swap).
class GooDockExample extends StatefulWidget {
  /// Creates the chapter scene.
  const GooDockExample({super.key});

  @override
  State<GooDockExample> createState() => _GooDockExampleState();
}

class _GooDockExampleState extends State<GooDockExample>
    with TickerProviderStateMixin {
  static const List<(IconData, String)> _tabs = <(IconData, String)>[
    (Icons.home_rounded, 'For you'),
    (Icons.search_rounded, 'Search'),
    (Icons.add_circle_outline_rounded, 'Create'),
    (Icons.favorite_rounded, 'Saved'),
    (Icons.person_rounded, 'Profile'),
  ];

  static const double _slot = 64;
  static const double _dockHeight = 58;
  static const double _dockWidth = _slot * 5;

  late final SingleMotionController _x = SingleMotionController(
    motion: pillGlide,
    vsync: this,
    initialValue: _slotCenter(0),
  );
  final MorphPieceChannel _blob = MorphPieceChannel();

  /// The per-frame path: the driver samples the spring and hands back
  /// the deformation, which goes straight into the channel. It outlives
  /// the spring on purpose - the deformation drains through its own
  /// window AFTER the landing.
  late final SquashDriver _driver = SquashDriver(
    vsync: this,
    position: () => Offset(_x.value, 0),
    isBusy: () => _x.isAnimating,
    onFrame: (MorphSquash squash) => _blob.update(
      offset: Offset(_x.value - _slotCenter(0), 0),
      scaleX: squash.scaleX,
      scaleY: squash.scaleY,
    ),
  );
  int _selected = 0;

  static double _slotCenter(int index) => _slot * index + _slot / 2;

  void _select(int index) {
    if (index != _selected) {
      setState(() => _selected = index);
    }
    // Retarget from the CURRENT position and velocity - the same
    // interruption contract as the flights (SingleMotionController
    // carries the velocity over on its own).
    _x.animateTo(_slotCenter(index));
    _driver.start();
  }

  @override
  void dispose() {
    _driver.dispose();
    _x.dispose();
    _blob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SceneScaffold(
      controls: const Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          PanelHint(
            'Tap tabs - fast. The blob is MASS shared with the dock: the '
            'neck stretches and rips, the launch stretches the blob '
            'along its travel and the arrival squashes it - deformation '
            'from FORCE, not from motion - and every mid-flight tap '
            'retargets from the current position and velocity.',
          ),
          PanelHint(
            'One MorphSkin, one channel write per frame: the dock body, '
            'the blob and the necks are a single traced contour - one '
            'mass, one shadow.',
          ),
        ],
      ),
      phone: PhoneFrame(
        app: (BuildContext context) => Stack(
          children: <Widget>[
            _Feed(tab: _tabs[_selected].$2, seed: _selected),
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Center(
                child: SizedBox(
                  width: _dockWidth,
                  height: _dockHeight + 36,
                  child: _dock(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dock() {
    return MorphSkin(
      blend: 24,
      color: const Color(0xFF241F35),
      elevation: 6,
      pieces: <MorphPiece>[
        const MorphPiece(
          id: 'dock',
          rect: .fromLTWH(0, 24, _dockWidth, _dockHeight),
          radius: _dockHeight / 2,
        ),
        // The selection blob: pure mass on a spring, delivered through
        // the geometry channel. Slightly proud of the dock so the bulge
        // reads on the silhouette.
        MorphPiece(
          id: 'blob',
          rect: .fromCenter(
            center: Offset(_slotCenter(0), 24 + _dockHeight / 2 - 12),
            width: 46,
            height: 46,
          ),
          radius: 23,
          channel: _blob,
        ),
        for (int i = 0; i < _tabs.length; i++)
          MorphPiece(
            id: 'tab-$i',
            rect: .fromLTWH(_slot * i, 24, _slot, _dockHeight),
            solid: false,
            child: IconButton(
              onPressed: () => _select(i),
              icon: Icon(
                _tabs[i].$1,
                size: 23,
                color: i == _selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ),
      ],
    );
  }
}

/// The set dressing: a feed skeleton that swaps with the tab, so the
/// dock reads as navigation, not as an isolated toy.
class _Feed extends StatelessWidget {
  const _Feed({required this.tab, required this.seed});

  final String tab;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final Color tint = Color.lerp(
      const Color(0xFF7C5CFF),
      const Color(0xFF4CC5B8),
      (seed % 5) / 4,
    )!;
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
            padding: const .fromLTRB(14, 0, 14, 110),
            itemCount: 6,
            itemBuilder: (BuildContext context, int index) => Padding(
              padding: const .only(bottom: 10),
              child: Container(
                height: 92,
                padding: const .all(12),
                decoration: BoxDecoration(
                  borderRadius: .circular(16),
                  color: Colors.white.withValues(alpha: 0.035),
                ),
                child: Row(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        borderRadius: .circular(12),
                        color: tint.withValues(
                          alpha: 0.14 + 0.1 * ((index + seed) % 3),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: .start,
                        children: <Widget>[
                          Container(
                            height: 11,
                            width: 130.0 + ((index * 37 + seed * 19) % 80),
                            decoration: BoxDecoration(
                              borderRadius: .circular(6),
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 9,
                            width: 90.0 + ((index * 53 + seed * 31) % 110),
                            decoration: BoxDecoration(
                              borderRadius: .circular(5),
                              color: Colors.white.withValues(alpha: 0.07),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
