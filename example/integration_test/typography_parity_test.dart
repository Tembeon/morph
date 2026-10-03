import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// UIKit's label widths on iOS 27.0.1 (iPhone 16 Pro) for the texts of
/// the probe's `fonts` scene (tool/ios_reference/Sources/Typography.swift),
/// in points, by the role whose size and weight UIKit used.
const _native = <(String, TextStyle, String, double)>[
  ('segment', MorphTypography.segment, 'Unread messages', 108.577),
  ('segment', MorphTypography.segment, 'VIP', 20.268),
  ('segment', MorphTypography.segment, 'Day', 23.194),
  ('segmentSelected', MorphTypography.segmentSelected, 'All', 15.787),
  ('segmentSelected', MorphTypography.segmentSelected, 'Night', 33.702),
  ('tabLabel', MorphTypography.tabLabel, 'Settings', 41.145),
  ('tabLabel', MorphTypography.tabLabel, 'Library', 34.824),
  ('tabLabelSelected', MorphTypography.tabLabelSelected, 'Settings', 42.034),
  ('tabLabelSelected', MorphTypography.tabLabelSelected, 'Library', 35.623),
  ('button', MorphTypography.button, 'Glass button', 96.156),
  ('button', MorphTypography.button, 'Sort by name', 101.22),
  ('barButton', MorphTypography.barButton, 'Edit', 30.17),
  ('barButton', MorphTypography.barButton, 'Select', 49.137),
  ('barButtonProminent', MorphTypography.barButtonProminent, 'Done', 41.622),
  ('menuItem', MorphTypography.menuItem, 'Rename', 61.783),
  ('title', MorphTypography.title, 'Settings', 66.411),
  ('largeTitle', MorphTypography.largeTitle, 'Settings', 132.962),
  ('alertTitle', MorphTypography.alertTitle, 'Delete message?', 135.896),
  (
    'alertMessage',
    MorphTypography.alertMessage,
    'This cannot be undone.',
    161.016,
  ),
  ('alertAction', MorphTypography.alertAction, 'Cancel', 53.689),
  ('searchField', MorphTypography.searchField, 'Search', 54.53),
  (
    'datePickerTitle',
    MorphTypography.datePickerTitle,
    'September 2026',
    134.564,
  ),
  ('datePickerWeekday', MorphTypography.datePickerWeekday, 'MON', 31.415),
  ('datePickerDaySelected', MorphTypography.datePickerDaySelected, '14', 22.09),
  (
    'datePickerCompact',
    MorphTypography.datePickerCompact,
    'Oct 3, 2026',
    90.96,
  ),
];

/// Where the device run leaves its lines (`<app tmp>`, pulled with
/// devicectl - `flutter drive` needs Rosetta's iproxy on this Mac).
final File _report = File('${Directory.systemTemp.path}/typography_parity.txt');

double _width(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  );
  painter.layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Width parity of the resolved text styles with UIKit, on an Apple
/// device only (elsewhere the system font is not SF Pro).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('resolved roles match UIKit label widths within 1 pt', (
    tester,
  ) async {
    if (!MorphTypography.usesAppleSystemFont) return;
    final misses = <String>[];
    final lines = <String>[];
    for (final (role, style, text, native) in _native) {
      final ours = _width(text, MorphTypography.resolve(style));
      final plain = _width(text, style);
      final line =
          'PARITY $role "$text" native ${native.toStringAsFixed(2)} '
          'ours ${ours.toStringAsFixed(2)} '
          '(${(ours - native).toStringAsFixed(2)}) '
          'unresolved ${plain.toStringAsFixed(2)} '
          '(${(plain - native).toStringAsFixed(2)})';
      debugPrint(line);
      lines.add(line);
      if ((ours - native).abs() > 1) misses.add(line);
    }
    _report.writeAsStringSync('${lines.join('\n')}\n');
    expect(misses, isEmpty);
  });

  testWidgets('a content-sized segment label renders at the native width', (
    tester,
  ) async {
    if (!MorphTypography.usesAppleSystemFont) return;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            child: MorphSegmentedControl(
              segments: const ['All', 'Unread messages', 'VIP'],
              selected: 0,
              sizeByContent: true,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    final unread = tester.getSize(find.text('Unread messages')).width;
    final all = tester.getSize(find.text('All')).width;
    final line = 'PARITY widget "Unread messages" $unread "All" $all';
    debugPrint(line);
    _report.writeAsStringSync('$line\n', mode: FileMode.append);
    expect(unread, closeTo(108.577, 1));
    expect(all, closeTo(15.787, 1));
  });
}
