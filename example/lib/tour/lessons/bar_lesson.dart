import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';
import 'package:morph_example/tour/lessons/dialog_contents.dart';
import 'package:morph_example/ui/goo_selector.dart';
import 'package:stupid_simple_sheet/stupid_simple_sheet.dart';

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
/// [MorphMotion.glass] - the same spring the button itself presses
/// and returns on.
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

  /// The piece's REAL channel: the composition of the Tug's writes and
  /// the sheet's yield lands here.
  final MorphPieceChannel _sendPull = MorphPieceChannel();

  /// The Tug's private channel: it never reaches the skin directly -
  /// [_syncSend] multiplies the yield in and forwards.
  final MorphPieceChannel _sendTug = MorphPieceChannel();

  int _selected = 0;

  /// How the compose surface opens: 0 - the morph dialog (the button
  /// BECOMES the surface), 1 - the foreign sheet (the button YIELDS to
  /// it).
  int _composeMode = 0;

  /// The foreign sheet's progress, 0..1 - the one driver of the yield.
  double _yield = 0;

  @override
  void initState() {
    super.initState();
    _sendTug.addListener(_syncSend);
  }

  @override
  void dispose() {
    _sendTug.removeListener(_syncSend);
    _barPull.dispose();
    _sendPull.dispose();
    _sendTug.dispose();
    super.dispose();
  }

  /// The friendship composition: the Tug's live write times the yield.
  /// While the sheet rises the button gives up a little of its mass
  /// and sinks toward the bar; the sheet's own drag drives the same
  /// animation, so pulling the sheet down revives the button LIVE.
  void _syncSend() {
    final double deflate = 1 - 0.08 * _yield;
    _sendPull.update(
      offset: Offset(_sendTug.offset.dx, _sendTug.offset.dy + 3 * _yield),
      scaleX: _sendTug.scaleX * deflate,
      scaleY: _sendTug.scaleY * deflate,
    );
  }

  void _openSheet(BuildContext buttonContext) {
    final StupidSimpleCupertinoSheetRoute<void> route =
        StupidSimpleCupertinoSheetRoute<void>(
          // The material rises the way the buttons press: the same
          // glass spring, handed straight to the foreign route.
          motion: MorphMotion.glass.closeMotion,
          backgroundColor: const Color(0xFF262038),
          child: const _ComposeSheet(),
        );
    Navigator.of(buttonContext).push(route);
    final Animation<double> animation = route.animation!;
    void tick() {
      _yield = animation.value;
      _syncSend();
    }

    animation.addListener(tick);
    route.popped.whenComplete(() {
      animation.removeListener(tick);
      _yield = 0;
      _syncSend();
    });
  }

  void _compose(BuildContext buttonContext) {
    if (_composeMode == 1) {
      _openSheet(buttonContext);
      return;
    }
    showMorphDialog(
      buttonContext,
      from: 'bar-send',
      width: 306,
      height: 420,
      // The material closes the way it presses: MorphMotion.glass's
      // close IS the Tug spring, so the dialog lands in the send
      // button with the button's own character.
      motion: MorphMotion.glass,
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
            'The touch itself is the answer: the pill starts lifting IN '
            'PLACE the moment the finger lands - even between tabs - '
            'with no hold timer at all. A quick release is a tap (the '
            'light flips with the screens, the pill glides and lands), '
            'a carry moves it by the finger\'s own displacement and '
            'snaps on release.',
          ),
          PanelSection(
            label: 'COMPOSE OPENS AS',
            child: GooSelector(
              labels: const <String>['morph dialog', 'foreign sheet'],
              index: _composeMode,
              onSelect: (int i) => setState(() => _composeMode = i),
            ),
          ),
          const PanelHint(
            'Dialog: the button BECOMES the surface - one morph flight, '
            'closing on the button\'s own glass spring. Sheet: a foreign '
            'route (stupid_simple_sheet) rises on that same spring, and '
            'the button YIELDS to it - a little mass and a couple px '
            'given up, returned as the sheet leaves. Drag the sheet '
            'down slowly: its own gesture drives the same animation, so '
            'the finger revives the button live.',
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
                            channel: _sendTug,
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

/// The compose sheet's body: set dressing for the friendship demo -
/// the surface itself belongs to the foreign route.
class _ComposeSheet extends StatelessWidget {
  const _ComposeSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const .fromLTRB(20, 10, 20, 20),
        child: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: .circular(2),
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'New message',
              style: TextStyle(fontSize: 19, fontWeight: .w800),
            ),
            const SizedBox(height: 14),
            for (final double width in const <double>[
              double.infinity,
              double.infinity,
              180,
            ]) ...<Widget>[
              Container(
                height: 40,
                width: width,
                decoration: BoxDecoration(
                  borderRadius: .circular(12),
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const Spacer(),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Send'),
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
  bool _placed = false;

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
    widget.barChannel.update(
      offset: Offset(_host.chromeShift(_width), 0),
      scaleX: _host.chromeBreath(_width),
      scaleY: _host.chromeBreath(_width),
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
        if (!_placed || (previousSlot != _slot && !_host.held)) {
          _placed = true;
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
                ListenableBuilder(
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
                    return Positioned(
                      left: _host.centerX - live.width / 2,
                      top: _height / 2 - live.height / 2,
                      width: math.max(1, live.width),
                      height: math.max(1, live.height),
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
