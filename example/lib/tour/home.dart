import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';

import 'package:morph/widgets.dart';

import 'package:morph_example/playground/playground.dart';
import 'package:morph_example/tour/lesson.dart';
import 'package:morph_example/tour/lessons/bar_lesson.dart';
import 'package:morph_example/tour/lessons/chips_example.dart';
import 'package:morph_example/tour/lessons/goo_dock_example.dart';
import 'package:morph_example/tour/lessons/menu_lesson.dart';
import 'package:morph_example/tour/lessons/morph_scene.dart';
import 'package:morph_example/tour/lessons/page_scene.dart';
import 'package:morph_example/tour/lessons/toolbar_lesson.dart';

/// The tour home: chapters in sections, each card a question the scene
/// answers. The navigation IS the thesis - every card morphs into its
/// page as a real route (container transform), and the back gesture
/// plays the close flight home.
class TourHome extends StatelessWidget {
  /// Creates the home grid.
  const TourHome({super.key});

  static const MorphMotion _speed = .normal;

  /// The chapters grouped for the grid; every scene is an app mockup
  /// answering the question on its card.
  static final List<(String, List<Lesson>)> sections = <(String, List<Lesson>)>[
    (
      'THE FLIGHT',
      <Lesson>[
        Lesson(
          id: 'lesson-morph',
          number: '01',
          icon: Icons.crop_free_rounded,
          title: 'The morph',
          tagline: 'What happens between a button and its dialog?',
          demo: (BuildContext context) => const MorphScene(motion: _speed),
        ),
      ],
    ),
    (
      'CONTROLS',
      <Lesson>[
        Lesson(
          id: 'lesson-menu',
          number: '02',
          icon: Icons.tune_rounded,
          title: 'Button to menu',
          tagline: 'Where does a menu come from?',
          demo: (BuildContext context) => const MenuLesson(motion: _speed),
        ),
        Lesson(
          id: 'lesson-toolbar',
          number: '03',
          icon: Icons.horizontal_rule_rounded,
          title: 'Toolbar merge',
          tagline: 'Where do controls go while you read?',
          demo: (BuildContext context) => const ToolbarLesson(motion: _speed),
        ),
      ],
    ),
    (
      'PAGES',
      <Lesson>[
        Lesson(
          id: 'lesson-pages',
          number: '04',
          icon: Icons.music_note_rounded,
          title: 'Card to page',
          tagline: 'When is a surface a real page?',
          demo: (BuildContext context) => const PageScene(motion: _speed),
        ),
      ],
    ),
    (
      'LIQUID',
      <Lesson>[
        Lesson(
          id: 'lesson-dock',
          number: '05',
          icon: Icons.water_drop_rounded,
          title: 'Liquid selection',
          tagline: 'What if selection were mass?',
          demo: (BuildContext context) => const GooDockExample(),
        ),
        Lesson(
          id: 'lesson-bar',
          number: '06',
          icon: Icons.call_to_action_rounded,
          title: 'The bar',
          tagline: 'What if the whole bar were one body?',
          demo: (BuildContext context) => const BarLesson(),
        ),
        Lesson(
          id: 'lesson-chips',
          number: '07',
          icon: Icons.grain_rounded,
          title: 'Living layout',
          tagline: 'What if layout flowed?',
          demo: (BuildContext context) => const ChipsExample(motion: _speed),
        ),
      ],
    ),
    (
      'THE LAB',
      <Lesson>[
        Lesson(
          id: 'lesson-playground',
          number: '08',
          icon: Icons.science_rounded,
          title: 'Playground',
          tagline: 'The sandbox: pieces, keyframes, stress, all knobs.',
          demo: (BuildContext context) => const Playground(),
        ),
      ],
    ),
  ];

  /// The chapters flat, in reading order; the last one is the
  /// Playground (the autodemo opens it by position).
  static final List<Lesson> lessons = <Lesson>[
    for (final (String, List<Lesson>) section in sections) ...section.$2,
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
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const .fromLTRB(28, 26, 28, 6),
                  child: Column(
                    crossAxisAlignment: .start,
                    children: <Widget>[
                      const Text(
                        'Morph',
                        style: TextStyle(fontSize: 30, fontWeight: .w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Hero for overlays, on springs. Every card below is '
                        'a question - and opens AS a morph route, so the '
                        'navigation is the first demo.',
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
              ),
              for (final (String label, List<Lesson> group) in sections) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const .fromLTRB(28, 18, 28, 10),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.8,
                        fontWeight: .w700,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const .symmetric(horizontal: 24),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          mainAxisExtent: 148,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: group.length,
                    itemBuilder: (BuildContext context, int index) =>
                        LessonCard(lesson: group[index], motion: _speed),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
