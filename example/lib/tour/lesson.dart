import 'package:flutter/material.dart';

import 'package:morph/widgets.dart';

/// One chapter of the tour: a single mechanism, a live demo, and the
/// taste notes - when the morph earns its place and when it does not.
/// The Widget-of-the-Week format: short, focused, interactive.
class Lesson {
  /// Creates a chapter description.
  const Lesson({
    required this.id,
    required this.number,
    required this.icon,
    required this.title,
    required this.tagline,
    required this.when,
    required this.avoid,
    required this.demo,
  });

  /// The MorphTag id of the card AND the route identity.
  final String id;

  /// Two-digit chapter number shown on the card.
  final String number;

  /// The card icon.
  final IconData icon;

  /// Chapter title; shared between card and page header.
  final String title;

  /// One line on the card.
  final String tagline;

  /// "Use it when": the honest situations.
  final String when;

  /// "Skip it when": the taste boundary.
  final String avoid;

  /// Builds the live demo of the chapter page.
  final WidgetBuilder demo;
}

/// Surface model of a chapter card.
const MorphSurfaceSpec lessonCardSpec = MorphSurfaceSpec(
  shape: RoundedRectangleBorder(borderRadius: .all(.circular(22))),
  color: Color(0xFF221D33),
  elevation: 3,
);

/// Surface model of an open chapter page.
const MorphSurfaceSpec lessonPageSpec = MorphSurfaceSpec(
  shape: RoundedRectangleBorder(),
  color: Color(0xFF15121F),
  elevation: 24,
);

/// Opens a chapter as a morph route: the card's surface becomes the
/// fullscreen page (container transform), the page lives in the
/// Navigator, and the back gesture plays the close flight home.
Future<void> openLesson(
  BuildContext context,
  Lesson lesson, {
  MorphMotion motion = .normal,
}) {
  return showMorphRoute<void>(
    context,
    from: lesson.id,
    motion: motion,
    semanticLabel: lesson.title,
    target: MorphTargetSpec.fullscreen(surface: lessonPageSpec),
    builder: (BuildContext context, MorphFlight flight) =>
        LessonPage(lesson: lesson, flight: flight),
  );
}

/// The card on the home grid. Tapping it is the library's own thesis:
/// the card BECOMES the lesson page - a container transform into a
/// real Navigator route, with live state and predictive back.
class LessonCard extends StatelessWidget {
  /// Creates the card for [lesson].
  const LessonCard({super.key, required this.lesson, required this.motion});

  /// The chapter this card opens.
  final Lesson lesson;

  /// Motion profile of the card flight.
  final MorphMotion motion;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return MorphTag(
      id: lesson.id,
      spec: lessonCardSpec,
      child: MorphSurface(
        onTap: (BuildContext context) =>
            openLesson(context, lesson, motion: motion),
        child: Padding(
          padding: const .all(16),
          child: Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(lesson.icon, size: 20, color: scheme.primary),
                  const Spacer(),
                  Text(
                    lesson.number,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: .w700,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // The title TRAVELS into the page header: both ends
              // mark the same id, the flight lerps the rects and
              // scales the glyphs between the two type sizes.
              MorphSharedElement(
                id: '${lesson.id}-title',
                child: Text(
                  lesson.title,
                  style: const TextStyle(fontSize: 14.5, fontWeight: .w700),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                lesson.tagline,
                maxLines: 2,
                overflow: .ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The opened chapter: header with a back that plays the close flight,
/// the taste notes, and the live demo. Content unfolds in a MorphReveal
/// cascade riding the SAME spring as the container.
class LessonPage extends StatelessWidget {
  /// Creates the page for [lesson].
  const LessonPage({super.key, required this.lesson, required this.flight});

  /// The chapter being shown.
  final Lesson lesson;

  /// The route flight carrying this page.
  final MorphFlight flight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const .fromLTRB(20, 14, 20, 12),
        child: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            Row(
              children: <Widget>[
                SpringButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const .all(8),
                    decoration: ShapeDecoration(
                      shape: const CircleBorder(),
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    child: const Icon(Icons.arrow_back_rounded, size: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  lesson.number,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: .w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: MorphSharedElement(
                      id: '${lesson.id}-title',
                      child: Text(
                        lesson.title,
                        style: const TextStyle(fontSize: 17, fontWeight: .w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            MorphReveal(
              from: 0.35,
              to: 0.8,
              child: Row(
                crossAxisAlignment: .start,
                children: <Widget>[
                  Expanded(
                    child: _TasteNote(
                      label: 'USE IT WHEN',
                      text: lesson.when,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TasteNote(
                      label: 'SKIP IT WHEN',
                      text: lesson.avoid,
                      color: scheme.tertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: MorphReveal(
                from: 0.45,
                to: 1,
                child: lesson.demo(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TasteNote extends StatelessWidget {
  const _TasteNote({
    required this.label,
    required this.text,
    required this.color,
  });

  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const .all(12),
      decoration: BoxDecoration(
        borderRadius: .circular(14),
        color: Colors.white.withValues(alpha: 0.035),
      ),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: .w700,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
