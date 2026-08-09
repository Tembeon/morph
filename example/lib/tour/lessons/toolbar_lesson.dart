import 'package:flutter/material.dart';

import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';
import 'package:motor/motor.dart';

/// The iOS 26 toolbar behavior: while the content scrolls, the three
/// floating actions MERGE into one quiet pill - liquid fusion driven by
/// one retargetable spring. Stop (or scroll back up) and the pill
/// splits back into buttons, necks stretching and ripping on the way.
/// Every geometric property is a pure function of the single merge
/// value; the scroll only retargets it.
///
/// The merge value reaches the masses through the piece geometry
/// channels (one per action): a spring tick writes three deltas and
/// the skin re-traces - the list, the bar and the piece widgets never
/// rebuild. Only the icons, whose opacity and glyph derive from the
/// same value, listen to the spring themselves.
class ToolbarLesson extends StatefulWidget {
  /// Creates the chapter demo.
  const ToolbarLesson({super.key, required this.motion});

  /// Motion profile of the demo springs and flights.
  final MorphMotion motion;

  @override
  State<ToolbarLesson> createState() => _ToolbarLessonState();
}

class _ToolbarLessonState extends State<ToolbarLesson>
    with SingleTickerProviderStateMixin {
  static const List<(IconData, String)> _actions = <(IconData, String)>[
    (Icons.ios_share_rounded, 'Share'),
    (Icons.edit_rounded, 'Edit'),
    (Icons.archive_outlined, 'Archive'),
  ];

  // The merge deserves character: a bouncier spring than the flight
  // default, so both the merge and the split land with a visible pop.
  static const Motion _mergeMotion = CupertinoMotion(
    duration: Duration(milliseconds: 600),
    bounce: 0.42,
  );

  late final SingleMotionController _merge = SingleMotionController(
    motion: _mergeMotion,
    vsync: this,
    initialValue: 0,
  );
  final List<MorphPieceChannel> _channels = <MorphPieceChannel>[
    MorphPieceChannel(),
    MorphPieceChannel(),
    MorphPieceChannel(),
  ];
  double _target = 0;

  @override
  void initState() {
    super.initState();
    _merge.addListener(_syncChannels);
  }

  /// Geometry eats the RAW spring value: clamping it here would strip
  /// the overshoot - and the overshoot IS the bounce (the buttons
  /// squeeze past the merge point and pop back on the split). Mass
  /// squeezes slightly toward the merged state so arrivals read in the
  /// silhouette, not just in the positions.
  void _syncChannels() {
    final double m = _merge.value;
    final double scale = 1 - 0.12 * m;
    for (int i = 0; i < _channels.length; i++) {
      _channels[i].update(
        offset: Offset((i - 1) * -58.0 * m, 0),
        scaleX: scale,
        scaleY: scale,
      );
    }
  }

  @override
  void dispose() {
    _merge.dispose();
    for (final MorphPieceChannel channel in _channels) {
      channel.dispose();
    }
    super.dispose();
  }

  void _retarget(double target) {
    if (target == _target) {
      return;
    }
    _target = target;
    _merge.animateTo(target);
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final double delta = notification.scrollDelta ?? 0;
      if (delta > 1) {
        _retarget(1);
      } else if (delta < -1) {
        _retarget(0);
      }
    } else if (notification is ScrollEndNotification) {
      _retarget(0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SceneScaffold(
      controls: const Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          PanelHint(
            'Scroll the list down - the three actions fuse into one '
            'quiet pill; stop, or scroll back up, and it splits into '
            'buttons again, necks stretching and ripping on the way.',
          ),
          PanelHint(
            'One retargetable merge spring drives everything; the '
            'scroll only moves its target. The raw overshooting value '
            'feeds the geometry - the bounce IS the overshoot.',
          ),
        ],
      ),
      phone: PhoneFrame(app: (BuildContext context) => _readerApp()),
    );
  }

  Widget _readerApp() {
    const double buttonSize = 52.0;
    const double barWidth = 76.0 * 3 + 40;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: <Widget>[
        Positioned.fill(
          child: Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              const Padding(
                padding: .fromLTRB(20, 12, 20, 10),
                child: Text(
                  'Reading list',
                  style: TextStyle(fontSize: 24, fontWeight: .w800),
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: ListView.builder(
                    padding: const .fromLTRB(14, 0, 14, 96),
                    itemCount: 24,
                    itemBuilder: (BuildContext context, int index) => Padding(
                      padding: const .only(bottom: 10),
                      child: Container(
                        height: 62,
                        decoration: BoxDecoration(
                          borderRadius: .circular(16),
                          color: Color.lerp(
                            const Color(0xFF201B31),
                            const Color(0xFF2A2340),
                            (index % 5) / 4,
                          ),
                        ),
                        alignment: Alignment.centerLeft,
                        padding: const .symmetric(horizontal: 16),
                        child: Text(
                          'Item ${index + 1} - scroll me',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const .only(bottom: 12),
          child: SizedBox(
            width: barWidth,
            height: buttonSize + 24,
            child: MorphSkin(
              blend: 24,
              color: const Color(0xFF2A2440),
              elevation: 6,
              pieces: <MorphPiece>[
                for (int i = 0; i < _actions.length; i++)
                  MorphPiece(
                    id: i,
                    rect: .fromCenter(
                      center: Offset(
                        barWidth / 2 + (i - 1) * 76.0,
                        12 + buttonSize / 2,
                      ),
                      width: buttonSize,
                      height: buttonSize,
                    ),
                    radius: buttonSize / 2,
                    channel: _channels[i],
                    child: ListenableBuilder(
                      listenable: _merge,
                      builder: (BuildContext context, Widget? child) {
                        final double m = _merge.value;
                        final double mVisual = m.clamp(0.0, 1.0);
                        return Opacity(
                          // Side icons dissolve INTO the merged pill;
                          // the center one stays as its face.
                          opacity: i == 1 ? 1 : (1 - mVisual).clamp(0.0, 1.0),
                          child: Icon(
                            i == 1 && m > 0.6
                                ? Icons.more_horiz_rounded
                                : _actions[i].$1,
                            size: 20,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
