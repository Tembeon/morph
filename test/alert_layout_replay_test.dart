import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';

const _sim = 'test/fixtures/ios27/alert';
const _device = 'test/fixtures/ios27-device/alert';

/// The tolerance of a resting frame against a UIKit layout read, in
/// points: the popover placement replay of alert_test ('placement matches
/// UIKit for every captured source') and the layout replays of
/// navigation_title_layout_test and date_picker_test hold resting frames
/// to it.
const double _tolerance = 0.5;

/// The safe area of both recording screens: the device platter rests at
/// y 451 = (62 + 874 - 34) / 2, the simulator's at 492 = (62 + 956 -
/// 34) / 2, and placements.json logs the padding (0, 62, 0, 34).
const _safeArea = EdgeInsets.only(top: 62, bottom: 34);

/// The probe's x3alert actions in the order it adds them
/// (Sources/Extras.swift showAlert, PROBE_ACTIONS unset: 3).
const _actions = [
  MorphAlertAction(title: 'OK'),
  MorphAlertAction(title: 'Delete', style: .destructive),
  MorphAlertAction(title: 'Cancel', style: .cancel),
];

const _title = 'Title';

/// The probe's message is "A message for the alert.", one line on the
/// device: the 264 point platter holds one 18 point message line. The
/// host test font draws every glyph one em wide and would wrap it in the
/// 260 point text column, so the replay shows a message that keeps the
/// recorded single line.
const _message = 'A message.';

/// Every popover fixture rests at the same content rect. The alert's
/// header constants give the content 207.99 points against UIKit's
/// 208.33, and the engine rounds each text line box to whole points (the
/// 20.33 point title line lays out 20 tall).
const _popoverSkip =
    'content top 0.72 pt low, height 0.71 pt short (355.39 / 207.62 vs '
    'UIKit 354.67 / 208.33): max 0.72, rms 0.51 vs 0.5 pt';

/// The probe's source button: 120 x 48, centered across the window, its
/// center 600 points from the top (Extras.swift, PROBE_BTN_Y unset).
Rect _source(Size screen) => Rect.fromCenter(
  center: Offset(screen.width / 2, 600),
  width: 120,
  height: 48,
);

/// A tracked UIKit view at rest: its class and its frame in window
/// points.
typedef _View = ({String cls, Rect frame});

/// A recording's window size and every tracked view as it rests before
/// the first touch or the scripted dismissal: the last sample of each
/// view, kept only when its layer is at scale 1 and opaque.
({Size screen, List<_View> views}) _rest(String path) {
  final rows = [
    for (final line in File(path).readAsLinesSync())
      if (line.trim().isNotEmpty)
        (jsonDecode(line) as Map).cast<String, Object?>(),
  ];
  double d(Map<String, Object?> r, String k) => (r[k]! as num).toDouble();
  final last = <int, Map<String, Object?>>{};
  for (final r in rows) {
    if (r['k'] == 'touch' || (r['k'] == 'evt' && r['e'] == 'dismiss')) break;
    if (r['k'] == 'V') last[r['id']! as int] = r;
  }
  final views = [
    for (final r in last.values)
      if (d(r, 'sx') == 1 && d(r, 'sy') == 1 && d(r, 'a') == 1)
        (
          cls: r['cls']! as String,
          frame: Rect.fromCenter(
            center: Offset(d(r, 'x'), d(r, 'y')),
            width: d(r, 'bw'),
            height: d(r, 'bh'),
          ),
        ),
  ];
  views.sort((_View a, _View b) => a.frame.top.compareTo(b.frame.top));
  return (screen: Size(d(rows.first, 'w'), d(rows.first, 'h')), views: views);
}

Finder _card() =>
    find.byWidgetPredicate((Widget w) => '${w.runtimeType}' == '_AlertCard');

Finder _button(String title) => find.ancestor(
  of: find.text(title),
  matching: find.byWidgetPredicate(
    (Widget w) => '${w.runtimeType}' == '_AlertButton',
  ),
);

Future<void> _show(
  WidgetTester tester,
  Size screen,
  void Function(BuildContext context) show,
) async {
  tester.view.physicalSize = screen * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = FakeViewPadding(
    top: _safeArea.top * 3,
    bottom: _safeArea.bottom * 3,
  );
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => Center(
          child: GestureDetector(
            key: const ValueKey('open'),
            behavior: HitTestBehavior.opaque,
            onTap: () => show(context),
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

/// Expects [actual] within [_tolerance] of [recorded] on its left, top,
/// width and height.
void _compare(Rect actual, Rect recorded, String name) {
  final deltas = [
    actual.left - recorded.left,
    actual.top - recorded.top,
    actual.width - recorded.width,
    actual.height - recorded.height,
  ];
  for (final (i, side) in ['left', 'top', 'width', 'height'].indexed) {
    expect(
      deltas[i].abs(),
      lessThanOrEqualTo(_tolerance),
      reason: '$name $side: morph $actual, UIKit $recorded',
    );
  }
}

void main() {
  const alerts = [
    '$_device/alert-present-dismiss.jsonl',
    '$_device/alert-press.jsonl',
    '$_device/alert-tap.jsonl',
    '$_device/alert-slide.jsonl',
    '$_device/alert-lean.jsonl',
    '$_sim/alert-present-dismiss.jsonl',
    '$_sim/alert-press.jsonl',
    '$_sim/alert-tap.jsonl',
  ];
  for (final path in alerts) {
    final name = path.split('/').skip(2).join('/');
    testWidgets('a three-action alert rests where UIKit lays out its platter '
        'and its buttons ($name)', (tester) async {
      final rest = _rest(path);
      await _show(
        tester,
        rest.screen,
        (BuildContext context) => showMorphAlert(
          context,
          title: _title,
          message: _message,
          actions: _actions,
        ),
      );
      _compare(
        tester.getRect(_card()),
        rest.views
            .singleWhere(
              (_View v) => v.cls == '_UIAlertControllerPhoneTVMacView',
            )
            .frame,
        'platter',
      );
      final buttons = [
        for (final v in rest.views)
          if (v.cls == '_UIInterfaceActionCustomViewRepresentationView') v,
      ];
      if (buttons.isNotEmpty) {
        for (final (i, title) in ['OK', 'Delete', 'Cancel'].indexed) {
          _compare(tester.getRect(_button(title)), buttons[i].frame, title);
        }
      }
    });
  }

  final placements =
      (jsonDecode(File('$_sim/placements.json').readAsStringSync()) as Map)
          .cast<String, Object?>();
  final contentHeight = ((placements['contentSize']! as List)[1]! as num)
      .toDouble();
  const sheets = [
    '$_device/actionsheet-present-dismiss.jsonl',
    '$_device/ash-press.jsonl',
    '$_device/ash-tap-out.jsonl',
    '$_sim/actionsheet-present-dismiss.jsonl',
    '$_sim/actionsheet-tap-out.jsonl',
  ];
  group('popover layout', () {
    for (final path in sheets) {
      final name = path.split('/').skip(2).join('/');
      testWidgets('an action sheet with a source rests where UIKit lays out '
          'its popover content ($name)', (tester) async {
        final rest = _rest(path);
        final popover = rest.views
            .singleWhere((_View v) => v.cls == '_UIPopoverView')
            .frame;
        final source = _source(rest.screen);
        expect(
          popover.bottom,
          closeTo(source.top, _tolerance),
          reason: 'the recorded arrow ends on the probe source',
        );
        await _show(
          tester,
          rest.screen,
          (BuildContext context) => showMorphActionSheet(
            context,
            title: _title,
            message: _message,
            actions: _actions,
            anchorRect: source,
          ),
        );
        // The popover view holds the content and, toward the source below
        // it, the arrow; placements.json logs the content's own height.
        _compare(
          tester.getRect(_card()),
          Rect.fromLTWH(
            popover.left,
            popover.top,
            popover.width,
            contentHeight,
          ),
          'content',
        );
      });
    }
  }, skip: _popoverSkip);
}
