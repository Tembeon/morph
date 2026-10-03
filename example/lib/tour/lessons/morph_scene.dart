import 'package:material_ui/material_ui.dart';

import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';
import 'package:morph_example/tour/lessons/dialog_contents.dart';
import 'package:morph_example/ui/lab_chrome.dart';
import 'package:morph_example/ui/spring_switcher.dart';

/// The opening scene: a mail app whose compose button becomes the
/// compose dialog. One mockup, one flight - and the lesson layers are
/// knobs over that same flight, not separate screens: Motion swaps the
/// spring profile, Interrupt runs a scripted storm of mid-air closes.
/// Both layers answer the same question from a different side: what
/// happens between a button and its dialog.
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
    ('liquid', .liquid),
    ('glacial', .glacial),
    ('instant', .instant),
  ];

  late MorphMotion _motion = widget.motion;
  late int _profile = switch (_profiles.indexWhere(
    ((String, MorphMotion) record) => identical(record.$2, widget.motion),
  )) {
    -1 => 0,
    final int found => found,
  };
  int _layer = 0;
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
          return _MailApp(onCompose: _openCompose);
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
          child: LabSegmented(
            labels: const <String>['Motion', 'Interrupt'],
            index: _layer,
            onSelect: (int i) => setState(() => _layer = i),
          ),
        ),
        SpringSwitcher(
          child: KeyedSubtree(
            key: ValueKey<int>(_layer),
            child: switch (_layer) {
              0 => _motionLayer(),
              _ => _interruptLayer(),
            },
          ),
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
          child: LabSegmented(
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
}

/// The mail mockup: inbox rows and the compose pill. The pill carries
/// the morph identity; everything else is set dressing.
class _MailApp extends StatelessWidget {
  static const Color _composeColor = Color(0xFF7C5CFF);

  const _MailApp({required this.onCompose});

  final void Function(BuildContext context) onCompose;

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
                padding: const .only(bottom: 90),
                itemCount: _mail.length,
                itemBuilder: (BuildContext context, int index) =>
                    _MailRow(mail: _mail[index], index: index),
              ),
            ),
          ],
        ),
        Positioned(
          right: 14,
          bottom: 14,
          child: MorphTag(
            id: 'mail-compose',
            spec: const MorphSurfaceSpec(
              shape: StadiumBorder(),
              color: _composeColor,
              elevation: 0,
            ),
            child: Builder(
              builder: (BuildContext context) => MorphGlassButton(
                tint: _composeColor,
                padding: const .symmetric(horizontal: 18, vertical: 13),
                onPressed: () => onCompose(context),
                child: const Row(
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
