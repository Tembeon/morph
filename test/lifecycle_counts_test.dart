import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/widgets.dart';

/// Lifecycle passports of the controls: per frame of a programmatic
/// interaction, the main-thread work morph does, next to the same window
/// of the native control (lab captures on an iPhone 16 Pro, iOS 27.0.1;
/// notes private; the comparison lives in
/// tool/ios_reference/spec/lifecycle.md).
///
/// Each scene drives the interaction the native window drives (a selection
/// set by the parent, a value toggled, a presentation shown and dismissed)
/// and records, frame by frame until the motion settles:
///
/// - builds: element builds (first builds of mounting elements and
///   rebuilds), as `debugOnRebuildDirtyWidget` reports them;
/// - layouts: `performLayout` calls (a layout skipped because nothing
///   changed does not count);
/// - paints: render objects painted (a clean repaint boundary that is
///   only composited again does not count);
/// - `+Nm` / `-Nu`: elements mounted into / unmounted from the tree;
/// - `gN`: paints of glass render objects (the surfaces whose backdrop or
///   body is redrawn).
///
/// A frame prints as `builds/layouts/paints`, an idle frame as `0`, and a
/// run of K idle frames as `0xK`. Frames are 16 ms, the Pixel 6a's 60 Hz.
///
/// The scenes whose gap to native was closed are pinned in [_ceilings]:
/// the first frame's builds, the last frame with any work, and the median
/// builds, layouts and paints of the frames after the first. A change may lower them, never raise them. The
/// others are recorded only. `LIFECYCLE_LOG=true` prints every timeline;
/// `LIFECYCLE_OUT=<file>` writes them to a file; `LIFECYCLE_TOP=<n>` lists
/// n render object classes per step instead of 8, `LIFECYCLE_DUMP=true`
/// prints the classes painted in every frame, and
/// `LIFECYCLE_WHO=<step>:<frame>` prints every render object laid out or
/// painted in that frame with the widgets that made it.
void main() {
  final log = Platform.environment['LIFECYCLE_LOG'] == 'true';
  final out = Platform.environment['LIFECYCLE_OUT'];
  final report = <String>[];

  setUpAll(() => isLocalTest = true);
  tearDownAll(() {
    isLocalTest = false;
    if (out != null) File(out).writeAsStringSync('${report.join('\n')}\n');
  });

  for (final tier in const [MorphGlassTier.flat, MorphGlassTier.liquid]) {
    for (final scene in _scenes) {
      final name = '${scene.family}/${tier.name}';
      testWidgets('lifecycle counts: $name', (WidgetTester tester) async {
        tester.view.physicalSize = _screen * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final navigator = GlobalKey<NavigatorState>();
        final setup = scene.setup(_Env(navigator));
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            debugShowCheckedModeBanner: false,
            theme: ThemeData(platform: TargetPlatform.iOS),
            builder: (BuildContext context, Widget? child) =>
                MorphAdaptiveGlass(tier: tier, child: child!),
            home: setup.home,
          ),
        );
        await _settle(tester);
        final lines = <String>[];
        final recorder = _Recorder(tester);
        final over = <String>[];
        for (final step in setup.steps) {
          final result = await recorder.record(step);
          lines.add(result.describe(name));
          if (_ceilings['$name ${step.name}'] case final ceiling?) {
            over.addAll(result.over(ceiling));
          }
        }
        await setup.end?.call(tester);
        await _settle(tester);
        report.addAll(lines);
        if (log) debugPrint(lines.join('\n'));
        expect(over, isEmpty, reason: '$name rose above its ceilings');
      });
    }
  }
}

/// The pinned scenes, by `family/tier step`: the builds of the first
/// frame, the last frame with any work in ms, and the median builds,
/// layouts and paints of the frames after the first (lifecycle.md,
/// 2026-10-14).
const _ceilings = <String, _Ceiling>{
  'segmented/flat select-2': (
    first: 13,
    ms: 1296,
    builds: 0,
    layouts: 2,
    paints: 8,
  ),
  'segmented/flat select-3': (
    first: 13,
    ms: 1328,
    builds: 0,
    layouts: 2,
    paints: 8,
  ),
  'segmented/liquid select-2': (
    first: 13,
    ms: 1296,
    builds: 0,
    layouts: 2,
    paints: 9,
  ),
  'tabbar/flat select-1': (
    first: 41,
    ms: 1328,
    builds: 0,
    layouts: 2,
    paints: 17,
  ),
  'tabbar/flat select-0': (
    first: 41,
    ms: 1456,
    builds: 0,
    layouts: 2,
    paints: 17,
  ),
  'tabbar/liquid select-1': (
    first: 41,
    ms: 1328,
    builds: 0,
    layouts: 2,
    paints: 18,
  ),
  'tabbar/liquid select-0': (
    first: 41,
    ms: 1456,
    builds: 0,
    layouts: 2,
    paints: 18,
  ),
  'switch/flat set-on': (first: 7, ms: 944, builds: 0, layouts: 2, paints: 9),
  'switch/flat set-off': (first: 7, ms: 832, builds: 0, layouts: 2, paints: 9),
  'switch/liquid set-on': (first: 7, ms: 944, builds: 0, layouts: 2, paints: 9),
  'button/flat highlight-on': (
    first: 0,
    ms: 448,
    builds: 0,
    layouts: 0,
    paints: 16,
  ),
  'button/flat highlight-off': (
    first: 0,
    ms: 704,
    builds: 0,
    layouts: 0,
    paints: 16,
  ),
  'button/liquid highlight-on': (
    first: 0,
    ms: 448,
    builds: 0,
    layouts: 0,
    paints: 16,
  ),
  'navigation/flat push': (
    first: 248,
    ms: 960,
    builds: 2,
    layouts: 5,
    paints: 47,
  ),
  'navigation/flat pop': (
    first: 114,
    ms: 944,
    builds: 2,
    layouts: 5,
    paints: 49,
  ),
  'navigation/liquid push': (
    first: 248,
    ms: 960,
    builds: 2,
    layouts: 7,
    paints: 48,
  ),
  'navigation/liquid pop': (
    first: 137,
    ms: 944,
    builds: 2,
    layouts: 7,
    paints: 49,
  ),
  'sheet/flat detent-large': (
    first: 20,
    ms: 688,
    builds: 0,
    layouts: 19,
    paints: 31,
  ),
  'sheet/flat detent-medium': (
    first: 19,
    ms: 688,
    builds: 0,
    layouts: 19,
    paints: 27,
  ),
  'sheet/liquid detent-large': (
    first: 20,
    ms: 688,
    builds: 0,
    layouts: 24,
    paints: 35,
  ),
  'alert/flat dismiss': (first: 76, ms: 432, builds: 0, layouts: 0, paints: 18),
  'alert/flat action-sheet-dismiss': (
    first: 74,
    ms: 544,
    builds: 0,
    layouts: 0,
    paints: 11,
  ),
  'alert/liquid dismiss': (
    first: 76,
    ms: 432,
    builds: 0,
    layouts: 0,
    paints: 22,
  ),
  'menu/flat open-inline': (
    first: 60,
    ms: 928,
    builds: 0,
    layouts: 1,
    paints: 22,
  ),
  'menu/flat close-inline': (
    first: 0,
    ms: 960,
    builds: 0,
    layouts: 0,
    paints: 8,
  ),
  'menu/liquid open-inline': (
    first: 60,
    ms: 928,
    builds: 0,
    layouts: 6,
    paints: 29,
  ),
  'menu/liquid close-inline': (
    first: 0,
    ms: 960,
    builds: 0,
    layouts: 5,
    paints: 15,
  ),
};

typedef _Ceiling = ({int first, int ms, int builds, int layouts, int paints});

const _screen = Size(402, 874);
const _frame = Duration(milliseconds: 16);

/// The longest window of a step that records until it settles.
const _maxFrames = 200;

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  _frame,
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 20),
);

/// What a scene needs from the app around it.
class _Env {
  _Env(this.navigator);

  final GlobalKey<NavigatorState> navigator;

  /// A context under the app's navigator.
  BuildContext get context => navigator.currentState!.overlay!.context;
}

/// One programmatic interaction, recorded in its own window.
class _Step {
  const _Step(this.name, this.action, {this.frames});

  final String name;

  /// Starts the interaction; the first recorded frame is the one after it.
  final FutureOr<void> Function(WidgetTester tester) action;

  /// A fixed window in frames, for a motion that never settles; null
  /// records until no frame is scheduled.
  final int? frames;
}

class _Setup {
  const _Setup(this.home, this.steps, {this.end});

  final Widget home;
  final List<_Step> steps;

  /// Brings a scene that never settles to rest after the last step.
  final FutureOr<void> Function(WidgetTester tester)? end;
}

class _Scene {
  const _Scene(this.family, this.setup);

  /// The native family the scene mirrors.
  final String family;
  final _Setup Function(_Env env) setup;
}

class _Counts {
  int builds = 0;
  int layouts = 0;
  int paints = 0;
  int mounts = 0;
  int unmounts = 0;
  int glass = 0;

  bool get idle =>
      builds == 0 &&
      layouts == 0 &&
      paints == 0 &&
      mounts == 0 &&
      unmounts == 0 &&
      glass == 0;

  String get token {
    if (idle) return '0';
    final b = StringBuffer('$builds/$layouts/$paints');
    if (mounts > 0) b.write('+${mounts}m');
    if (unmounts > 0) b.write('-${unmounts}u');
    if (glass > 0) b.write(':g$glass');
    return b.toString();
  }
}

/// Counts the main-thread work of each frame through the framework's
/// debug hooks and an element-tree diff.
class _Recorder {
  _Recorder(this.tester);

  final WidgetTester tester;
  _Counts _now = _Counts();
  final Map<String, int> _builders = {};
  final Map<String, int> _layouts = {};
  final Map<String, int> _paints = {};
  Set<Element> _elements = {};
  final Map<String, int>? _dump =
      Platform.environment['LIFECYCLE_DUMP'] == 'true' ? {} : null;
  final String? _who = Platform.environment['LIFECYCLE_WHO'];
  final List<String> _laidOut = [];
  final List<RenderObject> _painted = [];

  static String _creator(RenderObject object) {
    final creator = object.debugCreator;
    if (creator is! DebugCreator) return '';
    final chain = <String>[creator.element.widget.runtimeType.toString()];
    creator.element.visitAncestorElements((Element e) {
      chain.add(e.widget.runtimeType.toString());
      return chain.length < 8;
    });
    return chain.join(' < ');
  }

  void _printWho(String step, int frame) {
    if (_who != '$step:$frame') return;
    final byName = <String, RenderObject>{};
    void visit(RenderObject o) {
      byName[describeIdentity(o)] = o;
      o.visitChildren(visit);
    }

    for (final view in tester.binding.renderViews) {
      visit(view);
    }
    for (final name in _laidOut) {
      final o = byName[name];
      debugPrint('layout $name ${o == null ? '' : _creator(o)}');
    }
    for (final o in _painted) {
      debugPrint('paint ${describeIdentity(o)} ${_creator(o)}');
    }
  }

  static void _bump(Map<String, int> map, String key) =>
      map[key] = (map[key] ?? 0) + 1;

  Set<Element> _tree() {
    final out = <Element>{};
    void visit(Element element) {
      out.add(element);
      element.visitChildren(visit);
    }

    final root = tester.binding.rootElement;
    if (root != null) visit(root);
    return out;
  }

  Future<_Result> record(_Step step) async {
    _elements = _tree();
    _now = _Counts();
    _builders.clear();
    _layouts.clear();
    _paints.clear();
    final print = debugPrint;
    debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
      _now.builds++;
      _bump(_builders, element.widget.runtimeType.toString());
    };
    debugOnProfilePaint = (RenderObject object) {
      if (object.isRepaintBoundary && !object.debugNeedsPaint) return;
      if (_dump != null) _bump(_dump, object.runtimeType.toString());
      if (_who != null) _painted.add(object);
      _now.paints++;
      final type = object.runtimeType.toString();
      if (type.contains('Glass')) _now.glass++;
      _bump(_paints, type);
    };
    debugPrintLayouts = true;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.startsWith('Laying out (')) {
        _now.layouts++;
        final start = message.indexOf(') ') + 2;
        final end = message.indexOf('#', start);
        if (_who != null) {
          _laidOut.add(message.substring(start).split(' ').first);
        }
        _bump(
          _layouts,
          message.substring(start, end < 0 ? message.length : end),
        );
        return;
      }
      print(message, wrapWidth: wrapWidth);
    };
    final frames = <_Counts>[];
    try {
      await step.action(tester);
      final cap = step.frames ?? _maxFrames;
      for (var i = 0; i < cap; i++) {
        await tester.pump(_frame);
        final now = _tree();
        _now.mounts = now.where((e) => !_elements.contains(e)).length;
        _now.unmounts = _elements.where((e) => !now.contains(e)).length;
        _elements = now;
        frames.add(_now);
        if (_dump != null) {
          debugPrint('frame ${frames.length - 1} ${step.name}: $_dump');
          _dump.clear();
        }
        _printWho(step.name, frames.length - 1);
        _laidOut.clear();
        _painted.clear();
        _now = _Counts();
        if (step.frames == null &&
            i >= 3 &&
            !tester.binding.hasScheduledFrame) {
          break;
        }
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
      debugOnProfilePaint = null;
      debugPrintLayouts = false;
      debugPrint = print;
    }
    return _Result(
      step.name,
      frames,
      settled: !tester.binding.hasScheduledFrame,
      builders: Map.of(_builders),
      layouts: Map.of(_layouts),
      paints: Map.of(_paints),
    );
  }
}

class _Result {
  _Result(
    this.name,
    this.frames, {
    required this.settled,
    required this.builders,
    required this.layouts,
    required this.paints,
  });

  final String name;
  final List<_Counts> frames;
  final bool settled;
  final Map<String, int> builders;
  final Map<String, int> layouts;
  final Map<String, int> paints;

  String _timeline() {
    final out = <String>[];
    var zeros = 0;
    void flush() {
      if (zeros == 1) out.add('0');
      if (zeros > 1) out.add('0x$zeros');
      zeros = 0;
    }

    for (final f in frames) {
      if (f.idle) {
        zeros++;
        continue;
      }
      flush();
      out.add(f.token);
    }
    flush();
    return out.join(' ');
  }

  static String _top(Map<String, int> map) {
    final entries = map.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in entries.take(
        int.parse(Platform.environment['LIFECYCLE_TOP'] ?? '8'),
      ))
        '${e.key} ${e.value}',
    ].join(', ');
  }

  int get _lastActiveMs {
    var last = -1;
    for (final (i, f) in frames.indexed) {
      if (!f.idle) last = i;
    }
    return (last + 1) * 16;
  }

  List<_Counts> get _body {
    var last = -1;
    for (final (i, f) in frames.indexed) {
      if (!f.idle) last = i;
    }
    return last > 1 ? frames.sublist(1, last) : const [];
  }

  static int _median(List<int> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values];
    sorted.sort();
    return sorted[sorted.length ~/ 2];
  }

  /// The ways this step went over [ceiling], or none.
  List<String> over(_Ceiling ceiling) {
    final body = _body;
    final builds = _median([for (final f in body) f.builds]);
    final layouts = _median([for (final f in body) f.layouts]);
    final paints = _median([for (final f in body) f.paints]);
    final first = frames.isEmpty ? 0 : frames.first.builds;
    return [
      if (!settled) '$name did not settle',
      if (first > ceiling.first)
        '$name: first frame builds $first > ${ceiling.first}',
      if (_lastActiveMs > ceiling.ms)
        '$name: last active $_lastActiveMs ms > ${ceiling.ms}',
      if (builds > ceiling.builds)
        '$name: median builds $builds > ${ceiling.builds}',
      if (layouts > ceiling.layouts)
        '$name: median layouts $layouts > ${ceiling.layouts}',
      if (paints > ceiling.paints)
        '$name: median paints $paints > ${ceiling.paints}',
    ];
  }

  static String _spread(List<int> values) {
    if (values.isEmpty) return '-';
    final sorted = [...values];
    sorted.sort();
    return '${sorted[sorted.length ~/ 2]}/${sorted.last}';
  }

  String describe(String scene) {
    final active = [
      for (final (i, f) in frames.indexed)
        if (!f.idle) i,
    ];
    final last = active.isEmpty ? -1 : active.last;
    final body = last > 1 ? frames.sublist(1, last) : <_Counts>[];
    int sum(int Function(_Counts) of) => frames.fold(0, (a, f) => a + of(f));
    final head =
        '[$scene] $name: ${frames.length} frames, ${active.length} active, '
        'last active ${(last + 1) * 16} ms${settled ? '' : ' (not settled)'}';
    final summary =
        '  first ${frames.isEmpty ? '-' : frames.first.token}'
        '  body med/max b ${_spread([for (final f in body) f.builds])}'
        ' l ${_spread([for (final f in body) f.layouts])}'
        ' p ${_spread([for (final f in body) f.paints])}'
        '  total b ${sum((f) => f.builds)} l ${sum((f) => f.layouts)}'
        ' p ${sum((f) => f.paints)} +${sum((f) => f.mounts)}m'
        ' -${sum((f) => f.unmounts)}u g${sum((f) => f.glass)}';
    return [
      head,
      '  ${_timeline()}',
      summary,
      if (builders.isNotEmpty) '  build: ${_top(builders)}',
      if (layouts.isNotEmpty) '  layout: ${_top(layouts)}',
      if (paints.isNotEmpty) '  paint: ${_top(paints)}',
    ].join('\n');
  }
}

/// A page over striped content, so glass has a backdrop to sample.
Widget _page(Widget child, {Widget? bottom, Widget? fill}) => Stack(
  children: [
    const Positioned.fill(child: ColoredBox(color: Color(0xFFF2F2F7))),
    for (var i = 0; i < 12; i++)
      Positioned(
        left: 0,
        right: 0,
        top: i * 80.0,
        height: 40,
        child: ColoredBox(color: Color(0xFF000000 | (i * 0x153F7B))),
      ),
    Center(child: child),
    if (bottom != null) Positioned(left: 0, right: 0, bottom: 0, child: bottom),
    if (fill != null) Positioned.fill(child: fill),
  ],
);

/// A parent that rebuilds its control whenever [value] changes, as an app
/// holds a control's state.
Widget _parent<T>(ValueNotifier<T> value, Widget Function(T value) build) =>
    ValueListenableBuilder<T>(
      valueListenable: value,
      builder: (BuildContext context, T v, Widget? _) => build(v),
    );

ValueNotifier<T> _notifier<T>(T value) {
  final notifier = ValueNotifier<T>(value);
  addTearDown(notifier.dispose);
  return notifier;
}

_Step _set<T>(String name, ValueNotifier<T> notifier, T value) =>
    _Step(name, (_) => notifier.value = value);

Future<void> _tapAway(WidgetTester tester) =>
    tester.tapAt(const Offset(20, 840));

const _tabs = [
  MorphTabItem(icon: Icons.home, label: 'Home'),
  MorphTabItem(icon: Icons.search, label: 'Browse'),
  MorphTabItem(icon: Icons.radio, label: 'Radio'),
  MorphTabItem(icon: Icons.person, label: 'Profile'),
];

const _menuEntries = <MorphMenuEntry>[
  MorphMenuItem(title: 'Copy'),
  MorphMenuItem(title: 'Share'),
  MorphMenuItem(title: 'Rename'),
  MorphMenuItem(title: 'Move'),
  MorphMenuItem(title: 'Duplicate'),
  MorphMenuItem(title: 'Delete'),
];

final _scenes = <_Scene>[
  _Scene('segmented', (env) {
    final index = _notifier(0);
    return _Setup(
      _page(
        _parent(
          index,
          (int i) => SizedBox(
            width: 340,
            child: MorphSegmentedControl(
              segments: const [
                MorphSegment('One'),
                MorphSegment('Two'),
                MorphSegment('Three'),
                MorphSegment('Four'),
              ],
              selectedIndex: i,
              onChanged: (int v) => index.value = v,
            ),
          ),
        ),
      ),
      [
        _set('select-2', index, 2),
        _set('select-0', index, 0),
        _set('select-3', index, 3),
        _set('select-0-again', index, 0),
      ],
    );
  }),
  _Scene('tabbar', (env) {
    final index = _notifier(0);
    return _Setup(
      _parent(
        index,
        (int i) => _page(
          Text('Tab $i'),
          bottom: MorphTabBar(
            items: _tabs,
            selected: i,
            onChanged: (int v) => index.value = v,
          ),
        ),
      ),
      [
        _set('select-1', index, 1),
        _set('select-3', index, 3),
        _set('select-0', index, 0),
      ],
    );
  }),
  _Scene('switch', (env) {
    final on = _notifier(false);
    return _Setup(
      _page(
        _parent(
          on,
          (bool v) =>
              MorphSwitch(value: v, onChanged: (bool v) => on.value = v),
        ),
      ),
      [_set('set-on', on, true), _set('set-off', on, false)],
    );
  }),
  _Scene('slider', (env) {
    final value = _notifier(0.3);
    return _Setup(
      _page(
        _parent(
          value,
          (double v) => SizedBox(
            width: 354,
            child: MorphSlider(
              value: v,
              onChanged: (double v) => value.value = v,
            ),
          ),
        ),
      ),
      [_set('set-0.8', value, 0.8), _set('set-0.2', value, 0.2)],
    );
  }),
  _Scene('stepper', (env) {
    final value = _notifier(0.0);
    final enabled = _notifier(true);
    return _Setup(
      _page(
        _parent(
          enabled,
          (bool on) => _parent(
            value,
            (double v) => MorphStepper(
              value: v,
              max: 10,
              onChanged: on ? (double v) => value.value = v : null,
            ),
          ),
        ),
      ),
      [
        _set('set-5', value, 5.0),
        _set('set-0', value, 0.0),
        _set('disable', enabled, false),
        _set('enable', enabled, true),
      ],
    );
  }),
  _Scene('button', (env) {
    final state = _notifier<_ButtonState>((
      enabled: true,
      tint: null,
      title: 'Glass',
    ));
    TestGesture? press;
    return _Setup(
      _page(
        _parent(
          state,
          (s) => switch (s.tint) {
            null => MorphGlassButton(
              key: const ValueKey<String>('button'),
              enabled: s.enabled,
              onPressed: () {},
              child: Text(s.title),
            ),
            final Color tint => MorphGlassButton.prominent(
              key: const ValueKey<String>('button'),
              enabled: s.enabled,
              tint: tint,
              onPressed: () {},
              child: Text(s.title),
            ),
          },
        ),
      ),
      [
        _Step(
          'disable',
          (_) => state.value = (enabled: false, tint: null, title: 'Glass'),
        ),
        _Step(
          'enable',
          (_) => state.value = (enabled: true, tint: null, title: 'Glass'),
        ),
        _Step('highlight-on', (tester) async {
          press = await tester.startGesture(
            tester.getCenter(find.byKey(const ValueKey<String>('button'))),
          );
        }),
        _Step('highlight-off', (_) => press!.up()),
        _Step(
          'config-prominent',
          (_) => state.value = (
            enabled: true,
            tint: const Color(0xFF0A84FF),
            title: 'Glass',
          ),
        ),
        _Step(
          'config-glass',
          (_) => state.value = (enabled: true, tint: null, title: 'Glass'),
        ),
        _Step(
          'title-change',
          (_) => state.value = (
            enabled: true,
            tint: null,
            title: 'Longer glass button',
          ),
        ),
        _Step(
          'title-restore',
          (_) => state.value = (enabled: true, tint: null, title: 'Glass'),
        ),
      ],
    );
  }),
  _Scene('merge', (env) {
    final at = _notifier((inside: false, animated: true));
    return _Setup(
      _page(
        SizedBox(
          width: 402,
          height: 120,
          child: MorphGlassContainer(
            child: _parent(
              at,
              (s) => Stack(
                children: [
                  Positioned(
                    left: 100,
                    top: 38,
                    width: 80,
                    height: 44,
                    child: MorphGlassButton(
                      onPressed: () {},
                      child: const Text('A'),
                    ),
                  ),
                  AnimatedPositioned(
                    left: s.inside ? 170 : 270,
                    top: 38,
                    width: 80,
                    height: 44,
                    duration: s.animated
                        ? const Duration(milliseconds: 800)
                        : Duration.zero,
                    curve: Curves.easeInOut,
                    child: MorphGlassButton(
                      onPressed: () {},
                      child: const Text('B'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      [
        _set('animate-in', at, (inside: true, animated: true)),
        _set('animate-out', at, (inside: false, animated: true)),
        _set('jump-in', at, (inside: true, animated: false)),
        _set('jump-out', at, (inside: false, animated: false)),
      ],
    );
  }),
  _Scene(
    'menu',
    (env) => _Setup(_page(const MorphMenuButton(menu: _menuEntries)), [
      _Step('open-inline', (t) => t.tap(find.byType(MorphMenuButton))),
      const _Step('close-inline', _tapAway),
      _Step('open-inline-2', (t) => t.tap(find.byType(MorphMenuButton))),
      const _Step('close-inline-2', _tapAway),
    ]),
  ),
  _Scene('context-menu', (env) {
    TestGesture? hold;
    return _Setup(
      MorphScope(
        child: _page(
          MorphContextMenuRegion(
            below: MorphSatellite(
              builder: (BuildContext context, MorphFlight flight) =>
                  const ColoredBox(
                    color: Color(0xFFFFFFFF),
                    child: SizedBox(width: 250, height: 176),
                  ),
            ),
            child: const ColoredBox(
              key: ValueKey<String>('bubble'),
              color: Color(0xFF0A84FF),
              child: SizedBox(width: 180, height: 56),
            ),
          ),
        ),
      ),
      [
        _Step('press-and-hold', (tester) async {
          hold = await tester.startGesture(
            tester.getCenter(find.byKey(const ValueKey<String>('bubble'))),
          );
        }, frames: 60),
        _Step('release', (_) => hold!.up()),
        const _Step('close', _tapAway),
      ],
    );
  }),
  _Scene('sheet', (env) {
    BuildContext? sheet;
    void present() => unawaited(
      showMorphSheet<void>(
        env.context,
        detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
        // The controller is read where a detent button would read it, in
        // a leaf of the content, not at its root.
        builder: (BuildContext context) => ListView(
          controller: MorphSheet.scrollControllerOf(context),
          children: [
            Builder(
              builder: (BuildContext context) {
                sheet = context;
                MorphSheet.of(context);
                return const SizedBox(height: 44, child: Text('Detents'));
              },
            ),
            for (var i = 0; i < 15; i++)
              SizedBox(height: 44, child: Text('Row $i')),
          ],
        ),
      ),
    );
    void detent(MorphSheetDetent d) => MorphSheet.of(sheet!).animateTo(d);
    void dismiss() => Navigator.of(sheet!).pop();
    return _Setup(_page(const Text('Host')), [
      _Step('present', (_) => present()),
      _Step('detent-large', (_) => detent(MorphSheetDetent.large)),
      _Step('detent-medium', (_) => detent(MorphSheetDetent.medium)),
      _Step('dismiss', (_) => dismiss()),
      _Step('present-2', (_) => present()),
      _Step('dismiss-2', (_) => dismiss()),
    ]);
  }),
  _Scene('alert', (env) {
    void show() => unawaited(
      showMorphAlert(
        env.context,
        title: 'Title',
        message: 'A message.',
        actions: const [
          MorphAlertAction(title: 'OK'),
          MorphAlertAction(
            title: 'Cancel',
            style: MorphAlertActionStyle.cancel,
          ),
        ],
      ),
    );
    void sheet() => unawaited(
      showMorphActionSheet(
        env.context,
        title: 'Title',
        message: 'A message.',
        anchorRect: Rect.fromCenter(
          center: const Offset(201, 437),
          width: 100,
          height: 44,
        ),
        actions: const [
          MorphAlertAction(title: 'OK'),
          MorphAlertAction(
            title: 'Cancel',
            style: MorphAlertActionStyle.cancel,
          ),
        ],
      ),
    );
    void dismiss() => env.navigator.currentState!.pop();
    return _Setup(_page(const Text('Host')), [
      _Step('show', (_) => show()),
      _Step('dismiss', (_) => dismiss()),
      _Step('show-2', (_) => show()),
      _Step('dismiss-2', (_) => dismiss()),
      _Step('action-sheet-show', (_) => sheet()),
      _Step('action-sheet-dismiss', (_) => dismiss()),
    ]);
  }),
  _Scene('search', (env) {
    final active = _notifier(false);
    final text = TextEditingController();
    final focus = FocusNode();
    addTearDown(text.dispose);
    addTearDown(focus.dispose);
    return _Setup(
      _parent(
        active,
        (bool on) => _page(
          const Text('Results'),
          fill: MorphSearchTabBar(
            items: _tabs.take(3).toList(),
            selected: 0,
            onChanged: (_) {},
            active: on,
            onActiveChanged: (bool v) => active.value = v,
            controller: text,
            focusNode: focus,
          ),
        ),
      ),
      [
        _set('tab-search', active, true),
        _Step('focus', (_) => focus.requestFocus()),
        _Step('type-1', (_) => text.text = 'I'),
        _Step('type-3', (_) => text.text = 'Item'),
        _Step('clear', (_) => text.clear()),
        _Step('resign', (_) => focus.unfocus()),
        _set('cancel', active, false),
      ],
    );
  }),
  _Scene('search-bar', (env) {
    final text = TextEditingController();
    final focus = FocusNode();
    addTearDown(text.dispose);
    addTearDown(focus.dispose);
    return _Setup(
      _page(
        const Text('Results'),
        fill: MorphSearchToolbar(controller: text, focusNode: focus),
      ),
      [
        _Step('focus', (_) => focus.requestFocus()),
        _Step('type-1', (_) => text.text = 'I'),
        _Step('type-3', (_) => text.text = 'Item'),
        _Step('clear', (_) => text.clear()),
        _Step('resign', (_) => focus.unfocus()),
      ],
    );
  }),
  _Scene('scrolledge', (env) {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    _Step to(String name, double y, {bool animated = true}) => _Step(
      name,
      (_) => animated
          ? unawaited(
              scroll.animateTo(
                y,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              ),
            )
          : scroll.jumpTo(y),
    );
    return _Setup(
      MorphNavigationStack(
        home: MorphNavigationScaffold(
          title: 'Bars',
          largeTitleDisplayMode: MorphLargeTitleDisplayMode.always,
          controller: scroll,
          slivers: [
            SliverList.builder(
              itemCount: 120,
              itemBuilder: (BuildContext context, int i) => SizedBox(
                height: 44,
                child: ColoredBox(
                  color: Color(0xFF000000 | ((i * 0x2A3F1B) & 0xFFFFFF)),
                  child: Text('Row $i'),
                ),
              ),
            ),
          ],
        ),
      ),
      [
        to('scroll-300', 300),
        to('scroll-1500', 1500),
        to('scroll-top', 0),
        to('jump-600', 600, animated: false),
        to('jump-top', 0, animated: false),
      ],
    );
  }),
  _Scene('pagecontrol', (env) {
    final state = _notifier((count: 5, page: 0));
    return _Setup(
      _page(
        _parent(
          state,
          (s) => MorphPageControl(
            count: s.count,
            page: s.page,
            onChanged: (int p) => state.value = (count: s.count, page: p),
          ),
        ),
      ),
      [
        _set('page-1', state, (count: 5, page: 1)),
        _set('page-4', state, (count: 5, page: 4)),
        _set('page-0', state, (count: 5, page: 0)),
        _set('pages-7', state, (count: 7, page: 0)),
        _set('pages-5', state, (count: 5, page: 0)),
      ],
    );
  }),
  _Scene('progress', (env) {
    final state = _notifier((value: 0.3, animated: true));
    return _Setup(
      _page(
        _parent(
          state,
          (s) => SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MorphProgressView(value: s.value, animated: s.animated),
                const SizedBox(height: 20),
                MorphProgressView(
                  value: s.value,
                  animated: s.animated,
                  style: MorphProgressViewStyle.bar,
                ),
              ],
            ),
          ),
        ),
      ),
      [
        _set('progress-0.8', state, (value: 0.8, animated: true)),
        _set('progress-0.1', state, (value: 0.1, animated: true)),
        _set('progress-0.5-plain', state, (value: 0.5, animated: false)),
      ],
    );
  }),
  _Scene('activity', (env) {
    final spinning = _notifier(true);
    return _Setup(
      _page(
        _parent(
          spinning,
          (bool on) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MorphActivityIndicator(animating: on, hidesWhenStopped: false),
              const SizedBox(height: 20),
              MorphActivityIndicator(
                animating: on,
                hidesWhenStopped: false,
                size: MorphActivityIndicatorSize.large,
              ),
            ],
          ),
        ),
      ),
      [
        _Step('spinning-steady', (_) {}, frames: 94),
        _set('spinner-stop', spinning, false),
        const _Step('stopped-steady', _idle, frames: 60),
        _Step('spinner-start', (_) => spinning.value = true, frames: 60),
      ],
      end: (_) => spinning.value = false,
    );
  }),
  _Scene('datepicker', (env) {
    final day = DateTime(2026, 10, 12);
    final date = _notifier(day);
    final time = _notifier(DateTime(2026, 10, 12, 9, 41));
    return _Setup(
      _page(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _parent(
              date,
              (DateTime v) => MorphDatePicker(
                key: const ValueKey<String>('date'),
                value: v,
                today: day,
                onChanged: (DateTime v) => date.value = v,
              ),
            ),
            const SizedBox(height: 40),
            _parent(
              time,
              (DateTime v) => MorphDatePicker(
                key: const ValueKey<String>('time'),
                mode: MorphDatePickerMode.time,
                value: v,
                today: day,
                onChanged: (DateTime v) => time.value = v,
              ),
            ),
          ],
        ),
      ),
      [
        _set('compact-set-closed', date, DateTime(2026, 10, 13)),
        _Step(
          'compact-open',
          (t) => t.tap(find.byKey(const ValueKey<String>('date'))),
        ),
        _set('calendar-next-month', date, DateTime(2026, 11, 13)),
        const _Step('compact-close', _tapAway),
        _Step(
          'wheels-open',
          (t) => t.tap(find.byKey(const ValueKey<String>('time'))),
        ),
        _set('wheel-set', time, DateTime(2026, 10, 12, 12, 58)),
        _set('wheel-set-back', time, DateTime(2026, 10, 12, 9, 41)),
        const _Step('wheels-close', _tapAway),
      ],
    );
  }),
  _Scene('navigation', (env) {
    MorphBarButton icon(String id) => MorphBarButton(
      id: id,
      icon: const SizedBox.square(dimension: 24),
      semanticLabel: id,
      onPressed: () {},
    );
    List<Widget> rows(String page) => [
      SliverList.builder(
        itemCount: 40,
        itemBuilder: (BuildContext context, int i) =>
            SizedBox(height: 44, child: Text('$page $i')),
      ),
    ];
    return _Setup(
      MorphNavigationStack(
        home: MorphNavigationScaffold(
          title: 'Inbox',
          largeTitleDisplayMode: MorphLargeTitleDisplayMode.always,
          trailing: [
            MorphBarButtonGroup([icon('add'), icon('more')]),
          ],
          slivers: rows('Inbox'),
        ),
      ),
      [
        _Step('push', (tester) {
          final context = tester.element(find.text('Inbox 0'));
          unawaited(
            Navigator.of(context).push(
              MorphNavigationRoute<void>(
                builder: (_) => MorphNavigationScaffold(
                  title: 'Message',
                  trailing: [
                    MorphBarButtonGroup([icon('like'), icon('share')]),
                  ],
                  slivers: rows('Message'),
                ),
              ),
            ),
          );
        }),
        _Step(
          'pop',
          (tester) =>
              Navigator.of(tester.element(find.text('Message 0'))).pop(),
        ),
      ],
    );
  }),
];

void _idle(WidgetTester tester) {}

typedef _ButtonState = ({bool enabled, Color? tint, String title});
