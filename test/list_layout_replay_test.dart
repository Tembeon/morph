import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';

const _dir = 'test/fixtures/ios27/list';

/// The tolerance of a resting frame against a UIKit layout read, in
/// points: the layout replays of navigation_title_layout_test,
/// date_picker_test and the alert popover placement hold resting frames
/// to it.
const double _tolerance = 0.5;

/// One view of a dumped UIKit view tree: its class, its frame in window
/// points and the line it was read from.
class _Node {
  _Node(this.cls, this.frame, this.line);

  final String cls;
  final Rect frame;
  final String line;
  final List<_Node> children = [];

  bool get hidden => line.contains(' HIDDEN');

  double get alpha =>
      double.parse(RegExp(r' a=([0-9.]+)').firstMatch(line)!.group(1)!);

  String? get text => RegExp(r' text=(.*?) font=').firstMatch(line)?.group(1);

  double get fontSize =>
      double.parse(RegExp(r' fs=([0-9.]+)').firstMatch(line)!.group(1)!);

  String? get background => RegExp(r' bg=(\[.*?\])').firstMatch(line)?.group(1);

  Iterable<_Node> get descendants sync* {
    for (final child in children) {
      yield child;
      yield* child.descendants;
    }
  }

  _Node? find(String cls) {
    for (final node in descendants) {
      if (node.cls == cls) return node;
    }
    return null;
  }
}

/// A list-tree dump (manifest.txt): the resolved selected-cell color and
/// the window's view tree, one view per line, indented two spaces per
/// level, `Class x,y WxH` then its attributes.
({_Node root, String selected}) _parse(String path) {
  final view = RegExp(
    r'^( *)(\S+) (-?[0-9.]+),(-?[0-9.]+) ([0-9.]+)x([0-9.]+)',
  );
  final lines = File(path).readAsLinesSync();
  final selected = RegExp(r'^bgconfig selected grouped=(\[.*?\])')
      .firstMatch(lines.firstWhere((l) => l.startsWith('bgconfig selected')))!
      .group(1)!;
  final stack = <(int, _Node)>[];
  _Node? root;
  for (final text in lines) {
    final m = view.firstMatch(text);
    if (m == null) continue;
    final depth = m.group(1)!.length ~/ 2;
    final node = _Node(
      m.group(2)!,
      Rect.fromLTWH(
        double.parse(m.group(3)!),
        double.parse(m.group(4)!),
        double.parse(m.group(5)!),
        double.parse(m.group(6)!),
      ),
      text,
    );
    while (stack.isNotEmpty && stack.last.$1 >= depth) {
      stack.removeLast();
    }
    if (stack.isEmpty) {
      root = node;
    } else {
      stack.last.$2.children.add(node);
    }
    stack.add((depth, node));
  }
  return (root: root!, selected: selected);
}

/// A recorded cell and what it shows.
class _Cell {
  _Cell(this.node, String selectedColor) {
    final labels = [
      for (final n in node.descendants)
        if (n.cls == 'UILabel') n,
    ];
    labels.sort((_Node a, _Node b) => a.frame.left.compareTo(b.frame.left));
    title = labels.first;
    final rest = labels.skip(1);
    subtitle = rest
        .where((_Node l) => l.frame.top > title.frame.bottom - 1)
        .firstOrNull;
    detail = rest
        .where((_Node l) => (l.frame.top - title.frame.top).abs() < 1)
        .firstOrNull;
    selected = node.descendants.any(
      (_Node n) => n.cls == 'UIView' && n.background == selectedColor,
    );
  }

  final _Node node;
  late final _Node title;
  late final _Node? subtitle;
  late final _Node? detail;

  /// Whether the cell shows the selected background.
  late final bool selected;

  Rect get frame => node.frame;
  String get name => title.text!;
  _Node? get accessory => node.find('_UITableCellAccessoryButton');
  _Node? get toggle => node.find('UISwitch');
  _Node? get image => node.find('_UIListContentImageView');
  _Node get separator => node.find('_UITableViewCellSeparatorView')!;

  /// The disclosure chevron is a 10.33 x 14 image, the checkmark 19 x
  /// 17.33.
  bool get chevron => accessory != null && accessory!.frame.width < 15;
  bool get checkmark => accessory != null && !chevron;
}

/// A recorded section: its header and footer labels and its cells.
typedef _Section = ({_Node? header, _Node? footer, List<_Cell> cells});

/// A recorded table: where its content starts and its visible sections,
/// top to bottom. Cells that touch share a card; a header or footer view
/// belongs to the card it touches.
({double top, List<_Section> sections}) _table(String appearance) {
  final (:root, :selected) = _parse('$_dir/list-tree-$appearance.txt');
  final cells = [
    for (final n in root.descendants)
      if (n.cls == 'UITableViewCell' && !n.hidden) _Cell(n, selected),
  ];
  cells.sort((_Cell a, _Cell b) => a.frame.top.compareTo(b.frame.top));
  final labels = [
    for (final n in root.descendants)
      if (n.cls == 'UITableViewHeaderFooterView')
        (view: n.frame, label: n.find('_UITableViewHeaderFooterViewLabel')!),
  ];
  final cards = <List<_Cell>>[];
  for (final cell in cells) {
    if (cards.isNotEmpty &&
        (cell.frame.top - cards.last.last.frame.bottom).abs() < 0.5) {
      cards.last.add(cell);
    } else {
      cards.add([cell]);
    }
  }
  _Node? ending(double y) => labels
      .where((l) => (l.view.bottom - y).abs() < 0.5)
      .map((l) => l.label)
      .firstOrNull;
  _Node? starting(double y) => labels
      .where((l) => (l.view.top - y).abs() < 0.5)
      .map((l) => l.label)
      .firstOrNull;
  return (
    top: root.descendants
        .firstWhere((_Node n) => n.cls == 'UITableViewWrapperView')
        .frame
        .top,
    sections: [
      for (final card in cards)
        (
          header: ending(card.first.frame.top),
          footer: starting(card.last.frame.bottom),
          cells: card,
        ),
    ],
  );
}

/// The text of a recorded label as the replay draws it. SF Pro is not in
/// the host test: the text gets the line box UIKit laid out for it (the
/// label's height, a whole number of pixels the dump prints to two
/// decimals), which the engine rounds to whole points as it rounds SF
/// Pro's on the device. The host font draws every glyph one em wide, so
/// the recorded strings, one line each on the device, are kept to one
/// line.
Widget _text(_Node label) => Text(
  label.text!,
  maxLines: 1,
  softWrap: false,
  style: TextStyle(
    height: (label.frame.height * 3).roundToDouble() / 3 / label.fontSize,
  ),
);

Key _rowKey(_Cell cell) => ValueKey<String>('row ${cell.name}');

Widget _section(_Section section) {
  final header = section.header;
  final footer = section.footer;
  return MorphListSection(
    header: header == null ? null : _text(header),
    footer: footer == null ? null : _text(footer),
    children: [
      for (final cell in section.cells)
        MorphListRow(
          key: _rowKey(cell),
          title: _text(cell.title),
          subtitle: cell.subtitle == null ? null : _text(cell.subtitle!),
          detail: cell.detail == null ? null : _text(cell.detail!),
          leading: cell.image == null ? null : const Icon(Icons.settings),
          trailing: cell.toggle == null
              ? null
              : MorphSwitch(value: true, onChanged: (_) {}),
          accessory: cell.chevron
              ? .disclosureIndicator
              : cell.checkmark
              ? .checkmark
              : null,
          onTap: () {},
        ),
    ],
  );
}

Future<List<_Section>> _pump(WidgetTester tester, String appearance) async {
  final table = _table(appearance);
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final brightness = appearance == 'dark' ? Brightness.dark : Brightness.light;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      builder: (BuildContext context, Widget? child) => MorphTheme(
        data: MorphThemeData(brightness: brightness),
        child: child!,
      ),
      home: ListView(
        padding: EdgeInsets.only(top: table.top),
        children: [for (final s in table.sections) _section(s)],
      ),
    ),
  );
  await tester.pumpAndSettle();
  return table.sections;
}

Rect _row(WidgetTester tester, _Cell cell) =>
    tester.getRect(find.byKey(_rowKey(cell)));

Rect _label(WidgetTester tester, _Node label) =>
    tester.getRect(find.text(label.text!));

/// The separator a row paints, in global coordinates, or null.
Rect? _separator(WidgetTester tester, _Cell cell) {
  final painters = find.descendant(
    of: find.byKey(_rowKey(cell)),
    matching: find.byWidgetPredicate(
      (Widget w) =>
          w is CustomPaint &&
          '${w.foregroundPainter.runtimeType}' == '_SeparatorPainter',
    ),
  );
  if (painters.evaluate().isEmpty) return null;
  final box = tester.renderObject<RenderCustomPaint>(painters.first);
  final canvas = TestRecordingCanvas();
  box.foregroundPainter!.paint(canvas, box.size);
  final rect =
      canvas.invocations
              .singleWhere((i) => i.invocation.memberName == #drawRect)
              .invocation
              .positionalArguments
              .first
          as Rect;
  return rect.shift(box.localToGlobal(Offset.zero));
}

/// Every compared quantity's |morph - UIKit|, so a replay fails on all
/// its misses at once and reports their max and rms.
class _Errors {
  final List<(String, double)> all = [];

  void add(String name, double morph, double uikit) =>
      all.add((name, (morph - uikit).abs()));

  /// Compares [morph] and [uikit] relative to their own origins.
  void rect(
    String name,
    Rect morph,
    Rect uikit, {
    Offset morphOrigin = Offset.zero,
    Offset uikitOrigin = Offset.zero,
  }) {
    final m = morph.shift(-morphOrigin);
    final u = uikit.shift(-uikitOrigin);
    add('$name left', m.left, u.left);
    add('$name top', m.top, u.top);
    add('$name width', m.width, u.width);
    add('$name height', m.height, u.height);
  }

  void check() {
    final max = all.map(((String, double) e) => e.$2).reduce(math.max);
    final rms = math.sqrt(
      all.fold(0.0, (double s, (String, double) e) => s + e.$2 * e.$2) /
          all.length,
    );
    expect(
      [
        for (final (name, e) in all)
          if (e > _tolerance) '$name ${e.toStringAsFixed(2)}',
      ],
      isEmpty,
      reason:
          'max ${max.toStringAsFixed(3)}, rms ${rms.toStringAsFixed(3)} '
          'over ${all.length}',
    );
  }
}

void main() {
  for (final appearance in ['light', 'dark']) {
    testWidgets('section headers and footers stand off their cards by the '
        'UIKit gaps ($appearance)', (tester) async {
      final sections = await _pump(tester, appearance);
      final errors = _Errors();
      var morphEnd = _table(appearance).top;
      var uikitEnd = morphEnd;
      for (final section in sections) {
        final morphTop = _row(tester, section.cells.first).top;
        final uikitTop = section.cells.first.frame.top;
        final morphBottom = _row(tester, section.cells.last).bottom;
        final uikitBottom = section.cells.last.frame.bottom;
        final name = section.cells.first.name;
        errors.add(
          '$name card after the block above',
          morphTop - morphEnd,
          uikitTop - uikitEnd,
        );
        final header = section.header;
        if (header != null) {
          final label = _label(tester, header);
          errors.add('${header.text} left', label.left, header.frame.left);
          errors.add(
            '${header.text} below the block above',
            label.top - morphEnd,
            header.frame.top - uikitEnd,
          );
          errors.add(
            '${header.text} above its card',
            morphTop - label.bottom,
            uikitTop - header.frame.bottom,
          );
        }
        morphEnd = morphBottom;
        uikitEnd = uikitBottom;
        final footer = section.footer;
        if (footer != null) {
          final label = _label(tester, footer);
          errors.add('${footer.text} left', label.left, footer.frame.left);
          errors.add(
            '${footer.text} below its card',
            label.top - morphBottom,
            footer.frame.top - uikitBottom,
          );
          morphEnd = label.bottom;
          uikitEnd = footer.frame.bottom;
        }
      }
      errors.check();
    });

    testWidgets('rows keep the UIKit frames, text edges, accessories and '
        'separators on their card ($appearance)', (tester) async {
      final sections = await _pump(tester, appearance);
      final errors = _Errors();
      for (final cell in sections.expand((_Section s) => s.cells)) {
        if (cell.toggle != null) continue;
        final name = cell.name;
        final row = _row(tester, cell);
        errors.add('$name left', row.left, cell.frame.left);
        errors.add('$name width', row.width, cell.frame.width);
        errors.add('$name height', row.height, cell.frame.height);
        errors.add(
          '$name title start',
          _label(tester, cell.title).left - row.left,
          cell.title.frame.left - cell.frame.left,
        );
        final detail = cell.detail;
        if (detail != null) {
          errors.add(
            '$name detail end',
            _label(tester, detail).right - row.left,
            detail.frame.right - cell.frame.left,
          );
        }
        final image = cell.image;
        if (image != null) {
          final icon = tester.getCenter(find.byIcon(Icons.settings));
          errors.add(
            '$name symbol center x',
            icon.dx - row.left,
            image.frame.center.dx - cell.frame.left,
          );
          errors.add(
            '$name symbol center y',
            icon.dy - row.top,
            image.frame.center.dy - cell.frame.top,
          );
        }
        if (cell.chevron) {
          errors.rect(
            '$name chevron',
            tester.getRect(
              find.descendant(
                of: find.byKey(_rowKey(cell)),
                matching: find.byWidgetPredicate(
                  (Widget w) => '${w.runtimeType}' == '_Chevron',
                ),
              ),
            ),
            cell.accessory!.frame,
            morphOrigin: row.topLeft,
            uikitOrigin: cell.frame.topLeft,
          );
        }
        // UIKit hides the separator of a selected cell; a morph row keeps
        // no selection (lists.md), so only its card position is compared.
        if (cell.selected) continue;
        final separator = _separator(tester, cell);
        if (cell.separator.alpha == 0) {
          expect(separator, isNull, reason: '$name draws no separator');
        } else {
          errors.rect(
            '$name separator',
            separator!,
            cell.separator.frame,
            morphOrigin: row.topLeft,
            uikitOrigin: cell.frame.topLeft,
          );
        }
      }
      errors.check();
    });

    group('switch row', () {
      testWidgets('a row with a switch keeps the UIKit row height and its '
          'switch 20 points from the card edge ($appearance)', (tester) async {
        final sections = await _pump(tester, appearance);
        final errors = _Errors();
        for (final cell in sections.expand((_Section s) => s.cells)) {
          final toggle = cell.toggle;
          if (toggle == null) continue;
          final row = _row(tester, cell);
          errors.add('${cell.name} height', row.height, cell.frame.height);
          errors.rect(
            '${cell.name} switch',
            tester.getRect(
              find.descendant(
                of: find.byKey(_rowKey(cell)),
                matching: find.byType(MorphSwitch),
              ),
            ),
            toggle.frame,
            morphOrigin: row.topLeft,
            uikitOrigin: cell.frame.topLeft,
          );
        }
        errors.check();
      });
    });

    group('whole list', () {
      testWidgets('a whole inset grouped list lands on the UIKit frames '
          '($appearance)', (tester) async {
        final sections = await _pump(tester, appearance);
        final errors = _Errors();
        for (final section in sections) {
          for (final label in [?section.header, ?section.footer]) {
            errors.add(
              '${label.text} top',
              _label(tester, label).top,
              label.frame.top,
            );
          }
          for (final cell in section.cells) {
            errors.rect(cell.name, _row(tester, cell), cell.frame);
          }
        }
        errors.check();
      });
    });
  }
}
