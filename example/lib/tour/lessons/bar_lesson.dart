import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';
import 'package:morph_example/tour/lessons/dialog_contents.dart';

/// The floating-bar case: a capsule carrying an ink pill selector and a
/// send companion one neck away, fused by a single [MorphSkin] - the
/// whole bar is ONE mass, not a row of cards.
///
/// The physics is the reference synthesis, constants verbatim:
///
/// - the PILL is the liquid-glass nav pill (the "stations" feel), on a
///   raw Listener with NO timers: the touch itself starts the lift IN
///   PLACE (even between tabs), a quick release is a tap, a carry
///   moves the pill by the finger's own displacement and snaps on
///   release; a tap's journey rides the travel spring lifted the whole
///   way, coming down only on landing. Each lift axis rides its own spring -
///   the width overshoots a little further than the height, which is
///   what keeps the growth from reading as a plain scale-up - and the
///   deformation comes from the pill's own ACCELERATION, signed by the
///   direction of travel so it deforms one way for the whole journey;
/// - the BAR answers in sympathy, not by its own leash: the pill's drag
///   shifts the whole mass by at most 4px on an ease-out of the drag
///   fraction (springing home on release), and while the pill is up the
///   bar breathes 16px of width - both through the piece channel, so
///   the neck to the send button breathes along;
/// - the SEND companion keeps the button model ([Tug]) and is a real
///   morph source: tap it and the compose dialog grows out of it.
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
      controls: const Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          PanelHint(
            'The touch itself is the answer: the pill starts lifting IN '
            'PLACE the moment the finger lands - even between tabs - '
            'with no hold timer at all. A quick release is a tap (the '
            'light flips with the screens, the pill glides and lands), '
            'a carry moves it by the finger\'s own displacement and '
            'snaps on release.',
          ),
          PanelHint(
            'The bar itself has no leash: it answers in SYMPATHY - the '
            'drag shifts the whole mass by at most 4px on an ease-out, '
            'and while the pill is up the bar breathes a few pixels of '
            'width. One skin: the neck to the send button breathes '
            'along, and the send button is a real morph source.',
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

/// One frame of the pill, produced by the host's ticker and consumed by
/// the paint layer.
typedef _PillFrame = ({Rect rect});

/// One integration step of an underdamped spring, sub-stepped at 240 Hz
/// for stability - the reference integrator, ported verbatim.
(double, double) _springStep({
  required double x,
  required double vel,
  required double target,
  required double dt,
  required double stiffness,
  required double damping,
}) {
  double t = dt;
  double px = x;
  double pv = vel;
  while (t > 0) {
    final double step = t > 1 / 240.0 ? 1 / 240.0 : t;
    final double accel = -stiffness * (px - target) - damping * pv;
    pv += accel * step;
    px += pv * step;
    t -= step;
  }
  return (px, pv);
}

/// The ink track: the liquid-glass nav-bar pill HOST, constants
/// verbatim, painting ink instead of glass. The host owns every spring
/// and the ticker; the pill layer just draws the frame it is handed,
/// and the bar's sympathy goes out through the piece channel.
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
  // ── The reference constants, verbatim ────────────────────────────
  static const double _inset = 4;
  static const double _travelStiffness = 280;
  static const double _travelDamping = 31.4;
  static const double _liftStiffness = 250;
  // Damping ratio 0.6 across, 0.7 down: the width overshoots a little
  // further and settles a little later than the height - that small
  // disagreement keeps the growth from reading as a plain scale-up.
  static const double _liftDampingX = 19.0;
  static const double _liftDampingY = 22.1;
  static const double _pillGrowHeight = 12;
  static const double _handoverStart = 0.92;
  static const double _followTau = 0.05;
  static const double _signTau = 0.25;
  // The bar's sympathy (the reference bar): at most 4px of shift on an
  // ease-out of the drag fraction, 16px of width breathed while the
  // pill is up, and a stiff, non-bouncing return home.
  static const double _barShiftMax = 4;
  static const double _barBreathWidth = 16;
  static const double _barReturnStiffness = 300;
  static const double _pressStiffness = 1000;

  // ── Pill state (the reference host fields) ───────────────────────
  int _index = 0;

  /// What the cells light up: the LIVE choice - it flips the moment a
  /// tap commits (with the screens), and follows the nearest slot
  /// while the pill is carried.
  int _active = 0;
  double _travelPos = 0;
  double _travelVel = 0;
  double _travelTarget = 0;
  double _travelFrom = 0;
  bool _travelActive = false;
  bool _dragging = false;
  double _dragFollow = 0;
  double _dragTargetFrac = 0;
  double _grabFrac = 0;
  double _pressFrac = 0;
  bool _realMove = false;
  bool _lifted = false;
  double _liftX = 0;
  double _liftXVel = 0;
  double _liftY = 0;
  double _liftYVel = 0;
  double _travelSign = 0;
  double _travelSignEased = 0;
  final MorphSquash _squash = MorphSquash();

  // ── Bar sympathy state ───────────────────────────────────────────
  double _barAccum = 0;
  double _barAccumVel = 0;
  double _press = 0;
  double _pressVel = 0;
  double? _lastDragX;

  // ── The raw pointer (no timers: the DOWN is the answer) ──────────
  int? _pointer;
  double _downX = 0;

  /// The finger is down (dragging or not): the lift may not come down
  /// while the hand still holds the pill.
  bool _held = false;

  final ValueNotifier<_PillFrame> _pill = ValueNotifier<_PillFrame>((
    rect: Rect.zero,
  ));
  late final Ticker _ticker = createTicker(_tick);
  final Stopwatch _clock = Stopwatch()..start();
  double _clockLast = 0;

  double _slot = 0;
  double _width = 0;
  double _height = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.selected;
    _active = _index;
    _travelPos = _index.toDouble();
    _travelTarget = _travelPos;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pill.dispose();
    super.dispose();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _clockLast = _clock.elapsedMicroseconds / 1e6;
      _ticker.start();
    }
  }

  double _signOf(double span) => span.abs() < 1e-6 ? 0 : span.sign;

  // ── Selection / travel ───────────────────────────────────────────
  /// Launches (or resumes) a travel to [next] from wherever the pill
  /// currently stands - the one door every selection walks through, so
  /// an interrupted journey can never leave the pill stranded between
  /// slots.
  void _settleTo(int next, {required bool notify}) {
    final bool changed = next != _index;
    _index = next;
    _travelActive = true;
    _travelFrom = _travelPos;
    _travelTarget = next.toDouble();
    _travelSign = _signOf(_travelTarget - _travelFrom);
    // The light agrees with the screens: the emphasis flips the moment
    // the choice commits, not when the pill lands.
    if (_active != next) {
      setState(() => _active = next);
    }
    _wake();
    if (notify && changed) {
      widget.onSelect(next);
    }
  }

  // ── The raw pointer: no timers, the DOWN is the answer ───────────
  void _down(PointerDownEvent event) {
    if (_pointer != null || event.buttons != kPrimaryButton) {
      return;
    }
    _pointer = event.pointer;
    final double dx = event.localPosition.dx;
    _downX = dx;
    // The pill answers the touch itself: it starts lifting IN PLACE
    // immediately - a hold between tabs grows it where it lives. What
    // the gesture MEANS is decided later: a quick release is a tap, a
    // carry is a drag.
    _held = true;
    _dragging = false;
    _realMove = false;
    _travelActive = false;
    _lifted = true;
    // The hand takes the deformation back off the travel.
    _travelSign = 0;
    _dragFollow = _travelPos;
    _grabFrac = _travelPos;
    _travelVel = 0;
    _pressFrac = _toFrac(dx);
    _dragTargetFrac = _travelPos;
    _lastDragX = dx;
    _wake();
  }

  void _moveEvent(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    final double dx = event.localPosition.dx;
    if (!_dragging && (dx - _downX).abs() > 4) {
      _dragging = true;
      _lastDragX = dx;
    }
    if (!_dragging) {
      return;
    }
    // The delta rides the UNCLAMPED fraction: clamping inside the
    // difference would freeze the carry the moment the finger leaves
    // the track and desync it on the way back. Only the target clamps.
    final double frac = _toFrac(dx);
    if ((frac - _pressFrac).abs() > 0.2) {
      _realMove = true;
    }
    // Relative: the pill's target is where it was grabbed plus how far
    // the finger has travelled since - the native carry, not a jump
    // under the finger.
    _dragTargetFrac = (_grabFrac + (frac - _pressFrac)).clamp(
      0.0,
      (widget.tabs.length - 1).toDouble(),
    );
    _barAccum += dx - (_lastDragX ?? dx);
    _lastDragX = dx;
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    _held = false;
    if (_dragging) {
      _release();
      return;
    }
    // Never carried: a tap (or a motionless hold) selects the slot
    // under the finger. The same door also resumes a journey the DOWN
    // froze mid-flight, even when the slot did not change.
    _settleTo(
      (event.localPosition.dx / _slot).floor().clamp(0, widget.tabs.length - 1),
      notify: true,
    );
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    _held = false;
    if (_dragging) {
      _release();
      return;
    }
    // A cancelled touch resumes the pill's own journey home.
    _settleTo(_index, notify: false);
  }

  void _release() {
    final double from = _dragFollow;
    final double snap = _realMove ? from : _pressFrac;
    final int next = snap.round().clamp(0, widget.tabs.length - 1);
    // The pill stays lifted through the snap and comes down on
    // landing - letting go is not the end of the journey, arriving is.
    _dragging = false;
    _lastDragX = null;
    _travelPos = from;
    _travelVel = 0;
    _settleTo(next, notify: true);
  }

  /// The finger's x as a slot fraction, deliberately UNCLAMPED: the
  /// relative carry needs honest deltas past the track's edges.
  double _toFrac(double dx) => (dx - _slot / 2) / _slot;

  // ── The frame: every spring, the squash and the sympathy ─────────
  void _tick(Duration elapsed) {
    final double now = _clock.elapsedMicroseconds / 1e6;
    final double dt = now - _clockLast;
    _clockLast = now;
    if (dt <= 0 || _slot == 0) {
      return;
    }

    // 1) Travel (positional) spring.
    bool travelSettled = true;
    if (_travelActive) {
      final (double p, double v) = _springStep(
        x: _travelPos,
        vel: _travelVel,
        target: _travelTarget,
        dt: dt,
        stiffness: _travelStiffness,
        damping: _travelDamping,
      );
      _travelPos = p;
      _travelVel = v;
      travelSettled =
          (_travelPos - _travelTarget).abs() < 0.003 && _travelVel.abs() < 0.05;
      if (travelSettled) {
        _travelPos = _travelTarget;
        _travelVel = 0;
      }
    }

    // 2) While dragging, smoothly chase the finger target so a hold
    // away from the pill glides over to the held position.
    if (_dragging) {
      _dragFollow +=
          (_dragTargetFrac - _dragFollow) * (1 - math.exp(-dt / _followTau));
    }

    // 3) The lift: up for the whole journey, down once landed.
    final double progress = () {
      final double span = (_travelTarget - _travelFrom).abs();
      if (span < 1e-6) {
        return 1.0;
      }
      return (1 - (_travelTarget - _travelPos).abs() / span).clamp(0.0, 1.0);
    }();
    if (!_held && !_dragging && (travelSettled || progress >= _handoverStart)) {
      _lifted = false;
    }
    final double liftTarget = _lifted ? 1 : 0;
    final (double lx, double lxv) = _stepLift(
      _liftX,
      _liftXVel,
      liftTarget,
      dt,
      _liftDampingX,
    );
    _liftX = lx;
    _liftXVel = lxv;
    final (double ly, double lyv) = _stepLift(
      _liftY,
      _liftYVel,
      liftTarget,
      dt,
      _liftDampingY,
    );
    _liftY = ly;
    _liftYVel = lyv;
    final bool liftSettled = !_lifted && _liftX == 0 && _liftY == 0;

    // 4) The travel retires only once the lift has finished too: the
    // deflation outlives the spring that carried the pill there.
    if (_travelActive && travelSettled && liftSettled && !_dragging) {
      _travelActive = false;
    }
    // While the pill is CARRIED, the light follows it: the nearest
    // slot to the pill is the live choice under the hand.
    if (_dragging) {
      final int under = _dragFollow.round().clamp(0, widget.tabs.length - 1);
      if (under != _active) {
        setState(() => _active = under);
      }
    }

    // 5) The squash, sampled where the pill is drawn THIS frame, its
    // magnitude kept and its sign taken from the direction of travel -
    // the pill deforms one way for the whole journey instead of
    // turning itself inside out at the halfway mark; a reversal
    // crosses rather than switches.
    final double frac = _dragging ? _dragFollow : _travelPos;
    final double centerX = _slot * frac + _slot / 2;
    double deviation = _squash.track(Offset(centerX, 0), now: now, dt: dt);
    if (_travelSignEased == 0) {
      _travelSignEased = _travelSign;
    } else if (_travelSignEased != _travelSign) {
      _travelSignEased +=
          (_travelSign - _travelSignEased) * (1 - math.exp(-dt / _signTau));
      if ((_travelSign - _travelSignEased).abs() < 0.01) {
        _travelSignEased = _travelSign;
      }
    }
    final double key = _travelSignEased;
    if (key != 0) {
      deviation = deviation * (1 - key.abs()) - key * deviation.abs();
    }

    // 6) The pill frame: rest -> lifted per axis, then the deviation
    // on top (area held), centered on the travel.
    final Size rest = Size(_slot - _inset * 2, _height - _inset * 2);
    final double liftedH = _height + _pillGrowHeight;
    final Size lifted = Size(liftedH * (rest.width / rest.height), liftedH);
    final Size envelope = Size(
      rest.width + (lifted.width - rest.width) * _liftX,
      rest.height + (lifted.height - rest.height) * _liftY,
    );
    final Size live = Size(
      envelope.width * (1 + deviation),
      envelope.height * (1 - deviation),
    );
    _pill.value = (
      rect: Rect.fromCenter(
        center: Offset(centerX, _height / 2),
        width: live.width,
        height: live.height,
      ),
    );

    // 7) The bar's sympathy: press breathes the width, the drag shifts
    // the mass on an ease-out of the accumulated fraction, and the
    // accumulation springs home on release - all through the channel,
    // so the neck to the companion breathes along.
    final (double pp, double ppv) = _stepLift(
      _press,
      _pressVel,
      liftTarget,
      dt,
      2 * math.sqrt(_pressStiffness),
      stiffness: _pressStiffness,
    );
    _press = pp;
    _pressVel = ppv;
    if (!_dragging) {
      final (double a, double av) = _springStep(
        x: _barAccum,
        vel: _barAccumVel,
        target: 0,
        dt: dt,
        stiffness: _barReturnStiffness,
        damping: 2 * math.sqrt(_barReturnStiffness),
      );
      _barAccum = a;
      _barAccumVel = av;
      if (_barAccum.abs() < 0.05 && _barAccumVel.abs() < 0.5) {
        _barAccum = 0;
        _barAccumVel = 0;
      }
    }
    final double fraction = (_barAccum / math.max(_width, 1)).clamp(-1.0, 1.0);
    final double shift =
        _barShiftMax * fraction.sign * Curves.easeOut.transform(fraction.abs());
    final double breath = 1 + _press * _barBreathWidth / math.max(_width, 1);
    widget.barChannel.update(
      offset: Offset(shift, 0),
      scaleX: breath,
      scaleY: breath,
    );

    // 8) Everything must be finished - the deformation drains after
    // the spring does, and the sympathy after both.
    final bool motionSettled = deviation.abs() < 0.0005;
    final bool barSettled = _barAccum == 0 && _press == 0;
    if (!_travelActive &&
        !_dragging &&
        liftSettled &&
        motionSettled &&
        barSettled) {
      _squash.reset();
      _travelSign = 0;
      _travelSignEased = 0;
      _ticker.stop();
    }
  }

  /// One frame of a lift spring, snapped to its target once it has
  /// nothing left to say.
  (double, double) _stepLift(
    double x,
    double vel,
    double target,
    double dt,
    double damping, {
    double stiffness = _liftStiffness,
  }) {
    final (double p, double v) = _springStep(
      x: x,
      vel: vel,
      target: target,
      dt: dt,
      stiffness: stiffness,
      damping: damping,
    );
    if ((p - target).abs() < 0.001 && v.abs() < 0.01) {
      return (target, 0);
    }
    return (p, v);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _slot = constraints.maxWidth / widget.tabs.length;
        _width = constraints.maxWidth;
        _height = constraints.maxHeight;
        if (_pill.value.rect == Rect.zero) {
          _pill.value = (
            rect: Rect.fromCenter(
              center: Offset(_slot * _index + _slot / 2, _height / 2),
              width: _slot - _inset * 2,
              height: _height - _inset * 2,
            ),
          );
        }
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          // A raw Listener, no recognizers and no timers: the pill
          // starts lifting on the DOWN itself - the instant answer the
          // native bar gives - and what the gesture MEANT (a tap, a
          // hold, a carry) is read from what the pointer then does.
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _moveEvent,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: Stack(
              clipBehavior: .none,
              children: <Widget>[
                ValueListenableBuilder<_PillFrame>(
                  valueListenable: _pill,
                  builder:
                      (BuildContext context, _PillFrame frame, Widget? child) {
                        return Positioned(
                          left: frame.rect.left,
                          top: frame.rect.top,
                          width: frame.rect.width,
                          height: frame.rect.height,
                          child: child!,
                        );
                      },
                  child: DecoratedBox(
                    // Ink, not glass: an opaque wash of accent soaked
                    // into the surface, no outline.
                    decoration: ShapeDecoration(
                      color: Color.alphaBlend(
                        widget.accent.withValues(alpha: 0.16),
                        widget.surface,
                      ),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    for (int i = 0; i < widget.tabs.length; i++)
                      SizedBox(
                        width: _slot,
                        height: _height,
                        child: _Cell(
                          icon: widget.tabs[i].$1,
                          label: widget.tabs[i].$2,
                          // The light is LIVE: it flips with the choice
                          // (and with the screens), and follows the
                          // nearest slot while the pill is carried.
                          active: i == _active,
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

/// One slot's content: icon over label, emphasis following the
/// COMMITTED selection (it flips when the pill lands).
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
