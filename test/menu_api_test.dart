import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/menu_content.dart';
import 'package:morph/src/widgets/menu_entries.dart';
import 'package:morph/src/widgets/menu_layout.dart';
import 'package:morph/src/widgets/menu_motion.dart';

const _dir = 'test/fixtures/ios27-device/menu_api';

List<Map<String, Object?>> _rows(String name) => [
  for (final line in File('$_dir/$name.jsonl').readAsLinesSync())
    if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
];

double _n(Map<String, Object?> row, String key) =>
    (row[key]! as num).toDouble();

final Map<String, Object?> _layoutJson =
    jsonDecode(File('$_dir/layout.json').readAsStringSync())
        as Map<String, Object?>;

Map<String, Object?> _section(String key) =>
    _layoutJson['layout']! as Map<String, Object?>;

const _sort = MorphMenuSection(
  title: 'Sort by',
  singleSelection: true,
  children: [
    MorphMenuItem(title: 'Name', icon: IconData(1), state: MorphMenuState.on),
    MorphMenuItem(title: 'Date', icon: IconData(2)),
    MorphMenuItem(title: 'Size', icon: IconData(3)),
  ],
);

const _rich1 = <MorphMenuEntry>[
  _sort,
  MorphMenuSection(
    children: [
      MorphMenuItem(
        title: 'Show hidden',
        icon: IconData(4),
        state: MorphMenuState.on,
      ),
      MorphMenuItem(
        title: 'Mixed state',
        icon: IconData(5),
        state: MorphMenuState.mixed,
      ),
    ],
  ),
  MorphMenuSection(
    children: [
      MorphMenuItem(
        title: 'With subtitle',
        subtitle: 'A second line of detail',
        icon: IconData(6),
      ),
      MorphMenuItem(title: 'Disabled row', icon: IconData(7), enabled: false),
      MorphMenuItem(title: 'Delete', icon: IconData(8), destructive: true),
    ],
  ),
];

const _rich2 = <MorphMenuEntry>[
  MorphMenuSection(
    title: 'Color',
    palette: true,
    children: [
      MorphMenuItem(title: 'Red', icon: IconData(1)),
      MorphMenuItem(title: 'Orange', icon: IconData(1)),
      MorphMenuItem(title: 'Green', icon: IconData(1)),
      MorphMenuItem(title: 'Blue', icon: IconData(1), state: .on),
      MorphMenuItem(title: 'Purple', icon: IconData(1)),
    ],
  ),
  MorphMenuSection(
    elementSize: .small,
    children: [
      MorphMenuItem(title: 'Cut', icon: IconData(2)),
      MorphMenuItem(title: 'Copy', icon: IconData(2)),
      MorphMenuItem(title: 'Paste', icon: IconData(2)),
      MorphMenuItem(title: 'Share', icon: IconData(2)),
    ],
  ),
  MorphMenuSection(
    elementSize: .medium,
    children: [
      MorphMenuItem(title: 'Bold', icon: IconData(3)),
      MorphMenuItem(title: 'Italic', icon: IconData(3)),
      MorphMenuItem(title: 'Underline', icon: IconData(3)),
    ],
  ),
  MorphMenuSection(
    title: 'Inline submenu',
    children: [
      MorphMenuItem(title: 'Inline one'),
      MorphMenuItem(title: 'Inline two'),
    ],
  ),
  MorphMenuItem(title: 'Plain row', icon: IconData(4)),
];

const _deeper = MorphSubmenu(
  title: 'Deeper',
  icon: IconData(13),
  children: [
    MorphMenuItem(title: 'Deep one'),
    MorphMenuItem(title: 'Deep two'),
  ],
);

final _log = <String>[];

final _sub = <MorphMenuEntry>[
  const MorphMenuItem(title: 'Copy', icon: IconData(1)),
  const MorphMenuItem(title: 'Share', icon: IconData(2)),
  MorphSubmenu(
    title: 'More',
    icon: const IconData(3),
    children: [
      MorphMenuItem(
        title: 'Sub one',
        icon: const IconData(11),
        onSelected: () => _log.add('Sub one'),
      ),
      MorphMenuItem(
        title: 'Sub two',
        icon: const IconData(12),
        onSelected: () => _log.add('Sub two'),
      ),
      _deeper,
    ],
  ),
  const MorphMenuItem(title: 'Delete', icon: IconData(4), destructive: true),
];

Rect _element(MorphMenuLayout layout, String title) {
  for (final element in layout.elements) {
    final entry = element.entry;
    final name = switch (entry) {
      MorphMenuItem(:final title) => title,
      MorphSubmenu(:final title) => title,
      _ => element.title,
    };
    if (name == title) return element.rect;
  }
  throw StateError('no $title');
}

MorphMenuMotion _motion(List<MorphMenuEntry> entries) {
  final content = MorphMenuContent(onChanged: ({required bool animate}) {});
  content.entries = entries;
  final motion = MorphMenuMotion(
    button: Rect.fromCenter(
      center: const Offset(201, 150),
      width: 48,
      height: 48,
    ),
    layout: content.root,
    bounds: const Size(402, 874),
    padding: const EdgeInsets.only(top: 62, bottom: 34),
  );
  morphConnectMenu(motion, content);
  return motion;
}

/// Replays [name]: the first stroke opens the menu (at its lift, without
/// the tap delay), every later touch is fed at its time, shifted by the
/// difference between our menu's top and the device's; [check] runs at
/// every logged frame after the second stroke starts.
void _replay(
  String name,
  MorphMenuMotion motion,
  void Function(double t, Map<String, Object?> frame) check, {
  double? deviceTop,
}) {
  final rows = _rows(name);
  final touches = rows.where((Map<String, Object?> r) => r['k'] == 'touch');
  final lift = touches.firstWhere((Map<String, Object?> r) => r['phase'] == 3);
  final menu = rows.firstWhere(
    (Map<String, Object?> r) =>
        r['k'] == 'frame' && r['cls'] == '_UIContextMenuView',
  );
  final t0 = _n(lift, 't');
  motion.open(0, sourceScale: 1);
  motion.advance(1);
  final top = deviceTop ?? _n(menu, 'y') - _n(menu, 'h') / 2;
  final dy = motion.menuRect.top - top;
  var started = false;
  for (final row in rows) {
    final t = _n(row, 't') - t0;
    if (t <= 1) continue;
    if (row['k'] == 'touch') {
      final at = Offset(_n(row, 'x'), _n(row, 'y') + dy);
      switch (row['phase']) {
        case 0:
          started = true;
          motion.pointerDown(t, at);
        case 1:
          motion.pointerMove(t, at);
        case 3:
          motion.pointerUp(t, at);
      }
    } else if (row['k'] == 'frame' && started) {
      motion.advance(t);
      check(t, row);
    }
  }
}

double _rms(List<double> errors) => errors.isEmpty
    ? 0
    : math.sqrt(
        errors.fold<double>(0, (double a, double e) => a + e * e) /
            errors.length,
      );

void main() {
  group('layout (device view tree)', () {
    test('the measured metrics match layout.json', () {
      final layout = _section('layout');
      const m = MorphMenuMetrics.standard;
      expect(m.width, layout['menu_width']);
      expect(m.rowHeight, layout['row_height']);
      expect(m.subtitleRowHeight, layout['row_height_with_subtitle']);
      expect(m.topInset, layout['top_inset']);
      expect(
        m.maxHeight,
        (layout['max_height']! as Map<String, Object?>)['value'],
      );
      final header = layout['section_header']! as Map<String, Object?>;
      expect(m.headerHeight, header['height']);
    });

    test('rich1: header, selection column, gaps, subtitle row', () {
      final layout = MorphMenuLayout.build(_rich1);
      expect(_element(layout, 'Sort by').top, 0);
      final tops = {
        'Name': 38.33,
        'Date': 80.33,
        'Size': 122.33,
        'Show hidden': 185.33,
        'Mixed state': 227.33,
        'With subtitle': 290.33,
        'Disabled row': 350.33,
        'Delete': 392.33,
      };
      for (final MapEntry(key: title, value: top) in tops.entries) {
        expect(
          _element(layout, title).top,
          moreOrLessEquals(top, epsilon: 0.02),
          reason: title,
        );
      }
      expect(_element(layout, 'With subtitle').height, 60);
      expect(layout.height, moreOrLessEquals(444.33, epsilon: 0.02));
      final name = layout.elements.firstWhere(
        (MorphMenuPlaced e) =>
            e.entry is MorphMenuItem &&
            (e.entry! as MorphMenuItem).title == 'Name',
      );
      expect(name.checkCenter, moreOrLessEquals(27.7, epsilon: 0.05));
      expect(name.imageCenter, 55);
      expect(name.titleStart, 79);
      expect(name.titleEnd - name.titleStart, 143);
      final header = layout.elements.firstWhere(
        (MorphMenuPlaced e) => e.kind == MorphMenuPlacedKind.header,
      );
      expect(header.titleStart, 43);
      final separators = layout.elements.where(
        (MorphMenuPlaced e) => e.kind == MorphMenuPlacedKind.separator,
      );
      expect(separators.length, 2);
      expect(
        separators.first.rect.center.dy,
        moreOrLessEquals(164.33 + 10.5, epsilon: 0.02),
      );
      expect(separators.first.rect.left, 24);
      expect(separators.first.rect.right, 226);
      final disabled = layout.targets.where(
        (MorphMenuTarget t) =>
            (t.entry! as MorphMenuItem).title == 'Disabled row',
      );
      expect(disabled, isEmpty, reason: 'a disabled row takes no touch');
    });

    test('rich2: palette, small and medium cells, inline header', () {
      final layout = MorphMenuLayout.build(_rich2);
      final palette = layout.elements
          .where((MorphMenuPlaced e) => e.kind == MorphMenuPlacedKind.palette)
          .toList();
      expect(palette.length, 5);
      const xs = <double>[18.33, 61, 103.67, 146.33, 189];
      for (var i = 0; i < 5; i++) {
        expect(palette[i].rect.left, moreOrLessEquals(xs[i], epsilon: 0.03));
        expect(palette[i].rect.top, moreOrLessEquals(28.33, epsilon: 0.02));
        expect(palette[i].rect.width, moreOrLessEquals(42.67, epsilon: 0.01));
        expect(palette[i].rect.height, 54);
      }
      final small = layout.elements
          .where((MorphMenuPlaced e) => e.kind == MorphMenuPlacedKind.small)
          .toList();
      expect(small.first.rect.left, 8);
      expect(small.first.rect.top, moreOrLessEquals(82.33, epsilon: 0.02));
      expect(small.first.rect.width, moreOrLessEquals(58.33, epsilon: 0.2));
      expect(small.first.rect.height, moreOrLessEquals(51.67, epsilon: 0.01));
      final medium = layout.elements
          .where((MorphMenuPlaced e) => e.kind == MorphMenuPlacedKind.medium)
          .toList();
      expect([for (final e in medium) e.rect.left], [8, 86, 164]);
      expect(medium.first.rect.top, moreOrLessEquals(135, epsilon: 0.02));
      expect(
        _element(layout, 'Inline submenu').top,
        moreOrLessEquals(213, epsilon: 0.02),
      );
      expect(
        _element(layout, 'Inline one').top,
        moreOrLessEquals(251.33, epsilon: 0.02),
      );
      expect(
        _element(layout, 'Plain row').top,
        moreOrLessEquals(356.33, epsilon: 0.02),
      );
      expect(layout.height, moreOrLessEquals(408.33, epsilon: 0.02));
      final inline = layout.elements.firstWhere(
        (MorphMenuPlaced e) =>
            e.entry is MorphMenuItem &&
            (e.entry! as MorphMenuItem).title == 'Inline one',
      );
      final plain = layout.elements.firstWhere(
        (MorphMenuPlaced e) =>
            e.entry is MorphMenuItem &&
            (e.entry! as MorphMenuItem).title == 'Plain row',
      );
      expect(inline.titleStart, 28);
      expect(plain.titleStart, 64);
      expect(plain.imageCenter, 40);
    });

    test('a submenu card: header 62, rows after the inset', () {
      final layout = MorphMenuLayout.build(
        (_sub[2] as MorphSubmenu).children,
        header: _sub[2] as MorphSubmenu,
      );
      expect(_element(layout, 'More').height, 62);
      expect(_element(layout, 'Sub one').top, 72);
      expect(layout.height, moreOrLessEquals(208, epsilon: 0.5));
      expect(layout.targets.first.kind, MorphMenuTargetKind.back);
      expect(
        layout.targets.last.kind,
        MorphMenuTargetKind.submenu,
        reason: 'Deeper opens the next card',
      );
    });

    test('a loading deferred group is one 42 pt row', () {
      final layout = MorphMenuLayout.build([
        const MorphMenuItem(title: 'Copy', icon: IconData(1)),
        MorphMenuDeferred(() async => const []),
      ], resolve: (MorphMenuDeferred deferred) => null);
      expect(layout.loading, isTrue);
      expect(layout.height, 104);
      final loading = layout.elements.last;
      expect(loading.kind, MorphMenuPlacedKind.loading);
      expect(loading.imageCenter, 40);
      expect(loading.titleStart, 64);
    });

    test('an upward menu reverses groups and rows, a fixed order does not', () {
      final up = MorphMenuLayout.build(_rich1, reversed: true);
      expect(_element(up, 'Delete').top, lessThan(_element(up, 'Name').top));
      expect(_element(up, 'Sort by').top, lessThan(_element(up, 'Size').top));
      final content = MorphMenuContent(onChanged: ({required bool animate}) {});
      content.entries = _rich1;
      content.order = MorphMenuOrder.fixed;
      final fixed = content.root(reversed: true);
      expect(
        _element(fixed, 'Name').top,
        lessThan(_element(fixed, 'Delete').top),
      );
    });

    test('right to left mirrors the cells', () {
      final layout = MorphMenuLayout.build(_rich2, rtl: true);
      final palette = layout.elements
          .where((MorphMenuPlaced e) => e.kind == MorphMenuPlacedKind.palette)
          .toList();
      expect(
        palette.first.rect.right,
        moreOrLessEquals(250 - 18.33, epsilon: 0.03),
      );
    });
  });

  group('submenu motion (device frames)', () {
    test('a tap opens the card: the menu grows, the root shrinks', () {
      final motion = _motion(_sub);
      final heights = <double>[];
      final widths = <double>[];
      final cardErrors = <double>[];
      final rootId =
          '${_rows('mm-sub-tap').firstWhere((Map<String, Object?> r) => r['cls'] == '_UIContextMenuListView')['id']}';
      _replay('mm-sub-tap', motion, (double t, Map<String, Object?> frame) {
        if (t > 4.5) return;
        if (frame['cls'] == '_UIContextMenuView') {
          final q = motion.cards.length < 2 ? 0.0 : motion.cards[1].progress;
          heights.add(q - (_n(frame, 'h') - 250) / 37.2);
        }
        if (frame['cls'] == '_UIContextMenuListView') {
          if ('${frame['id']}' == rootId) {
            widths.add(250 * motion.cards.first.scale - _n(frame, 'w'));
          } else if (motion.cards.length > 1) {
            final card = motion.cards[1].rect;
            cardErrors.add(card.width - _n(frame, 'w'));
            cardErrors.add(card.height - _n(frame, 'h'));
          }
        }
      });
      expect(motion.cards.length, 2);
      expect(heights.length, greaterThan(20));
      expect(_rms(heights), lessThan(0.01), reason: 'card progress');
      expect(_rms(widths), lessThan(0.1), reason: 'root list width');
      expect(cardErrors.length, greaterThan(20));
      expect(_rms(cardErrors), lessThan(1), reason: 'card frame');
    });

    test('the header sends the card back into its row', () {
      final motion = _motion(_sub);
      final errors = <double>[];
      String? cardId;
      var back = false;
      _replay('mm-sub-back', motion, (double t, Map<String, Object?> frame) {
        if (frame['cls'] != '_UIContextMenuListView') return;
        if (_n(frame, 'h') > 200 && _n(frame, 'h') < 215) {
          cardId = '${frame['id']}';
        }
        if ('${frame['id']}' != cardId || motion.cards.length < 2) return;
        if (_n(frame, 'h') < 205) back = true;
        if (!back) return;
        final card = motion.cards[1].rect;
        errors.add(card.height - _n(frame, 'h'));
        errors.add(card.width - _n(frame, 'w'));
      });
      expect(errors.length, greaterThan(20));
      expect(_rms(errors), lessThan(1.5));
    });

    test('a deeper card grows on its own spring', () {
      final motion = _motion(_sub);
      final errors = <double>[];
      _replay('mm-sub-deeper', motion, (double t, Map<String, Object?> frame) {
        if (frame['cls'] != '_UIContextMenuListView') return;
        if (motion.cards.length < 3 || t > 5) return;
        if (_n(frame, 'w') < 229 || _n(frame, 'h') > 168) return;
        if (_n(frame, 'w') > 249.9 && _n(frame, 'h') > 165) return;
        final card = motion.cards[2].rect;
        errors.add(card.height - _n(frame, 'h'));
      });
      expect(errors.length, greaterThan(8));
      expect(_rms(errors), lessThan(2));
      expect(
        motion.cards.first.scale,
        moreOrLessEquals(0.97 * 0.97, epsilon: 1e-3),
      );
    });

    test(
      'a held finger opens the card after the dwell and fires a sub row',
      () {
        _log.clear();
        final motion = _motion(_sub);
        final rows = _rows('mm-sub-slide2');
        final t0 = _n(rows.first, 't');
        final evt = rows.firstWhere(
          (Map<String, Object?> r) => r['k'] == 'evt',
        );
        final lift = rows.lastWhere(
          (Map<String, Object?> r) => r['k'] == 'touch' && r['phase'] == 3,
        );
        double? opened;
        double? fired;
        motion.onActivate = (MorphMenuTarget target) {
          fired = motion.time;
          (target.entry! as MorphMenuItem).onSelected?.call();
        };
        var dy = 0.0;
        for (final row in rows) {
          final t = _n(row, 't') - t0;
          if (row['k'] != 'touch') continue;
          while (motion.time + 0.004 < t) {
            motion.advance(motion.time + 0.004);
            if (opened == null && motion.cards.length > 1) opened = motion.time;
          }
          if (motion.isOpen && dy == 0) dy = motion.menuRect.top - 118.33;
          final at = Offset(_n(row, 'x'), _n(row, 'y') + dy);
          switch (row['phase']) {
            case 0:
              motion.pointerDown(t, at);
            case 1:
              motion.pointerMove(t, at);
            case 3:
              motion.pointerUp(t, at);
          }
        }
        motion.advance(motion.time + 0.1);
        expect(opened, isNotNull);
        expect((opened! - 6.021).abs(), lessThan(0.06));
        expect(_log, ['Sub two']);
        expect(
          fired! - (_n(lift, 't') - t0),
          moreOrLessEquals(_n(evt, 't') - _n(lift, 't'), epsilon: 0.008),
        );
      },
    );
  });

  group('live resize (device frames)', () {
    test('added rows grow the menu, a removed one shrinks it', () {
      var count = 3;
      final content = MorphMenuContent(onChanged: ({required bool animate}) {});
      List<MorphMenuEntry> entries() => [
        for (var i = 0; i < count; i++)
          MorphMenuItem(title: 'Row $i', keepsMenuOpen: true),
      ];
      content.entries = entries();
      final motion = MorphMenuMotion(
        button: Rect.fromCenter(
          center: const Offset(201, 150),
          width: 48,
          height: 48,
        ),
        layout: content.root,
        bounds: const Size(402, 874),
        padding: const EdgeInsets.only(top: 62, bottom: 34),
      );
      morphConnectMenu(motion, content);
      final rows = _rows('mm-resize');
      final t0 = _n(
        rows.firstWhere(
          (Map<String, Object?> r) => r['k'] == 'touch' && r['phase'] == 3,
        ),
        't',
      );
      motion.open(0, sourceScale: 1);
      motion.advance(1);
      final errors = <double>[];
      final segments = <int, List<double>>{};
      final start = motion.menuRect.height;
      double? deviceStart;
      var touches = 0;
      for (final row in rows) {
        final t = _n(row, 't') - t0;
        if (t <= 1) continue;
        if (row['k'] == 'evt') {
          touches++;
          count += row['title'] == 'Add row' ? 1 : -1;
          content.entries = entries();
          motion.updateLayout(t);
        } else if (row['k'] == 'touch' && touches == 3) {
          break;
        } else if (row['k'] == 'frame' && row['cls'] == '_UIContextMenuView') {
          motion.advance(t);
          deviceStart ??= _n(row, 'h');
          errors.add(
            motion.menuRect.height - start - (_n(row, 'h') - deviceStart),
          );
          (segments[touches] ??= []).add(errors.last);
        }
      }
      expect(errors.length, greaterThan(100));
      expect(_rms(segments[1]!), lessThan(0.5), reason: 'first row added');
      expect(_rms(segments[3]!), lessThan(0.3), reason: 'row removed');
      expect(
        _rms(segments[2]!),
        lessThan(6),
        reason:
            'the second add started 0.02 s earlier after its action on the '
            'device than the first: the delay jitters with the display link',
      );
    });
  });
}
