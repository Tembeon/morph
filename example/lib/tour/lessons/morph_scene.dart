import 'package:flutter/material.dart';

import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';
import 'package:morph_example/tour/lessons/dialog_contents.dart';
import 'package:morph_example/ui/goo_selector.dart';
import 'package:morph_example/ui/lab_chrome.dart';
import 'package:morph_example/ui/spring_switcher.dart';

/// The opening scene: a mail app whose compose button becomes the
/// compose dialog. One mockup, one flight - and the lesson layers are
/// knobs over that same flight, not separate screens: Motion swaps the
/// spring profile, Interrupt runs a scripted storm of mid-air closes,
/// Landing hands over the bump knobs. Every layer answers the same
/// question from a different side: what happens between a button and
/// its dialog.
class MorphScene extends StatefulWidget {
  /// Creates the chapter scene.
  const MorphScene({super.key, required this.motion});

  /// Initial motion profile of the compose flight.
  final MorphMotion motion;

  @override
  State<MorphScene> createState() => _MorphSceneState();
}

class _MorphSceneState extends State<MorphScene> {
  static const List<(String, MorphMotion)> _profiles = <(String, MorphMotion)>[
    ('glacial', .glacial),
    ('slow', .slow),
    ('normal', .normal),
    ('fast', .fast),
  ];

  late MorphMotion _motion = widget.motion;
  late int _profile = switch (_profiles.indexWhere(
    ((String, MorphMotion) record) => identical(record.$2, widget.motion),
  )) {
    -1 => 2,
    final int found => found,
  };
  int _layer = 0;
  double _bumpScale = 0.8;
  double _bumpRecoil = 180;
  bool _torturing = false;
  BuildContext? _phoneContext;

  MorphFlight _openCompose(BuildContext context) {
    return showMorphDialog(
      context,
      from: 'mail-compose',
      width: 306,
      height: 420,
      motion: _motion,
      semanticLabel: 'New message',
      builder: (BuildContext context, MorphFlight flight) =>
          ComposeDialogContent(flight: flight),
    );
  }

  /// The same spring flying to a COMPACT anchored popover. The lever
  /// that changes how a morph reads is the SIZE DELTA, not the anchor:
  /// a target that nearly fills the phone is a centered dialog no
  /// matter what it is anchored to, while a compact popover keeps the
  /// container near the button's own aspect for most of the flight -
  /// the calm morph.
  MorphFlight _openNote(BuildContext context) {
    return showMorph(
      context,
      target: MorphTargetSpec.popover(
        anchor: morphAnchorRect(context),
        size: const Size(260, 240),
        gap: 8,
      ),
      motion: _motion,
      semanticLabel: 'Quick note',
      builder: (BuildContext context, MorphFlight flight) =>
          _QuickNoteContent(flight: flight),
    );
  }

  /// The interruption storm: opens the compose flight and closes it
  /// mid-air, three times with shrinking patience - the retarget
  /// contract, visible without fast fingers.
  Future<void> _torture() async {
    final BuildContext? phone = _phoneContext;
    if (_torturing || phone == null || !phone.mounted) {
      return;
    }
    setState(() => _torturing = true);
    try {
      for (final (int hold, int gap) in const <(int, int)>[
        (240, 180),
        (300, 140),
        (900, 0),
      ]) {
        if (!phone.mounted) {
          return;
        }
        final MorphFlight flight = _openCompose(phone);
        await Future<void>.delayed(Duration(milliseconds: hold));
        flight.close();
        await Future<void>.delayed(Duration(milliseconds: gap));
      }
    } finally {
      if (mounted) {
        setState(() => _torturing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SceneScaffold(
      controls: _panel(),
      phone: PhoneFrame(
        app: (BuildContext context) {
          _phoneContext = context;
          return _MailApp(
            bumpScale: _bumpScale,
            bumpRecoil: _bumpRecoil,
            onCompose: _openCompose,
            onNote: _openNote,
          );
        },
      ),
    );
  }

  Widget _panel() {
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        PanelSection(
          label: 'LAYER',
          child: GooSelector(
            labels: const <String>['Motion', 'Interrupt', 'Landing'],
            index: _layer,
            onSelect: (int i) => setState(() => _layer = i),
          ),
        ),
        SpringSwitcher(
          child: KeyedSubtree(
            key: ValueKey<int>(_layer),
            child: switch (_layer) {
              0 => _motionLayer(),
              1 => _interruptLayer(),
              _ => _landingLayer(),
            },
          ),
        ),
        const PanelHint(
          'Two buttons, one spring, two TARGETS: New message flies to a '
          'full centered dialog and pays the stretch phase (the '
          'container must cross from the pill\'s aspect to the '
          'dialog\'s), Quick note opens a compact popover hugging the '
          'button - a small size delta keeps the flight near the '
          'pill\'s own shape. The calm morph is a target-size choice.',
        ),
      ],
    );
  }

  Widget _motionLayer() {
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        PanelSection(
          label: 'PROFILE',
          child: GooSelector(
            labels: <String>[for (final (String n, _) in _profiles) n],
            index: _profile,
            onSelect: (int i) => setState(() {
              _profile = i;
              _motion = _profiles[i].$2;
            }),
          ),
        ),
        const PanelHint(
          'Tap New message. The button IS the dialog: one MorphTag, one '
          'showMorphDialog call. Glacial is the magnifier - watch the '
          'corner radius derive from live geometry.',
        ),
      ],
    );
  }

  Widget _interruptLayer() {
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        PanelSection(
          label: 'STORM',
          child: Align(
            alignment: Alignment.centerLeft,
            child: LabActionButton(
              label: _torturing ? 'torturing...' : 'Interruption torture',
              icon: Icons.bolt_rounded,
              onPressed: _torturing ? null : _torture,
            ),
          ),
        ),
        const PanelHint(
          'Or just re-tap mid-flight yourself. Every open and close is a '
          'new simulation seeded from the CURRENT value and velocity - '
          'there is no timeline to rewind, so nothing ever jumps.',
        ),
      ],
    );
  }

  Widget _landingLayer() {
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        PanelSection(
          label: 'BUMP',
          child: Column(
            children: <Widget>[
              PanelKnob(
                label: 'squash',
                value: _bumpScale,
                min: 0,
                max: 1.5,
                format: (double v) => v.toStringAsFixed(2),
                onChanged: (double v) => setState(() => _bumpScale = v),
              ),
              PanelKnob(
                label: 'recoil',
                value: _bumpRecoil,
                min: 0,
                max: 300,
                format: (double v) => '${v.round()}px',
                onChanged: (double v) => setState(() => _bumpRecoil = v),
              ),
            ],
          ),
        ),
        const PanelHint(
          'Close the dialog and watch the button absorb the impact: '
          'squash rides the spring undershoot along the flight axis, '
          'recoil kicks the button off its spot. A timing curve never '
          'crosses zero - it cannot land.',
        ),
      ],
    );
  }
}

/// The mail mockup: inbox rows and the compose pill. The pill carries
/// the morph identity; everything else is set dressing.
class _MailApp extends StatelessWidget {
  const _MailApp({
    required this.bumpScale,
    required this.bumpRecoil,
    required this.onCompose,
    required this.onNote,
  });

  final double bumpScale;
  final double bumpRecoil;
  final void Function(BuildContext context) onCompose;
  final void Function(BuildContext context) onNote;

  static const List<(String, String, String)> _mail =
      <(String, String, String)>[
        ('Ava', 'Re: springs everywhere', '9:12'),
        ('Marcus', 'The demo build is live', '8:47'),
        ('Noah', 'Lunch on Thursday?', '8:20'),
        ('Priya', 'Design review notes', 'Yesterday'),
        ('Leo', 'That shader idea', 'Yesterday'),
        ('Mia', 'Weekend plans', 'Tue'),
        ('Sam', 'Invoice #1042', 'Mon'),
      ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            const Padding(
              padding: .fromLTRB(20, 12, 20, 10),
              child: Text(
                'Inbox',
                style: TextStyle(fontSize: 24, fontWeight: .w800),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const .only(bottom: 140),
                itemCount: _mail.length,
                itemBuilder: (BuildContext context, int index) =>
                    _MailRow(mail: _mail[index], index: index),
              ),
            ),
          ],
        ),
        // The anchored twin: same spring, same content, but the target
        // is a popover growing out of THIS button's edge.
        Positioned(
          right: 14,
          bottom: 66,
          child: MorphTag(
            id: 'mail-note',
            spec: const MorphSurfaceSpec(
              shape: StadiumBorder(),
              color: Color(0xFF4CC5B8),
              elevation: 4,
            ),
            bumpScale: bumpScale,
            bumpRecoil: bumpRecoil,
            child: MorphSurface(
              onTap: onNote,
              child: const Padding(
                padding: .symmetric(horizontal: 18, vertical: 13),
                child: Row(
                  mainAxisSize: .min,
                  children: <Widget>[
                    Icon(Icons.sticky_note_2_outlined, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Quick note',
                      style: TextStyle(fontSize: 13, fontWeight: .w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 14,
          bottom: 14,
          child: MorphTag(
            id: 'mail-compose',
            spec: const MorphSurfaceSpec(
              shape: StadiumBorder(),
              color: Color(0xFF7C5CFF),
              elevation: 4,
            ),
            bumpScale: bumpScale,
            bumpRecoil: bumpRecoil,
            child: MorphSurface(
              onTap: onCompose,
              child: const Padding(
                padding: .symmetric(horizontal: 18, vertical: 13),
                child: Row(
                  mainAxisSize: .min,
                  children: <Widget>[
                    Icon(Icons.edit_rounded, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'New message',
                      style: TextStyle(fontSize: 13, fontWeight: .w600),
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

class _MailRow extends StatelessWidget {
  const _MailRow({required this.mail, required this.index});

  final (String, String, String) mail;
  final int index;

  @override
  Widget build(BuildContext context) {
    final Color tint = Color.lerp(
      const Color(0xFF7C5CFF),
      const Color(0xFF4CC5B8),
      (index % 5) / 4,
    )!;
    return Padding(
      padding: const .fromLTRB(14, 3, 14, 3),
      child: Container(
        padding: const .symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: .circular(14),
          color: Colors.white.withValues(alpha: 0.035),
        ),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 15,
              backgroundColor: tint.withValues(alpha: 0.3),
              child: Text(
                mail.$1[0],
                style: TextStyle(fontSize: 13, fontWeight: .w700, color: tint),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: <Widget>[
                  Text(
                    mail.$1,
                    style: const TextStyle(fontSize: 12.5, fontWeight: .w700),
                  ),
                  Text(
                    mail.$2,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              mail.$3,
              style: TextStyle(
                fontSize: 10.5,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The compact popover content: sized for a note, not a form - the
/// point of the twin button is the small size delta.
class _QuickNoteContent extends StatelessWidget {
  const _QuickNoteContent({required this.flight});

  final MorphFlight flight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          const Text(
            'New note',
            style: TextStyle(fontSize: 15, fontWeight: .w700),
          ),
          const SizedBox(height: 10),
          MorphReveal(
            from: 0.4,
            to: 0.9,
            child: TextField(
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Jot it down...',
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: .circular(12),
                  borderSide: .none,
                ),
              ),
            ),
          ),
          const Spacer(),
          MorphReveal(
            from: 0.55,
            to: 1,
            child: Align(
              alignment: Alignment.centerRight,
              child: SpringButton(
                onPressed: flight.close,
                child: Container(
                  padding: const .symmetric(horizontal: 16, vertical: 9),
                  decoration: const ShapeDecoration(
                    shape: StadiumBorder(),
                    color: Color(0xFF4CC5B8),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 12.5, fontWeight: .w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
