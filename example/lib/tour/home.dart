import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:morph/morph.dart';

import 'package:morph_example/tour/lessons/chips_example.dart';
import 'package:morph_example/tour/lessons/goo_dock_example.dart';
import 'package:morph_example/tour/lessons/player_example.dart';
import 'package:morph_example/tour/lessons/route_example.dart';
import 'package:morph_example/playground/playground.dart';
import 'package:morph_example/tour/lesson.dart';
import 'package:morph_example/tour/lessons/basics_lessons.dart';
import 'package:morph_example/tour/lessons/menu_lesson.dart';
import 'package:morph_example/tour/lessons/toolbar_lesson.dart';

/// The tour home: a grid of chapters. The navigation IS the thesis -
/// every card morphs into its page as a real route (container
/// transform), and the back gesture plays the close flight home.
class TourHome extends StatelessWidget {
  /// Creates the home grid.
  const TourHome({super.key});

  static const MorphMotion _speed = .normal;

  /// The chapters, in reading order; the last one is the Playground.
  static final List<Lesson> lessons = <Lesson>[
    Lesson(
      id: 'lesson-identity',
      number: '01',
      icon: Icons.crop_free_rounded,
      title: 'Identity',
      tagline: 'A button becomes its dialog - one tag, one call.',
      when:
          'The user must never lose track of where a surface came '
          'from: compose buttons, editors, any control that opens '
          'its own workspace.',
      avoid:
          'The destination has no visual origin (a push from a '
          'list header, a global alert) - an honest fade or slide '
          'reads better than a fake source.',
      demo: (BuildContext context) => const IdentityLesson(motion: _speed),
    ),
    Lesson(
      id: 'lesson-retarget',
      number: '02',
      icon: Icons.bolt_rounded,
      title: 'Retargeting',
      tagline: 'Interrupt anything mid-flight; velocity carries over.',
      when:
          'Always - this is not a feature but the contract. Every '
          'tap during an animation retargets from the current value '
          'and velocity.',
      avoid:
          'Never: if an interaction cannot be interrupted, the '
          'model is wrong, not the user.',
      demo: (BuildContext context) => const RetargetLesson(motion: _speed),
    ),
    Lesson(
      id: 'lesson-landing',
      number: '03',
      icon: Icons.sports_gymnastics_rounded,
      title: 'Landing',
      tagline: 'Squash and recoil from the spring undershoot.',
      when:
          'Closing reads as an arrival: the surface has weight, the '
          'button absorbs the impact along the flight axis.',
      avoid:
          'Timing curves drive the close - a curve never crosses '
          'zero, so there is no undershoot to land with (the '
          'closeMotion contract).',
      demo: (BuildContext context) => const LandingLesson(motion: _speed),
    ),
    Lesson(
      id: 'lesson-menu',
      number: '04',
      icon: Icons.tune_rounded,
      title: 'Button to menu',
      tagline: 'The pill expands into its own popover.',
      when:
          'Contextual options belong to a control: the surface of '
          'the button IS the menu, anchored where it stands.',
      avoid:
          'Global commands with no owner - a command palette or an '
          'app menu should not pretend to grow out of a button.',
      demo: (BuildContext context) => const MenuLesson(motion: _speed),
    ),
    Lesson(
      id: 'lesson-toolbar',
      number: '05',
      icon: Icons.horizontal_rule_rounded,
      title: 'Toolbar merge',
      tagline: 'Actions fuse into one pill while you scroll.',
      when:
          'Context shifts attention: while the user reads, controls '
          'quiet down into one mass and split back on demand.',
      avoid:
          'The controls are the primary task - merging them away '
          'from under the pointer is hostile, not calm.',
      demo: (BuildContext context) => const ToolbarLesson(motion: _speed),
    ),
    Lesson(
      id: 'lesson-player',
      number: '06',
      icon: Icons.music_note_rounded,
      title: 'Shared elements and drag',
      tagline: 'The cover flies; the whole card follows the finger.',
      when:
          'Content persists across the morph (artwork, avatars) and '
          'the open surface should feel like a physical card in hand.',
      avoid:
          'Everything crossfades anyway - a shared element that '
          'does not visibly travel is dead weight.',
      demo: (BuildContext context) => const PlayerExample(motion: _speed),
    ),
    Lesson(
      id: 'lesson-dock',
      number: '07',
      icon: Icons.water_drop_rounded,
      title: 'Liquid selection',
      tagline: 'A dock whose selection is a blob of shared mass.',
      when:
          'Selection among siblings that share one surface: tab '
          'bars, docks - the blob IS the selection, mass never lies.',
      avoid:
          'Settings and forms: a segmented control is a tool, not '
          'a creature. Fusion there is decoration.',
      demo: (BuildContext context) => const GooDockExample(motion: _speed),
    ),
    Lesson(
      id: 'lesson-chips',
      number: '08',
      icon: Icons.grain_rounded,
      title: 'Liquid layout',
      tagline: 'Layout computes slots; springs and mass do the rest.',
      when:
          'Items are born and die inside a living row: droplets '
          'inflate at their slot, neighbors pour into vacated space, '
          'edits ripple as a stiffness wave.',
      avoid:
          'Static lists - liquid choreography on content that '
          'never changes is noise.',
      demo: (BuildContext context) => const ChipsExample(motion: _speed),
    ),
    Lesson(
      id: 'lesson-route',
      number: '09',
      icon: Icons.route_rounded,
      title: 'A real route',
      tagline: 'The destination lives in the Navigator; state flies.',
      when:
          'The destination is a PAGE: it pushes further pages, '
          'answers the back gesture, survives as history. The second '
          'latch hands the live subtree to the route.',
      avoid:
          'A plain dialog that nothing stacks upon - the overlay '
          'flight is lighter and needs no Navigator.',
      demo: (BuildContext context) => const RouteExample(motion: _speed),
    ),
    Lesson(
      id: 'lesson-playground',
      number: '10',
      icon: Icons.science_rounded,
      title: 'Playground',
      tagline: 'The sandbox: pieces, keyframes, stress, all the knobs.',
      when:
          'Tuning taste: glacial is the magnifier, the HUD shows '
          'the spring, stress mode shows the worst frame.',
      avoid:
          'Shipping the defaults untouched - motion is a product '
          'decision, and these knobs are how it gets made.',
      demo: (BuildContext context) => const Playground(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.2, -0.6),
            radius: 1.4,
            colors: <Color>[Color(0xFF1D1830), Color(0xFF12101A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              Padding(
                padding: const .fromLTRB(28, 26, 28, 0),
                child: Column(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    const Text(
                      'Morph',
                      style: TextStyle(fontSize: 30, fontWeight: .w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hero for overlays, on springs. Ten chapters; every '
                      'card below opens AS a morph route - the navigation '
                      'is the first demo.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (kIsWeb) ...<Widget>[
                      const SizedBox(height: 10),
                      const _WebPerfNote(),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const .fromLTRB(24, 18, 24, 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    mainAxisExtent: 148,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: lessons.length,
                  itemBuilder: (BuildContext context, int index) =>
                      LessonCard(lesson: lessons[index], motion: _speed),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The web-only note under the header: the browser build is for
/// getting a feel, not for judging performance - a native release
/// build runs the same scenes far smoother.
class _WebPerfNote extends StatelessWidget {
  const _WebPerfNote();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Padding(
        padding: const .symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: .min,
          children: <Widget>[
            Icon(Icons.speed_rounded, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Web build: judge the motion here, not the frame rate - '
                'a native release build runs far smoother.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
