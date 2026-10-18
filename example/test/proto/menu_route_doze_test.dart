import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/motion.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/menu_content.dart';
import 'package:morph/src/widgets/menu_entries.dart';
import 'package:morph/src/widgets/menu_layout.dart';
import 'package:morph_example/proto/menu_route_probe.dart';

const _button = Rect.fromLTWH(177, 126, 48, 48);
const _bounds = Size(402, 874);

final _entries = <MorphMenuEntry>[
  const MorphMenuItem(title: 'Copy', icon: Icon(IconData(1))),
  const MorphMenuItem(title: 'Share', icon: Icon(IconData(2))),
  const MorphSubmenu(
    title: 'More',
    icon: Icon(IconData(3)),
    children: [
      MorphMenuItem(title: 'Sub one', icon: Icon(IconData(11))),
      MorphMenuItem(title: 'Sub two', icon: Icon(IconData(12))),
    ],
  ),
  const MorphMenuItem(title: 'Delete', icon: Icon(IconData(4))),
];

Rect _row(MorphMenuLayout layout, String title) {
  for (final element in layout.elements) {
    final name = switch (element.entry) {
      MorphMenuItem(:final title) => title,
      MorphSubmenu(:final title) => title,
      _ => element.title,
    };
    if (name == title) return element.rect;
  }
  throw StateError('no $title');
}

typedef _Stamped = ({ProbeMenuSample sample, Duration stamp, bool inFrame});

class _Harness {
  final nav = GlobalKey<NavigatorState>();
  final source = GlobalKey<ProbeMenuSourceState>();
  final samples = <_Stamped>[];
  final models = <MorphMenuMotion>[];

  Widget app(WidgetTester tester) => WidgetsApp(
    color: const Color(0xFFFFFFFF),
    navigatorKey: nav,
    onGenerateRoute: (_) => PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => Focus(
        autofocus: true,
        child: ProbeMenuSource(
          key: source,
          button: _button,
          pointerInput: true,
          now: () => Duration(
            microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
          ),
          onSample: (sample) {
            final scheduler = SchedulerBinding.instance;
            final inFrame =
                scheduler.schedulerPhase == SchedulerPhase.transientCallbacks;
            samples.add((
              sample: sample,
              stamp: inFrame
                  ? scheduler.currentSystemFrameTimeStamp
                  : Duration(
                      microseconds: tester.binding.clock
                          .now()
                          .microsecondsSinceEpoch,
                    ),
              inFrame: inFrame,
            ));
          },
          createMotion: () {
            final content = MorphMenuContent(
              onChanged: ({required bool animate}) {},
            );
            content.entries = _entries;
            final model = MorphMenuMotion(
              button: _button,
              layout: content.root,
              bounds: _bounds,
              padding: const EdgeInsets.only(top: 62, bottom: 34),
              sourceHeight: 64,
              sourceRadius: 22,
            );
            morphConnectMenu(model, content);
            models.add(model);
            return model;
          },
          menuBuilder: (_) => const SizedBox.expand(),
        ),
      ),
    ),
  );

  List<_Stamped> get frames =>
      samples.where((s) => s.sample.kind == .frame).toList();

  _Stamped lastFrameBefore(_Stamped event) {
    final index = samples.indexOf(event);
    return samples.sublist(0, index).lastWhere((s) => s.sample.kind == .frame);
  }
}

double _seconds(Duration duration) => duration.inMicroseconds / 1e6;

void _expectWallTime(_Stamped previous, _Stamped next, String reason) {
  final expected =
      previous.sample.time +
      _seconds(next.stamp - previous.stamp) / timeDilation;
  expect(next.sample.time, closeTo(expected, 1e-6), reason: reason);
}

void main() {
  for (final step in [
    const Duration(microseconds: 16667),
    const Duration(microseconds: 8333),
  ]) {
    for (final dilation in [1.0, 5.0]) {
      for (final ending in ['escape', 'cover']) {
        final rate = (1e6 / step.inMicroseconds).round();
        testWidgets('$ending while a resting finger dozes the route: $rate Hz, '
            '${dilation}x', (tester) async {
          final harness = _Harness();
          await tester.pumpWidget(harness.app(tester));
          final original = timeDilation;
          timeDilation = dilation;
          final frame = step * dilation;
          try {
            await tester.tapAt(_button.center);
            ProbeMenuRoute? route;
            for (var i = 0; i < 400; i++) {
              await tester.pump(frame);
              route = harness.source.currentState!.activeRoute;
              if (route != null && harness.models.last.isSettled) break;
            }
            expect(route, isNotNull);
            final model = harness.models.last;
            expect(model.isSettled, isTrue);

            final more =
                model.menuRect.topLeft + _row(model.layout, 'More').center;
            final finger = await tester.startGesture(more);
            var idle = 0;
            for (var i = 0; i < 400 && idle < 4; i++) {
              final before = route!.motionFrames;
              await tester.pump(frame);
              idle = route.motionFrames == before ? idle + 1 : 0;
            }
            expect(
              idle,
              4,
              reason: 'a finger resting on a submenu row lets the route doze',
            );
            expect(model.cards, hasLength(1), reason: 'the card is due later');

            final commandAt = harness.samples.length;
            if (ending == 'escape') {
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            } else {
              harness.nav.currentState!.push(
                PageRouteBuilder<void>(
                  opaque: false,
                  transitionDuration: Duration.zero,
                  pageBuilder: (_, _, _) => const SizedBox.expand(),
                ),
              );
            }
            final ProbeMenuSampleKind expected = ending == 'escape'
                ? .close
                : .cancelInput;
            final command = harness.samples
                .sublist(commandAt)
                .firstWhere((s) => s.sample.kind == expected);
            expect(command.inFrame, isFalse);
            _expectWallTime(
              harness.lastFrameBefore(command),
              command,
              'the command lands on the dozed clock, not the last frame',
            );
            await finger.up();

            if (ending == 'cover') {
              await tester.pump(frame);
              harness.nav.currentState!.pop();
              await tester.pump(frame);
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            }
            final closing = harness.samples.length;
            for (var i = 0; i < 1200; i++) {
              await tester.pump(frame);
              if (harness.source.currentState!.motionSettled &&
                  route!.disposed) {
                break;
              }
            }
            expect(route!.disposed, isTrue);
            expect(route.handBack, isNotNull);
            final tail = harness.samples
                .sublist(closing)
                .where((s) => s.sample.kind == .frame)
                .toList();
            expect(tail.length, greaterThan(10));
            for (var i = 1; i < tail.length; i++) {
              _expectWallTime(
                tail[i - 1],
                tail[i],
                'closing frame $i follows the frame clock',
              );
            }
          } finally {
            timeDilation = original;
          }
        });
      }
    }
  }
}

// ignore_for_file: implementation_imports, invalid_use_of_internal_member
