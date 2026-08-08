import 'package:flutter/material.dart';
import 'package:morph/widgets.dart';

import 'package:morph_example/ui/goo_selector.dart';
import 'package:morph_example/ui/lab_chrome.dart';
import 'package:morph_example/ui/spring_switcher.dart';
import 'package:morph_example/ui/spring_toggle.dart';

import 'package:morph_example/tour/lessons/dialog_contents.dart';
import 'package:morph_example/playground/hud.dart';
import 'package:morph_example/playground/sandbox.dart';
import 'package:morph_example/playground/stress_lab.dart';
import 'package:morph_example/flags.dart';

/// Motion family for the lab: the engine accepts any Motion,
/// the lab shows the three vocabularies shipped with motor.
enum MotionFamily {
  /// CupertinoMotion springs (the presets live here).
  cupertino,

  /// Material 3 expressive spatial tokens.
  material,

  /// Timing curves - a live demo of why close needs a spring.
  curve,
}

/// All playground knobs. The motion profile is assembled from the selected
/// family and its parameters until a named preset is chosen.
class LabSettings {
  /// The selected motion vocabulary.
  MotionFamily family = .cupertino;

  /// The selected named preset; null once a slider builds a custom one.
  MorphMotion? preset = .normal;

  /// Open duration knob, ms.
  double openMs = 400;

  /// Close duration knob, ms.
  double closeMs = 550;

  /// Close bounce knob.
  double closeBounce = 0.27;

  /// Close velocity injection knob (stored positive).
  double closeKick = 2.5;

  /// Index into [materialTokens].
  int materialIndex = 1;

  /// Index into [curveOptions] for open.
  int openCurveIndex = 1;

  /// Index into [curveOptions] for close.
  int closeCurveIndex = 0;

  /// Landing squash knob.
  double bumpScale = 0.6;

  /// Landing recoil knob, px.
  double bumpRecoil = 140;

  /// The Material 3 spatial tokens on offer.
  static const List<(String, MaterialSpringMotion)> materialTokens =
      <(String, MaterialSpringMotion)>[
        ('standardSpatialFast', MaterialSpringMotion.standardSpatialFast()),
        (
          'standardSpatialDefault',
          MaterialSpringMotion.standardSpatialDefault(),
        ),
        ('standardSpatialSlow', MaterialSpringMotion.standardSpatialSlow()),
        ('expressiveSpatialFast', MaterialSpringMotion.expressiveSpatialFast()),
        (
          'expressiveSpatialDefault',
          MaterialSpringMotion.expressiveSpatialDefault(),
        ),
        ('expressiveSpatialSlow', MaterialSpringMotion.expressiveSpatialSlow()),
      ];

  /// The timing curves on offer.
  static const List<(String, Curve)> curveOptions = <(String, Curve)>[
    ('easeInOut', Curves.easeInOut),
    ('easeOutCubic', Curves.easeOutCubic),
    ('linearToEaseOut', Curves.linearToEaseOut),
    ('easeOutBack', Curves.easeOutBack),
    ('bounceOut', Curves.bounceOut),
    ('linear', Curves.linear),
  ];

  /// The profile assembled from the current family and knobs.
  MorphMotion get motion => switch (family) {
    .cupertino =>
      preset ??
          MorphMotion(
            name: 'custom',
            openMotion: CupertinoMotion.smooth(
              duration: Duration(milliseconds: openMs.round()),
            ),
            closeMotion: CupertinoMotion(
              duration: Duration(milliseconds: closeMs.round()),
              bounce: closeBounce,
            ),
            closeVelocityHint: -closeKick,
          ),
    .material => MorphMotion(
      name: 'm3',
      openMotion: materialTokens[materialIndex].$2,
      closeMotion: materialTokens[materialIndex].$2,
      closeVelocityHint: -closeKick,
    ),
    // Curves cannot go below zero: the morph works, but the landing
    // bump will not play - a live demo of the closeMotion contract.
    .curve => MorphMotion(
      name: 'curve',
      openMotion: CurvedMotion(
        Duration(milliseconds: openMs.round()),
        curveOptions[openCurveIndex].$2,
      ),
      closeMotion: CurvedMotion(
        Duration(milliseconds: closeMs.round()),
        curveOptions[closeCurveIndex].$2,
      ),
    ),
  };

  /// Selects a named preset and mirrors its numbers into the knobs.
  void adoptPreset(MorphMotion next) {
    family = .cupertino;
    preset = next;
    if (next.openMotion case CupertinoMotion(:final Duration duration)) {
      openMs = duration.inMilliseconds.toDouble();
    }
    if (next.closeMotion case CupertinoMotion(
      :final Duration duration,
      :final double bounce,
    )) {
      closeMs = duration.inMilliseconds.toDouble();
      closeBounce = bounce;
    }
    closeKick = -next.closeVelocityHint;
  }
}

/// The tuning room, as the final chapter of the tour -
/// sandbox canvas, motion vocabularies, landing knobs, keyframes,
/// liquid controls, stress rig and the spring HUD.
class Playground extends StatefulWidget {
  /// Creates the playground chapter.
  const Playground({super.key});

  @override
  State<Playground> createState() => _PlaygroundState();
}

class _PlaygroundState extends State<Playground> {
  final LabSettings lab = LabSettings();
  final SandboxController sandbox = SandboxController();
  bool _hudVisible = true;
  bool _tortureRunning = false;
  bool _stressMode = false;
  double _stressCount = 24;
  bool _stressAnimate = true;

  void _update(VoidCallback change) => setState(change);

  Motion get _sandboxMotion => appReducedMotion.value
      ? MorphMotion.instant.openMotion
      : lab.motion.openMotion;

  @override
  void dispose() {
    sandbox.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (kAutoDemo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runAutoDemo());
    }
  }

  /// Piece used by autodemo and torture flights: id 2 (the player),
  /// or the first live piece if it was removed.
  SandboxPiece get _flightPiece {
    for (final SandboxPiece p in sandbox.pieces) {
      if (p.id == 2) {
        return p;
      }
    }
    return sandbox.pieces.first;
  }

  Future<void> _runAutoDemo() async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) {
      return;
    }
    final SandboxPiece piece = _flightPiece;
    final MorphFlight compose = showMorphDialog(
      context,
      from: piece.id,
      width: 480,
      height: 460,
      motion: lab.motion,
      builder: (BuildContext context, MorphFlight flight) =>
          ComposeDialogContent(flight: flight),
    );
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    compose.close();
    await compose.closed;
    if (!mounted) {
      return;
    }
    await _runTorture(context);
    for (int i = 0; i < 4; i++) {
      if (!mounted) {
        return;
      }
      sandbox.playToggle(_sandboxMotion);
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
  }

  MorphFlight _openPlayer(BuildContext context) {
    return showMorphDialog(
      context,
      from: _flightPiece.id,
      width: 440,
      height: 520,
      motion: lab.motion,
      builder: (BuildContext context, MorphFlight flight) =>
          PlayerDialogContent(flight: flight),
    );
  }

  Future<void> _runTorture(BuildContext context) async {
    if (_tortureRunning) {
      return;
    }
    setState(() => _tortureRunning = true);
    try {
      final MorphFlight flight = _openPlayer(context);
      await Future<void>.delayed(const Duration(milliseconds: 240));
      flight.close();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!context.mounted) {
        return;
      }
      final MorphFlight second = _openPlayer(context);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      second.close();
      await Future<void>.delayed(const Duration(milliseconds: 140));
      if (!context.mounted) {
        return;
      }
      final MorphFlight third = _openPlayer(context);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      third.close();
    } finally {
      if (mounted) {
        setState(() => _tortureRunning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: .circular(18),
      child: Row(
        children: <Widget>[
          SizedBox(width: 320, child: _Sidebar(shell: this)),
          const VerticalDivider(width: 1),
          Expanded(
            child: Stack(
              children: <Widget>[
                const Positioned.fill(child: _CanvasBackground()),
                Positioned.fill(
                  bottom: _hudVisible ? 174 : 0,
                  child: Padding(
                    padding: const .all(16),
                    // Stress mode swaps the sandbox for the orbit rig;
                    // the LIQUID knobs (blend/detail) keep applying, so
                    // the stage listens to the sandbox controller. The
                    // canvas swap itself rides a spring (SpringSwitcher).
                    child: SpringSwitcher(
                      rise: 22,
                      child: _stressMode
                          ? KeyedSubtree(
                              key: const ValueKey<String>('canvas-stress'),
                              child: ListenableBuilder(
                                listenable: sandbox,
                                builder:
                                    (BuildContext context, Widget? child) =>
                                        StressLab(
                                          count: _stressCount.round(),
                                          animate: _stressAnimate,
                                          blend: sandbox.blend,
                                          cell: sandbox.cell,
                                        ),
                              ),
                            )
                          : KeyedSubtree(
                              key: const ValueKey<String>('canvas-sandbox'),
                              child: SandboxStage(
                                controller: sandbox,
                                motion: lab.motion,
                                bumpScale: lab.bumpScale,
                                bumpRecoil: lab.bumpRecoil,
                              ),
                            ),
                    ),
                  ),
                ),
                if (_hudVisible)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Builder(
                      builder: (BuildContext context) => SpringHud(
                        lastFlight: MorphScope.of(context).lastFlight,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.shell});

  final _PlaygroundState shell;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final LabSettings lab = shell.lab;
    return ListView(
      padding: const .all(20),
      children: <Widget>[
        const SizedBox(height: 4),

        _SectionHeader('MOTION', scheme),
        const SizedBox(height: 8),
        GooSelector(
          labels: const <String>['cupertino', 'm3', 'curve'],
          index: lab.family.index,
          onSelect: (int i) =>
              shell._update(() => lab.family = MotionFamily.values[i]),
        ),
        const SizedBox(height: 4),
        SpringSwitcher(
          child: KeyedSubtree(
            key: ValueKey<MotionFamily>(lab.family),
            child: Column(
              crossAxisAlignment: .stretch,
              children: _familyPanel(context, scheme, lab),
            ),
          ),
        ),
        const Divider(height: 28),

        _SectionHeader('LANDING', scheme),
        _LabSlider(
          label: 'squash',
          value: lab.bumpScale,
          min: 0,
          max: 1.5,
          format: (double v) => v.toStringAsFixed(2),
          onChanged: (double v) => shell._update(() => lab.bumpScale = v),
        ),
        _LabSlider(
          label: 'recoil',
          value: lab.bumpRecoil,
          min: 0,
          max: 300,
          format: (double v) => '${v.round()}px',
          onChanged: (double v) => shell._update(() => lab.bumpRecoil = v),
        ),
        Text(
          'Landing after the latch: squash along the impact axis and button '
          'recoil, both derived from the undershoot of the same spring.',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        const Divider(height: 28),

        ListenableBuilder(
          listenable: shell.sandbox,
          builder: (BuildContext context, Widget? child) =>
              _SandboxPanel(shell: shell, scheme: scheme),
        ),
        const Divider(height: 28),

        _SectionHeader('STRESS', scheme),
        SpringToggleTile(
          label: 'Stress mode',
          value: shell._stressMode,
          onChanged: (bool v) => shell._update(() => shell._stressMode = v),
        ),
        SpringSwitcher(
          child: KeyedSubtree(
            key: ValueKey<bool>(shell._stressMode),
            child: Column(
              crossAxisAlignment: .stretch,
              children: !shell._stressMode
                  ? const <Widget>[]
                  : <Widget>[
                      _LabSlider(
                        label: 'pieces',
                        value: shell._stressCount,
                        min: 4,
                        max: 64,
                        format: (double v) => v.round().toString(),
                        onChanged: (double v) =>
                            shell._update(() => shell._stressCount = v),
                      ),
                      SpringToggleTile(
                        label: 'Animate',
                        value: shell._stressAnimate,
                        onChanged: (bool v) =>
                            shell._update(() => shell._stressAnimate = v),
                      ),
                      Text(
                        'Orbiting pieces re-trace the skin every frame; the '
                        'meter shows average FPS and the worst frame per '
                        'window. Blend and detail from LIQUID apply here '
                        'too. Judge real numbers in --profile or --release: '
                        'debug is pessimistic.',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
            ),
          ),
        ),
        const Divider(height: 28),

        ValueListenableBuilder<bool>(
          valueListenable: appReducedMotion,
          builder: (BuildContext context, bool reduced, Widget? child) =>
              SpringToggleTile(
                label: 'Reduced motion',
                value: reduced,
                onChanged: (bool v) => appReducedMotion.value = v,
              ),
        ),
        SpringToggleTile(
          label: 'Spring HUD',
          value: shell._hudVisible,
          onChanged: (bool v) => shell._update(() => shell._hudVisible = v),
        ),
        const SizedBox(height: 8),
        LabActionButton(
          label: 'Interruption torture',
          icon: Icons.bolt_rounded,
          onPressed: shell._tortureRunning
              ? null
              : () => shell._runTorture(context),
        ),
        const Divider(height: 28),

        _SectionHeader('WHAT TO TRY', scheme),
        const SizedBox(height: 10),
        for (final String note in const <String>[
          ('The whole canvas is a sandbox: tap selects a piece, drag moves '
              'it (the neck stretches and snaps), double-tap flies a morph'),
          ('Keyframes: arrange the pieces, set A, rearrange them, set B - '
              'then morph A/B on the current Motion (press mid-flight too)'),
          ('Link: select a piece, press link, tap another - a tube bridge; '
              'tapping the same pair again breaks it'),
          ('Three motion vocabularies: cupertino (Apple spirit), m3 '
              '(Material tokens), curve (and why curves do not belong on '
              'close)'),
          ('Build your own Motion: close 2000ms + bounce 0.5 + kick 5 - '
              'then close a dialog'),
          ('Click the scrim or press Esc mid-flight: retarget with velocity '
              'carry-over; switching profiles mid-flight is live too'),
          ('Resize the window with the sheet open: the target is recomputed '
              'every frame'),
          ('Stress mode: crank the piece count and watch the FPS meter '
              'while necks form and rip across the whole canvas'),
          ('The shell itself runs on the engine: selectors are liquid goo, '
              'toggles and buttons are springs, panel swaps ride a '
              'MorphController'),
        ])
          Padding(
            padding: const .only(bottom: 8),
            child: Row(
              crossAxisAlignment: .start,
              children: <Widget>[
                Padding(
                  padding: const .only(top: 4),
                  child: Icon(
                    Icons.circle,
                    size: 5,
                    color: scheme.primary.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(note, style: const TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _familyPanel(
    BuildContext context,
    ColorScheme scheme,
    LabSettings lab,
  ) {
    final _PlaygroundState shell = this.shell;
    return <Widget>[
      if (lab.family == .cupertino)
        GooSelector(
          labels: <String>[
            for (final MorphMotion s in MorphMotion.values) s.name,
          ],
          index: lab.preset == null
              ? null
              : MorphMotion.values.indexOf(lab.preset!),
          onSelect: (int i) =>
              shell._update(() => lab.adoptPreset(MorphMotion.values[i])),
        ),
      if (lab.family == .cupertino) ...<Widget>[
        _LabSlider(
          label: 'open',
          value: lab.openMs,
          min: 150,
          max: 4000,
          format: (double v) => '${v.round()}ms',
          onChanged: (double v) => shell._update(() {
            lab
              ..preset = null
              ..openMs = v;
          }),
        ),
        _LabSlider(
          label: 'close',
          value: lab.closeMs,
          min: 150,
          max: 4000,
          format: (double v) => '${v.round()}ms',
          onChanged: (double v) => shell._update(() {
            lab
              ..preset = null
              ..closeMs = v;
          }),
        ),
        _LabSlider(
          label: 'bounce',
          value: lab.closeBounce,
          min: 0,
          max: 0.6,
          format: (double v) => v.toStringAsFixed(2),
          onChanged: (double v) => shell._update(() {
            lab
              ..preset = null
              ..closeBounce = v;
          }),
        ),
        _LabSlider(
          label: 'kick',
          value: lab.closeKick,
          min: 0,
          max: 6,
          format: (double v) => '-${v.toStringAsFixed(1)}',
          onChanged: (double v) => shell._update(() {
            lab
              ..preset = null
              ..closeKick = v;
          }),
        ),
        Text(
          'open is critically damped (CupertinoMotion.smooth), close has '
          'bounce. The sliders build a custom profile; kick injects close '
          'velocity from rest, scaled by flight distance.',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
      if (lab.family == .material) ...<Widget>[
        _LabDropdown(
          label: 'token',
          value: lab.materialIndex,
          options: <String>[
            for (final (String name, _) in LabSettings.materialTokens) name,
          ],
          onChanged: (int v) => shell._update(() => lab.materialIndex = v),
        ),
        _LabSlider(
          label: 'kick',
          value: lab.closeKick,
          min: 0,
          max: 6,
          format: (double v) => '-${v.toStringAsFixed(1)}',
          onChanged: (double v) => shell._update(() => lab.closeKick = v),
        ),
        Text(
          'Expressive Material 3 spatial tokens from motor: one Motion '
          'in both directions, each token brings its own bounce.',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
      if (lab.family == .curve) ...<Widget>[
        _LabDropdown(
          label: 'open',
          value: lab.openCurveIndex,
          options: <String>[
            for (final (String name, _) in LabSettings.curveOptions) name,
          ],
          onChanged: (int v) => shell._update(() => lab.openCurveIndex = v),
        ),
        _LabDropdown(
          label: 'close',
          value: lab.closeCurveIndex,
          options: <String>[
            for (final (String name, _) in LabSettings.curveOptions) name,
          ],
          onChanged: (int v) => shell._update(() => lab.closeCurveIndex = v),
        ),
        _LabSlider(
          label: 'open',
          value: lab.openMs,
          min: 150,
          max: 4000,
          format: (double v) => '${v.round()}ms',
          onChanged: (double v) => shell._update(() => lab.openMs = v),
        ),
        _LabSlider(
          label: 'close',
          value: lab.closeMs,
          min: 150,
          max: 4000,
          format: (double v) => '${v.round()}ms',
          onChanged: (double v) => shell._update(() => lab.closeMs = v),
        ),
        Text(
          'CurvedMotion: timing curves instead of physics. Interruption '
          'stays continuous (retarget from the current value), but the '
          'curve never goes below zero - the landing bump will not play. '
          'A live demo of the closeMotion contract.',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    ];
  }
}

class _SandboxPanel extends StatelessWidget {
  const _SandboxPanel({required this.shell, required this.scheme});

  final _PlaygroundState shell;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final SandboxController sandbox = shell.sandbox;
    final SandboxPiece? selected = sandbox.selected;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        _SectionHeader('SANDBOX', scheme),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            for (final (SandboxShape kind, IconData icon)
                in const <(SandboxShape, IconData)>[
                  (.box, Icons.crop_16_9_rounded),
                  (.stadium, Icons.crop_7_5_rounded),
                  (.circle, Icons.circle_outlined),
                ]) ...<Widget>[
              Expanded(
                child: SpringButton(
                  onPressed: () => sandbox.addPiece(kind),
                  child: Container(
                    padding: const .symmetric(vertical: 8),
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: scheme.secondaryContainer.withValues(alpha: 0.55),
                    ),
                    child: Icon(icon, size: 18),
                  ),
                ),
              ),
              if (kind != .circle) const SizedBox(width: 6),
            ],
          ],
        ),
        if (selected != null) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'piece ${selected.id} - ${selected.kind.name}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              SpringButton(
                onPressed: sandbox.armLink,
                child: Tooltip(
                  message: sandbox.linkArming
                      ? 'tap a second piece'
                      : 'link with a bridge',
                  child: Padding(
                    padding: const .all(6),
                    child: Icon(
                      Icons.link_rounded,
                      size: 18,
                      color: sandbox.linkArming ? scheme.primary : null,
                    ),
                  ),
                ),
              ),
              SpringButton(
                onPressed: shell.sandbox.pieces.length > 1
                    ? sandbox.removeSelected
                    : null,
                child: const Tooltip(
                  message: 'delete',
                  child: Padding(
                    padding: .all(6),
                    child: Icon(Icons.delete_outline_rounded, size: 18),
                  ),
                ),
              ),
            ],
          ),
          if (selected.kind == .circle)
            _LabSlider(
              label: 'size',
              value: selected.rect.width,
              min: 36,
              max: 200,
              format: (double v) => '${v.round()}px',
              onChanged: (double v) => sandbox.resizeSelected(width: v),
            )
          else ...<Widget>[
            _LabSlider(
              label: 'width',
              value: selected.rect.width,
              min: 36,
              max: 360,
              format: (double v) => '${v.round()}px',
              onChanged: (double v) => sandbox.resizeSelected(width: v),
            ),
            _LabSlider(
              label: 'height',
              value: selected.rect.height,
              min: 36,
              max: 280,
              format: (double v) => '${v.round()}px',
              onChanged: (double v) => sandbox.resizeSelected(height: v),
            ),
          ],
          if (selected.kind == .box)
            _LabSlider(
              label: 'radius',
              value: selected.radius,
              min: 0,
              max: 60,
              format: (double v) => '${v.round()}px',
              onChanged: (double v) => sandbox.resizeSelected(radius: v),
            ),
        ],
        if (sandbox.links.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final SandboxLink link in sandbox.links)
                InputChip(
                  visualDensity: .compact,
                  labelStyle: const TextStyle(fontSize: 11),
                  label: Text('${link.a}-${link.b}'),
                  onDeleted: () => sandbox.removeLink(link),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Tap to select, drag to move, double-tap for a morph flight '
          '(dialogs and a sheet by piece id). Click empty space to deselect.',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        const Divider(height: 28),

        _SectionHeader('KEYFRAMES', scheme),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            for (final String slot in const <String>['A', 'B']) ...<Widget>[
              Expanded(
                child: LabActionButton(
                  label: 'set $slot',
                  filled: false,
                  onPressed: () => sandbox.setKey(slot),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: LabActionButton(
                  label: slot,
                  onPressed: () => sandbox.playKey(slot, shell._sandboxMotion),
                ),
              ),
              if (slot == 'A') const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Scene snapshots. Playback is a spring morph of all pieces and '
          'the blend from the CURRENT state on the profile openMotion: '
          'press mid-flight, drag pieces during the morph.',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        const Divider(height: 28),

        _SectionHeader('LIQUID', scheme),
        const SizedBox(height: 8),
        GooSelector(
          labels: const <String>['geometric', 'goo'],
          index: switch (sandbox.mode) {
            null => null,
            .geometric => 0,
            .goo => 1,
          },
          onSelect: (int i) => sandbox.applyMode(i == 0 ? .geometric : .goo),
        ),
        _LabSlider(
          label: 'blend',
          value: sandbox.blend,
          min: 0,
          max: 80,
          format: (double v) => v.round().toString(),
          onChanged: sandbox.setBlend,
        ),
        _LabSlider(
          label: 'detail',
          value: sandbox.cell,
          min: 3,
          max: 14,
          format: (double v) => '${v.round()}px',
          onChanged: sandbox.setDetail,
        ),
        Text(
          'One skin for all pieces: SDF smooth-union + marching squares. '
          'blend is the fusion width (geometric joint -> gooey neck), '
          'detail is the outline grid step.',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.scheme);

  final String title;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 2,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

class _LabSlider extends StatelessWidget {
  const _LabSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            format(value),
            textAlign: .right,
            style: const TextStyle(
              fontSize: 11,
              fontFeatures: <FontFeature>[.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _LabDropdown extends StatelessWidget {
  const _LabDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<String> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const .symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              isDense: true,
              style: const TextStyle(fontSize: 12),
              items: <DropdownMenuItem<int>>[
                for (int i = 0; i < options.length; i++)
                  DropdownMenuItem<int>(
                    value: i,
                    child: Text(
                      options[i],
                      style: const TextStyle(fontSize: 12),
                      overflow: .ellipsis,
                    ),
                  ),
              ],
              onChanged: (int? v) {
                if (v != null) {
                  onChanged(v);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CanvasBackground extends StatelessWidget {
  const _CanvasBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.2, -0.6),
          radius: 1.4,
          colors: <Color>[Color(0xFF1D1830), Color(0xFF12101A)],
        ),
      ),
    );
  }
}
