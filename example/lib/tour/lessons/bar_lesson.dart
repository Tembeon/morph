import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';
import 'package:morph_example/tour/lessons/dialog_contents.dart';

/// The floating-bar case: a capsule carrying an ink pill selector and a
/// send companion one neck away, fused by a single [MorphSkin] - the
/// whole bar is ONE mass, not a row of cards.
///
/// The physics is [MorphPillHost] - the promoted liquid-glass pill
/// with the native grab - consumed the intended way: the scene owns
/// the track's geometry, the ink rendering and the selection
/// semantics; the host owns every spring. The chrome sympathy goes
/// out through the capsule's piece channel, so the neck to the send
/// button breathes along; the send companion keeps the button model
/// ([Tug]) and is a real morph source whose compose dialog closes on
/// [MorphMotion.glass] - the button family's character at flight
/// mass.
class BarLesson extends StatefulWidget {
  /// Creates the chapter demo.
  const BarLesson({super.key});

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
      // The material closes the way it presses: the glass profile is
      // the button family's tempo calibrated for flight mass, so the
      // dialog lands in the send button as kin, not as slapstick.
      motion: MorphMotion.glass,
      semanticLabel: 'New message',
      builder: (BuildContext context, MorphFlight flight) =>
          ComposeDialogContent(flight: flight),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SceneScaffold(
      controls: const Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          PanelHint(
            'The touch itself is the answer, no hold timer at all: on '
            'the pill\'s own tab it lifts IN PLACE; hold ANOTHER tab '
            'and the pill travels to it under the finger, committing '
            'on release. A quick release is a tap (the light flips '
            'with the screens), a carry moves the pill by the '
            'finger\'s own displacement and snaps on release.',
          ),
          PanelHint(
            'The bar itself has no leash: it answers in SYMPATHY - the '
            'drag shifts the whole mass by at most 4px on an ease-out, '
            'and while the pill is up the bar breathes a few pixels of '
            'width. One skin: the neck to the send button breathes '
            'along, and the send button is a real morph source whose '
            'dialog closes on the glass profile - the button family\'s '
            'tempo at flight mass.',
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
                          child: _InkTrack(
                            tabs: _tabs,
                            selected: _selected,
                            surface: _glass,
                            accent: _accent,
                            barChannel: _barPull,
                            onSelect: (int i) => setState(() => _selected = i),
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

/// The ink track: [MorphPillHost] consumed the intended way. The scene
/// maps pixels to slots through the host's two callbacks, feeds the
/// raw pointer straight in (a Listener - no recognizers, no timers),
/// paints the ink pill wherever the host says, and forwards the
/// chrome sympathy into the capsule's piece channel.
class _InkTrack extends StatefulWidget {
  const _InkTrack({
    required this.tabs,
    required this.selected,
    required this.surface,
    required this.accent,
    required this.barChannel,
    required this.onSelect,
  });

  final List<(IconData, String)> tabs;
  final int selected;
  final Color surface;
  final Color accent;
  final MorphPieceChannel barChannel;
  final ValueChanged<int> onSelect;

  @override
  State<_InkTrack> createState() => _InkTrackState();
}

class _InkTrackState extends State<_InkTrack>
    with SingleTickerProviderStateMixin {
  static const double _inset = 4;

  /// The reference lift: +12px of height at full lift, same w:h ratio.
  static const double _growHeight = 12;

  late final MorphPillHost _host = MorphPillHost(
    vsync: this,
    hit: _hitCenter,
    snap: _snapCenter,
    onTarget: _onTarget,
  );

  /// What the cells light up: the LIVE choice - it flips the moment a
  /// tap commits (with the screens), and follows the nearest slot
  /// while the pill is carried.
  int _active = 0;
  int? _pointer;

  double _slot = 0;
  double _width = 0;
  double _height = 0;

  @override
  void initState() {
    super.initState();
    _active = widget.selected;
    _host.addListener(_onFrame);
  }

  @override
  void dispose() {
    _host.removeListener(_onFrame);
    _host.dispose();
    super.dispose();
  }

  double _slotCenter(int index) => _slot * index + _slot / 2;

  int _slotOf(double centerX) =>
      ((centerX - _slot / 2) / _slot).round().clamp(0, widget.tabs.length - 1);

  double _hitCenter(double fingerX) =>
      _slotCenter((fingerX / _slot).floor().clamp(0, widget.tabs.length - 1));

  double _snapCenter(double pillCenterX) => _slotCenter(_slotOf(pillCenterX));

  void _onTarget(double centerX, {required bool byCarry}) {
    final int index = _slotOf(centerX);
    if (_active != index) {
      setState(() => _active = index);
    }
    if (index != widget.selected) {
      widget.onSelect(index);
    }
  }

  /// One frame from the host: forward the chrome sympathy into the
  /// capsule's channel, and hand the light over while the pill is
  /// carried. The pill layer repaints through its own listenable.
  void _onFrame() {
    if (_width == 0) {
      return;
    }
    // The breath is a WIDTH: writing it into scaleY too would grow the
    // bar's height, break its stadium against a fixed radius and eat
    // the gap the neck lives in.
    widget.barChannel.update(
      offset: Offset(_host.chromeShift(_width), 0),
      scaleX: _host.chromeBreath(_width),
    );
    if (_host.carrying) {
      final int under = _slotOf(_host.centerX);
      if (under != _active) {
        setState(() => _active = under);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double previousSlot = _slot;
        _slot = constraints.maxWidth / widget.tabs.length;
        _width = constraints.maxWidth;
        _height = constraints.maxHeight;
        // The host holds an ABSOLUTE center; the first layout places
        // it, and a width change re-anchors a resting pill to the
        // current selection's new center.
        if (previousSlot != _slot && !_host.held) {
          _host.jumpTo(_slotCenter(widget.selected));
        }
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          // A raw Listener, no recognizers and no timers: the pill
          // starts lifting on the DOWN itself - the instant answer the
          // native bar gives - and what the gesture MEANT (a tap, a
          // hold, a carry) is read from what the pointer then does.
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (PointerDownEvent e) {
              if (_pointer == null && e.buttons == kPrimaryButton) {
                _pointer = e.pointer;
                _host.down(e.localPosition.dx);
              }
            },
            onPointerMove: (PointerMoveEvent e) {
              if (e.pointer == _pointer) {
                _host.move(e.localPosition.dx);
              }
            },
            onPointerUp: (PointerUpEvent e) {
              if (e.pointer == _pointer) {
                _pointer = null;
                _host.up(e.localPosition.dx);
              }
            },
            onPointerCancel: (PointerCancelEvent e) {
              if (e.pointer == _pointer) {
                _pointer = null;
                _host.cancel();
              }
            },
            child: Stack(
              clipBehavior: .none,
              children: <Widget>[
                // The pill is PAINTED, not laid out: a Positioned whose
                // values change per tick marks the Stack for layout
                // every frame, and the house rule is that spring ticks
                // repaint only. The layout box is the whole track; the
                // frame rides a transform inside it.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ListenableBuilder(
                      listenable: _host,
                      builder: (BuildContext context, Widget? child) {
                        final Size rest = Size(
                          _slot - _inset * 2,
                          _height - _inset * 2,
                        );
                        final double liftedH = _height + _growHeight;
                        final Size lifted = Size(
                          liftedH * (rest.width / rest.height),
                          liftedH,
                        );
                        final Size live = _host.resolveSize(
                          rest: rest,
                          lifted: lifted,
                        );
                        final Matrix4 place = Matrix4.translationValues(
                          _host.centerX - live.width / 2,
                          _height / 2 - live.height / 2,
                          0,
                        );
                        place.scaleByDouble(
                          live.width / math.max(rest.width, 1),
                          live.height / math.max(rest.height, 1),
                          1,
                          1,
                        );
                        return Transform(transform: place, child: child);
                      },
                      child: Align(
                        alignment: .topLeft,
                        child: SizedBox(
                          width: math.max(_slot - _inset * 2, 1),
                          height: math.max(_height - _inset * 2, 1),
                          child: DecoratedBox(
                            // Ink, not glass: an opaque wash of accent
                            // soaked into the surface, no outline.
                            decoration: ShapeDecoration(
                              color: Color.alphaBlend(
                                widget.accent.withValues(alpha: 0.16),
                                widget.surface,
                              ),
                              shape: const StadiumBorder(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    for (int i = 0; i < widget.tabs.length; i++)
                      SizedBox(
                        width: _slot,
                        height: _height,
                        // The gestures live on the track, but a tab is
                        // a control: screen readers need a name, the
                        // selected state and something to activate.
                        child: Semantics(
                          button: true,
                          selected: i == _active,
                          label: widget.tabs[i].$2,
                          onTap: () => widget.onSelect(i),
                          child: ExcludeSemantics(
                            child: _Cell(
                              icon: widget.tabs[i].$1,
                              label: widget.tabs[i].$2,
                              active: i == _active,
                            ),
                          ),
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

/// One slot's content: icon over label, emphasis following the LIVE
/// choice (it flips with the selection, and under a carried pill).
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
