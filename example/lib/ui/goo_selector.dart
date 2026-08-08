import 'package:flutter/material.dart';

import 'package:morph/widgets.dart';
import 'package:motor/motor.dart';

/// The lab's segmented control, rebuilt on the liquid engine: one skin
/// fuses a track with a selection blob riding a spring between
/// slots - slightly proud of the track so the bulge reads on the
/// silhouette, necking through the goo on the way. Tapping mid-flight
/// retargets with velocity carry-over (motor's [SingleMotionController]
/// does that for free); a null selection deflates the blob to nothing
/// (mass, not opacity). Label emphasis is a pure function of the blob
/// position - no second clock anywhere.
class GooSelector extends StatefulWidget {
  /// Creates a selector over [labels].
  const GooSelector({
    super.key,
    required this.labels,
    required this.index,
    required this.onSelect,
    this.height = 34,
  });

  /// Slot labels, one per option.
  final List<String> labels;

  /// null parks no selection: the blob deflates in place.
  final int? index;

  /// Called with the tapped slot index.
  final ValueChanged<int> onSelect;

  /// Track height; the blob rides slightly proud of it.
  final double height;

  @override
  State<GooSelector> createState() => _GooSelectorState();
}

class _GooSelectorState extends State<GooSelector>
    with TickerProviderStateMixin {
  SingleMotionController? _x;
  late final SingleMotionController _scale = SingleMotionController(
    motion: MorphMotion.normal.closeMotion,
    vsync: this,
    initialValue: widget.index == null ? 0 : 1,
  );
  double _width = 0;

  @override
  void dispose() {
    _x?.dispose();
    _scale.dispose();
    super.dispose();
  }

  double _slotCenter(int index) {
    final double slot = _width / widget.labels.length;
    return slot * index + slot / 2;
  }

  @override
  void didUpdateWidget(GooSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      final int? index = widget.index;
      if (index != null) {
        _x?.animateTo(_slotCenter(index));
      }
      _scale.animateTo(index == null ? 0 : 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double h = widget.height;
    return SizedBox(
      height: h + 12,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          _width = constraints.maxWidth;
          // The position spring needs a laid-out slot to be born in.
          _x ??= SingleMotionController(
            motion: MorphMotion.normal.closeMotion,
            vsync: this,
            initialValue: _slotCenter(widget.index ?? 0),
          );
          final double slot = _width / widget.labels.length;
          return ListenableBuilder(
            listenable: .merge(<Listenable>[_x!, _scale]),
            builder: (BuildContext context, Widget? child) {
              final double x = _x!.value;
              final double blobScale = _scale.value < 0 ? 0 : _scale.value;
              return MorphSkin(
                blend: 14,
                color: const Color(0xFF2A2440),
                elevation: 2,
                pieces: <MorphPiece>[
                  MorphPiece(
                    id: 'track',
                    rect: .fromLTWH(0, 6, _width, h),
                    radius: h / 2,
                  ),
                  // The selection: mass proud of the track, deflating to
                  // zero when nothing is selected.
                  MorphPiece(
                    id: 'blob',
                    rect: .fromCenter(
                      center: Offset(x, 6 + h / 2),
                      width: (slot - 8) * blobScale,
                      height: (h + 10) * blobScale,
                    ),
                    radius: (h + 10) * blobScale / 2,
                  ),
                  for (int i = 0; i < widget.labels.length; i++)
                    MorphPiece(
                      id: 'slot-$i',
                      rect: .fromLTWH(slot * i, 6, slot, h),
                      solid: false,
                      child: SpringButton(
                        onPressed: () => widget.onSelect(i),
                        child: Center(
                          child: Text(
                            widget.labels[i],
                            maxLines: 1,
                            overflow: .fade,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: .w600,
                              // Emphasis follows the BLOB, not the model:
                              // a pure function of the spring position.
                              color: Colors.white.withValues(
                                alpha: _labelAlpha(i, slot, x, blobScale),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  double _labelAlpha(int i, double slot, double x, double blobScale) {
    final double distance = (_slotCenter(i) - x).abs();
    final double proximity = 1 - (distance / slot).clamp(0.0, 1.0);
    return 0.45 + 0.55 * proximity * blobScale.clamp(0.0, 1.0);
  }
}
