import 'package:flutter/material.dart';

import 'package:morph/morph.dart';

import 'package:morph_example/tour/lessons/dialog_contents.dart';
import 'package:morph_example/tour/lessons/comet_example.dart';
import 'package:morph_example/ui/morph_surface.dart';

/// 01 - Identity: one MorphTag, one showMorph call. The button becomes
/// the dialog; closing lands back into the button with the full-wave
/// bump. This is the entire basic API surface.
class IdentityLesson extends StatelessWidget {
  /// Creates the chapter demo.
  const IdentityLesson({super.key, required this.motion});

  /// Motion profile of the demo flights.
  final MorphMotion motion;

  static const MorphSurfaceSpec _pill = MorphSurfaceSpec(
    shape: StadiumBorder(),
    color: Color(0xFF7C5CFF),
    elevation: 4,
  );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: MorphTag(
        id: 'identity-compose',
        spec: _pill,
        // The MorphSurface recipe renders the surface FROM the spec and
        // hands onTap a context under the tag - from: is inferred.
        child: MorphSurface(
          onTap: (BuildContext context) => showMorphDialog(
            context,
            width: 480,
            height: 440,
            motion: motion,
            semanticLabel: 'New message',
            builder: (BuildContext context, MorphFlight flight) =>
                ComposeDialogContent(flight: flight),
          ),
          child: const Padding(
            padding: .symmetric(horizontal: 24, vertical: 14),
            child: Row(
              mainAxisSize: .min,
              children: <Widget>[
                Icon(Icons.edit_rounded, size: 18),
                SizedBox(width: 8),
                Text(
                  'New message',
                  style: TextStyle(fontSize: 14, fontWeight: .w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 02 - Retargeting: the comet chain chases the pointer (every move is
/// a retarget from the current value and velocity), and the torture
/// button interrupts a flight mid-air over and over - the interruption
/// contract, visible.
class RetargetLesson extends StatefulWidget {
  /// Creates the chapter demo.
  const RetargetLesson({super.key, required this.motion});

  /// Motion profile of the demo flights.
  final MorphMotion motion;

  @override
  State<RetargetLesson> createState() => _RetargetLessonState();
}

class _RetargetLessonState extends State<RetargetLesson> {
  bool _running = false;

  Future<void> _torture(BuildContext context) async {
    if (_running) {
      return;
    }
    setState(() => _running = true);
    try {
      for (final (int hold, int gap) in const <(int, int)>[
        (240, 180),
        (300, 140),
        (900, 0),
      ]) {
        if (!context.mounted) {
          return;
        }
        final MorphFlight flight = showMorphDialog(
          context,
          from: 'retarget-button',
          width: 420,
          height: 420,
          motion: widget.motion,
          builder: (BuildContext context, MorphFlight flight) =>
              PlayerDialogContent(flight: flight),
        );
        await Future<void>.delayed(Duration(milliseconds: hold));
        flight.close();
        await Future<void>.delayed(Duration(milliseconds: gap));
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(child: CometExample()),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const .only(bottom: 10),
            child: MorphTag(
              id: 'retarget-button',
              spec: const MorphSurfaceSpec(
                shape: StadiumBorder(),
                color: Color(0xFF2A2440),
                elevation: 3,
              ),
              child: MorphSurface(
                onTap: _running ? null : _torture,
                child: Padding(
                  padding: const .symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisSize: .min,
                    children: <Widget>[
                      Icon(
                        Icons.bolt_rounded,
                        size: 17,
                        color: _running
                            ? Colors.white38
                            : const Color(0xFFFFC24B),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _running ? 'torturing...' : 'Interruption torture',
                        style: const TextStyle(fontSize: 13, fontWeight: .w600),
                      ),
                    ],
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

/// 03 - Landing: the same flight with the bump knobs in hand. Squash
/// rides the spring's undershoot along the impact axis; recoil kicks
/// the button off its spot. Both are zero on curves - by contract.
class LandingLesson extends StatefulWidget {
  /// Creates the chapter demo.
  const LandingLesson({super.key, required this.motion});

  /// Motion profile of the demo flights.
  final MorphMotion motion;

  @override
  State<LandingLesson> createState() => _LandingLessonState();
}

class _LandingLessonState extends State<LandingLesson> {
  double _bumpScale = 0.8;
  double _bumpRecoil = 180;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: MorphTag(
              id: 'landing-note',
              spec: const MorphSurfaceSpec(
                shape: RoundedRectangleBorder(
                  borderRadius: .all(.circular(18)),
                ),
                color: Color(0xFF2A2440),
                elevation: 3,
              ),
              bumpScale: _bumpScale,
              bumpRecoil: _bumpRecoil,
              child: MorphSurface(
                onTap: (BuildContext context) => showMorphSheet(
                  context,
                  heightFactor: 0.55,
                  motion: widget.motion,
                  semanticLabel: 'Share',
                  builder: (BuildContext context, MorphFlight flight) =>
                      ShareSheetContent(onClose: flight.close),
                ),
                child: const Padding(
                  padding: .symmetric(horizontal: 26, vertical: 16),
                  child: Text(
                    'Fly me, then watch the landing',
                    style: TextStyle(fontSize: 13.5, fontWeight: .w600),
                  ),
                ),
              ),
            ),
          ),
        ),
        _Knob(
          label: 'squash',
          value: _bumpScale,
          min: 0,
          max: 1.5,
          format: (double v) => v.toStringAsFixed(2),
          onChanged: (double v) => setState(() => _bumpScale = v),
        ),
        _Knob(
          label: 'recoil',
          value: _bumpRecoil,
          min: 0,
          max: 300,
          format: (double v) => '${v.round()}px',
          onChanged: (double v) => setState(() => _bumpRecoil = v),
        ),
        Text(
          'a glacial profile in the Playground is the magnifier for this',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob({
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
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
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              format(value),
              textAlign: .right,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
