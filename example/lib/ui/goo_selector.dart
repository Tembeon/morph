import 'package:flutter/material.dart';

import 'package:morph/widgets.dart';
import 'package:motor/motor.dart';

/// The lab's segmented control, rebuilt on the liquid engine: one skin
/// fuses a track with a selection blob riding a spring between
/// slots - slightly proud of the track so the bulge reads on the
/// silhouette, necking through the goo on the way. Tapping mid-flight
/// retargets with velocity carry-over (motor's [SingleMotionController]
/// does that for free); a null selection deflates the blob to nothing
/// (mass, not opacity - channel scale zero). Label emphasis is a pure
/// function of the blob position - no second clock anywhere.
///
/// The per-frame path is the piece geometry channel: the springs write
/// the blob's offset and scale straight into the render object, and
/// only the label texts (whose emphasis derives from the same springs)
/// rebuild - the skin and its piece list stay untouched.
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
  final MorphPieceChannel _blob = MorphPieceChannel();
  double _width = 0;

  @override
  void initState() {
    super.initState();
    _scale.addListener(_syncBlob);
  }

  @override
  void dispose() {
    _x?.dispose();
    _scale.dispose();
    _blob.dispose();
    super.dispose();
  }

  double _slotCenter(int index) {
    final double slot = _width / widget.labels.length;
    return slot * index + slot / 2;
  }

  /// The springs feed the blob's geometry channel: offset from the
  /// track center, scale deflating to zero. The spring can dip below
  /// zero on the deflate - mass cannot.
  void _syncBlob() {
    if (_x == null || _width == 0) {
      return;
    }
    final double scale = _scale.value < 0 ? 0 : _scale.value;
    _blob.update(
      offset: Offset(_x!.value - _width / 2, 0),
      scaleX: scale,
      scaleY: scale,
    );
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
          final double previousWidth = _width;
          _width = constraints.maxWidth;
          // The position spring needs a laid-out slot to be born in.
          _x ??= SingleMotionController(
            motion: MorphMotion.normal.closeMotion,
            vsync: this,
            initialValue: _slotCenter(widget.index ?? 0),
          )..addListener(_syncBlob);
          // The spring holds an ABSOLUTE position; a width change moves
          // every slot center, so a resting blob must be re-anchored to
          // the current selection's new center (a live animation keeps
          // its own target).
          if (previousWidth != _width &&
              previousWidth != 0 &&
              widget.index != null &&
              !_x!.isAnimating) {
            _x!.value = _slotCenter(widget.index!);
          }
          // Re-aim the channel after layout changes; a no-op tick when
          // nothing moved.
          _syncBlob();
          final double slot = _width / widget.labels.length;
          final Listenable blobFrame = Listenable.merge(<Listenable>[
            _x!,
            _scale,
          ]);
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
              // The selection: mass proud of the track, riding the
              // geometry channel; scale 0 parks it as nothing when no
              // selection is made.
              MorphPiece(
                id: 'blob',
                rect: .fromCenter(
                  center: Offset(_width / 2, 6 + h / 2),
                  width: slot - 8,
                  height: h + 10,
                ),
                radius: (h + 10) / 2,
                channel: _blob,
              ),
              for (int i = 0; i < widget.labels.length; i++)
                MorphPiece(
                  id: 'slot-$i',
                  rect: .fromLTWH(slot * i, 6, slot, h),
                  solid: false,
                  child: SpringButton(
                    onPressed: () => widget.onSelect(i),
                    child: Center(
                      // Emphasis follows the BLOB, not the model: a pure
                      // function of the spring position. The text listens
                      // to the springs itself, so a tick repaints labels
                      // without touching the skin or the piece list.
                      child: ListenableBuilder(
                        listenable: blobFrame,
                        builder: (BuildContext context, Widget? child) => Text(
                          widget.labels[i],
                          maxLines: 1,
                          overflow: .fade,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: .w600,
                            color: Colors.white.withValues(
                              alpha: _labelAlpha(i, slot),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  double _labelAlpha(int i, double slot) {
    final double blobScale = _scale.value.clamp(0.0, 1.0);
    final double distance = (_slotCenter(i) - _x!.value).abs();
    final double proximity = 1 - (distance / slot).clamp(0.0, 1.0);
    return 0.45 + 0.55 * proximity * blobScale;
  }
}
