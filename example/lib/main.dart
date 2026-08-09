import 'package:flutter/material.dart';
import 'package:morph/morph.dart';

import 'package:morph_example/flags.dart';
import 'package:morph_example/perf/release_bench.dart';
import 'package:morph_example/tour/home.dart';
import 'package:morph_example/tour/lesson.dart';

void main() {
  runApp(const MorphTourApp());
}

/// The tour: an introduction to the library where the app itself is
/// the first exhibit - chapters open as morph routes, controls answer
/// with springs, and the Playground chapter holds all the knobs.
class MorphTourApp extends StatelessWidget {
  /// Creates the app.
  const MorphTourApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: appReducedMotion,
      builder: (BuildContext context, bool reduced, Widget? child) {
        return MaterialApp(
          title: 'Morph',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: .dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF7C5CFF),
              brightness: .dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF12101A),
            // Touch feedback in this app is springs and mass, not ink:
            // a Material ripple on top of a spring press is a second
            // design language. Hover and focus stay - those are
            // pointer/a11y affordances, not decoration.
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          builder: (BuildContext context, Widget? child) {
            final MediaQueryData mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(disableAnimations: reduced),
              child: MorphScope(child: child!),
            );
          },
          home: const _TourEntry(),
        );
      },
    );
  }
}

class _TourEntry extends StatefulWidget {
  const _TourEntry();

  @override
  State<_TourEntry> createState() => _TourEntryState();
}

class _TourEntryState extends State<_TourEntry> {
  @override
  void initState() {
    super.initState();
    if (kBenchMode) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) async {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          await runReleaseBench(context);
        }
      });
      return;
    }
    if (kAutoDemo) {
      // The scripted gate: open the Playground chapter AS a morph
      // route (exercising the card flight and the second latch), then
      // its own autodemo sequence takes over.
      WidgetsBinding.instance.addPostFrameCallback((Duration _) async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) {
          return;
        }
        await openLesson(context, TourHome.lessons.last);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return const TourHome();
  }
}
