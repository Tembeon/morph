import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';
import 'package:morph_example/tour/lessons/dialog_contents.dart';
import 'package:motor/motor.dart';

/// The floating-bar case: a capsule carrying an ink pill selector and a
/// send companion one neck away, fused by a single [MorphSkin] - the
/// whole bar is ONE mass, not a row of cards.
///
/// Three mechanics live on the same finger, none stealing from the
/// others:
///
/// - the INK PILL floats freely under a horizontal drag (its width
///   adapts to the target under the finger, the smear grows with the
///   remaining distance) and snaps on release - direct manipulation, so
///   the pill rides its own bouncy springs, not the tug;
/// - the CAPSULE answers the same finger through [Tug] (a raw Listener,
///   out of the gesture arena): a whisper of travel, height pinned by
///   `vertical: 0`, the wide-calm aspect fade doing the rest;
/// - the SEND companion is a morphable piece a neck away: pull it and
///   the skin fuses the two bodies, tap it and the compose dialog grows
///   out of it.
class BarLesson extends StatefulWidget {
  /// Creates the chapter demo.
  const BarLesson({super.key, required this.motion});

  /// Motion profile of the compose flight.
  final MorphMotion motion;

  @override
  State<BarLesson> createState() => _BarLessonState();
}

class _BarLessonState extends State<BarLesson> {
  static const Color _glass = Color(0xFF2A2440);
  static const Color _accent = Color(0xFF7C5CFF);
  static const double _barHeight = 56;
  static const double _gap = 12;

  static const List<(IconData, String)> _tabs = <(IconData, String)>[
    (Icons.library_music_rounded, 'Library'),
    (Icons.mail_rounded, 'Mail'),
    (Icons.person_rounded, 'Profile'),
  ];

  final MorphPieceChannel _barPull = MorphPieceChannel();
  final MorphPieceChannel _sendPull = MorphPieceChannel();
  int _selected = 0;

  double _give = 0.05;
  double _pressGrow = 4;
  double _vertical = 0;

  @override
  void dispose() {
    _barPull.dispose();
    _sendPull.dispose();
    super.dispose();
  }

  void _compose(BuildContext buttonContext) {
    showMorphDialog(
      buttonContext,
      from: 'bar-send',
      width: 306,
      height: 420,
      motion: widget.motion,
      semanticLabel: 'New message',
      builder: (BuildContext context, MorphFlight flight) =>
          ComposeDialogContent(flight: flight),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SceneScaffold(
      controls: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          const PanelHint(
            'One skin, one mass: the capsule and the send button fuse '
            'through the neck the moment a pull brings them close. Drag '
            'the pill along the track - it floats under the finger and '
            'snaps on release - while the capsule itself answers the '
            'same finger with a whisper of tug.',
          ),
          const PanelHint(
            'The bar is wide chrome: past a 2:1 aspect the tug '
            'transmission fades by itself, the press grows by absolute '
            'pixels per axis, and vertical: 0 pins the height - no '
            'special "quiet" variant, just the material.',
          ),
          PanelSection(
            label: 'BAR MATERIAL',
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
                  label: 'press',
                  value: _pressGrow,
                  min: -6,
                  max: 10,
                  format: (double v) => '${v.toStringAsFixed(1)}px',
                  onChanged: (double v) => setState(() => _pressGrow = v),
                ),
                PanelKnob(
                  label: 'vertical',
                  value: _vertical,
                  min: 0,
                  max: 1,
                  format: (double v) => v.toStringAsFixed(2),
                  onChanged: (double v) => setState(() => _vertical = v),
                ),
              ],
            ),
          ),
        ],
      ),
      phone: PhoneFrame(
        app: (BuildContext context) => Stack(
          children: <Widget>[
            _Skeleton(tab: _tabs[_selected].$2, seed: _selected),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double capsuleWidth = math.min(
                    300,
                    constraints.maxWidth - _gap - _barHeight,
                  );
                  final double rowWidth = capsuleWidth + _gap + _barHeight;
                  final double left = (constraints.maxWidth - rowWidth) / 2;
                  return SizedBox(
                    height: _barHeight,
                    child: MorphSkin(
                      blend: 10,
                      cell: 6,
                      color: _glass,
                      elevation: 4,
                      pieces: <MorphPiece>[
                        MorphPiece(
                          id: 'bar-capsule',
                          rect: Rect.fromLTWH(
                            left,
                            0,
                            capsuleWidth,
                            _barHeight,
                          ),
                          radius: _barHeight / 2,
                          channel: _barPull,
                          child: Tug(
                            channel: _barPull,
                            give: _give,
                            pressGrow: _pressGrow,
                            vertical: _vertical,
                            child: ClipPath(
                              clipper: const ShapeBorderClipper(
                                shape: StadiumBorder(),
                              ),
                              child: _InkTrack(
                                tabs: _tabs,
                                selected: _selected,
                                surface: _glass,
                                accent: _accent,
                                onSelect: (int i) =>
                                    setState(() => _selected = i),
                              ),
                            ),
                          ),
                        ),
                        MorphPiece.morphable(
                          id: 'bar-send',
                          rect: Rect.fromLTWH(
                            left + capsuleWidth + _gap,
                            0,
                            _barHeight,
                            _barHeight,
                          ),
                          radius: _barHeight / 2,
                          channel: _sendPull,
                          child: Tug(
                            channel: _sendPull,
                            child: MorphTapTarget(
                              label: 'Compose',
                              onTap: _compose,
                              child: const Center(
                                child: Icon(
                                  Icons.send_rounded,
                                  size: 20,
                                  color: _accent,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ink pill track - the dream-echo selector mechanic on morph's
/// stage: gestures live on the TRACK (tap-down already flies the pill
/// toward the finger, a horizontal drag floats it freely, release
/// snaps), the pill layer rides its own springs through a
/// ValueNotifier so a drag never rebuilds the slot content.
class _InkTrack extends StatefulWidget {
  const _InkTrack({
    required this.tabs,
    required this.selected,
    required this.surface,
    required this.accent,
    required this.onSelect,
  });

  final List<(IconData, String)> tabs;
  final int selected;
  final Color surface;
  final Color accent;
  final ValueChanged<int> onSelect;

  @override
  State<_InkTrack> createState() => _InkTrackState();
}

class _InkTrackState extends State<_InkTrack> {
  static const double _inset = 4;

  /// The finger's continuous x during a drag; flows straight into the
  /// pill layer without rebuilding the slots.
  final ValueNotifier<double?> _dragX = ValueNotifier<double?>(null);
  int? _hover;
  bool _pressed = false;

  @override
  void dispose() {
    _dragX.dispose();
    super.dispose();
  }

  int _hitSlot(double dx, double slot) =>
      (dx / slot).floor().clamp(0, widget.tabs.length - 1);

  void _dragTo(double dx, double slot) {
    final int hovered = _hitSlot(dx, slot);
    _dragX.value = dx;
    if (_hover != hovered) {
      setState(() => _hover = hovered);
    }
    if (!_pressed) {
      setState(() => _pressed = true);
    }
  }

  void _reset() {
    _dragX.value = null;
    setState(() {
      _hover = null;
      _pressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final int active = _dragX.value != null
        ? (_hover ?? widget.selected)
        : widget.selected;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double slot = constraints.maxWidth / widget.tabs.length;
        final double height = constraints.maxHeight;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails d) => _dragTo(d.localPosition.dx, slot),
            onTapCancel: _reset,
            onTapUp: (TapUpDetails d) {
              final int hit = _hitSlot(d.localPosition.dx, slot);
              _reset();
              widget.onSelect(hit);
            },
            onHorizontalDragStart: (DragStartDetails d) =>
                _dragTo(d.localPosition.dx, slot),
            onHorizontalDragUpdate: (DragUpdateDetails d) =>
                _dragTo(d.localPosition.dx, slot),
            onHorizontalDragEnd: (DragEndDetails d) {
              final int? hovered = _hover;
              _reset();
              if (hovered != null && hovered != widget.selected) {
                widget.onSelect(hovered);
              }
            },
            onHorizontalDragCancel: _reset,
            child: Stack(
              children: <Widget>[
                ValueListenableBuilder<double?>(
                  valueListenable: _dragX,
                  builder: (BuildContext context, double? dragX, Widget? _) {
                    final double width = slot - _inset * 2;
                    final double start = dragX != null
                        // Free float: the pill centers on the finger,
                        // clamped to the track; targets snap only on
                        // release.
                        ? (dragX - slot / 2).clamp(
                            0.0,
                            constraints.maxWidth - slot,
                          )
                        : slot * widget.selected;
                    return _InkPill(
                      targetStart: start + _inset,
                      width: width,
                      height: height,
                      inset: _inset,
                      pressed: _pressed,
                      color: Color.alphaBlend(
                        widget.accent.withValues(alpha: 0.16),
                        widget.surface,
                      ),
                    );
                  },
                ),
                Row(
                  children: <Widget>[
                    for (int i = 0; i < widget.tabs.length; i++)
                      SizedBox(
                        width: slot,
                        height: height,
                        child: _Cell(
                          icon: widget.tabs[i].$1,
                          label: widget.tabs[i].$2,
                          active: i == active,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The pill layer: position on a bouncy spring, press on a smooth one,
/// and the SMEAR proportional to the remaining distance - the pill
/// stretches in flight and relaxes as it arrives. Ink, not glass: an
/// opaque wash of accent soaked into the surface, no outline.
class _InkPill extends StatelessWidget {
  const _InkPill({
    required this.targetStart,
    required this.width,
    required this.height,
    required this.inset,
    required this.pressed,
    required this.color,
  });

  final double targetStart;
  final double width;
  final double height;
  final double inset;
  final bool pressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      value: targetStart,
      // One spring for every situation (tap flight, chase, press), so
      // the pill always moves with one character.
      motion: const CupertinoMotion.bouncy(),
      builder: (BuildContext context, double animatedStart, Widget? child) =>
          SingleMotionBuilder(
            value: pressed ? 1 : 0,
            motion: const CupertinoMotion.smooth(
              duration: Duration(milliseconds: 200),
            ),
            builder: (BuildContext context, double press, Widget? child) {
              final double distance = (animatedStart - targetStart).abs();
              final double stretch =
                  1 + math.min(0.45, distance / math.max(width, 1) * 0.35);
              final double grow = 1 + 0.04 * press.clamp(0.0, 1.0);
              final double pillWidth = width * stretch * grow;
              final double pillHeight = (height - inset * 2) * grow;
              return Positioned(
                left: animatedStart + width / 2 - pillWidth / 2,
                top: height / 2 - pillHeight / 2,
                width: pillWidth,
                height: pillHeight,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: color,
                    shape: const StadiumBorder(),
                  ),
                ),
              );
            },
          ),
    );
  }
}

/// One slot's content: icon over label, emphasis following the active
/// target (the one under the finger during a drag).
class _Cell extends StatelessWidget {
  const _Cell({required this.icon, required this.label, required this.active});

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color color = Colors.white.withValues(alpha: active ? 1 : 0.45);
    return Column(
      mainAxisAlignment: .center,
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: .w600, color: color),
        ),
      ],
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
