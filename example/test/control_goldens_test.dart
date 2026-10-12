import 'dart:convert';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

import '../integration_test/support/control_matrix.dart';

/// Every cell of the control matrix, on the flat and fake tiers, as a
/// sequence of frame hashes at fixed steps of fake time, against the
/// hashes recorded in test/fixtures/control_goldens.json: a change that
/// must keep pixels (a control moved onto its own render object) proves it
/// here.
///
///     flutter test test/control_goldens_test.dart
///     flutter test --dart-define=GOLDENS_UPDATE=true \
///       test/control_goldens_test.dart
///
/// The second line records the fixture; record it on the commit the change
/// starts from. A cell that differs names its first differing frame.
void main() => _main();

const bool _update = bool.fromEnvironment('GOLDENS_UPDATE');

final File _fixture = File('test/fixtures/control_goldens.json');

void _main() {
  setUpAll(() async {
    // No Impeller on the host: the renderer reports its fake fallback once.
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {};
    try {
      await MorphGlassRenderer.precache();
    } finally {
      FlutterError.onError = previous;
    }
  });

  final recorded = <String, List<String>>{};
  tearDownAll(() {
    if (!_update) return;
    final entries = recorded.entries.toList();
    entries.sort((a, b) => a.key.compareTo(b.key));
    final sorted = Map.fromEntries(entries);
    _fixture.parent.createSync(recursive: true);
    _fixture.writeAsStringSync(
      '${const JsonEncoder.withIndent(' ').convert(sorted)}\n',
    );
  });

  for (final tier in ['flat', 'fake']) {
    testWidgets('control frames on the $tier tier', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final previousTier = GalleryGlassSettings.initialTier;
      GalleryGlassSettings.initialTier = tier;
      addTearDown(() => GalleryGlassSettings.initialTier = previousTier);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: const GalleryApp(key: ValueKey('matrix'), home: MatrixStage()),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final driver = _HashingDriver(tester, boundary);
      await runControlMatrix(driver, (String scene) => true);
      final golden = _fixture.existsSync()
          ? (jsonDecode(_fixture.readAsStringSync()) as Map<String, Object?>)
          : const <String, Object?>{};
      final failures = <String>[];
      for (final MapEntry(:key, :value) in driver.frames.entries) {
        final name = '$tier $key';
        recorded[name] = value;
        if (_update) continue;
        final expected = (golden[name] as List<Object?>?)?.cast<String>();
        if (expected == null) {
          failures.add('$name: no recorded frames');
          continue;
        }
        final n = value.length < expected.length
            ? value.length
            : expected.length;
        var at = 0;
        while (at < n && value[at] == expected[at]) {
          at++;
        }
        if (at < n || value.length != expected.length) {
          failures.add(
            '$name: frame $at of ${expected.length} differs '
            '(${value.length} taken)',
          );
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }
}

/// Drives the matrix like the audit, hashing a frame every third pump of
/// 16 ms fake time while a cell runs.
class _HashingDriver implements MatrixDriver {
  _HashingDriver(this.tester, this.boundary);

  @override
  final WidgetTester tester;

  final GlobalKey boundary;
  final Map<String, List<String>> frames = {};
  List<String>? _cell;
  int _pumps = 0;
  int _pointer = 1;

  Future<void> _pump([Duration step = const Duration(milliseconds: 16)]) async {
    await tester.pump(step);
    final cell = _cell;
    if (cell == null || _pumps++ % 3 != 0) return;
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = (await tester.runAsync(render.toImage))!;
    final bytes = (await tester.runAsync(image.toByteData))!;
    image.dispose();
    cell.add(_hash(bytes.buffer.asUint8List()));
  }

  static String _hash(List<int> bytes) {
    // FNV-1a, 64 bit in two halves for the web-safe int range.
    var lo = 0x811c9dc5;
    var hi = 0x01000193;
    for (final b in bytes) {
      lo = ((lo ^ b) * 0x01000193) & 0xFFFFFFFF;
      hi = ((hi ^ lo) * 0x01000193) & 0xFFFFFFFF;
    }
    return '${hi.toRadixString(16)}${lo.toRadixString(16)}';
  }

  @override
  Future<void> settle([int ms = 900]) async {
    for (var t = 0; t < ms; t += 16) {
      await _pump();
    }
  }

  @override
  Future<void> finger(
    Offset from,
    List<Offset> path, {
    Duration holdBefore = const Duration(milliseconds: 16),
  }) async {
    final gesture = await tester.createGesture(pointer: _pointer++);
    await gesture.down(from);
    await _pump(holdBefore);
    for (final p in path) {
      await gesture.moveTo(p);
      await _pump(const Duration(milliseconds: 8));
    }
    await gesture.up();
    await _pump();
  }

  @override
  Future<void> tap(Offset at) =>
      finger(at, const [], holdBefore: const Duration(milliseconds: 60));

  @override
  Future<void> measure(String name, Future<void> Function() body) async {
    final cell = _cell = frames[name] = [];
    _pumps = 0;
    await body();
    _cell = null;
    expect(cell, isNotEmpty);
  }
}
