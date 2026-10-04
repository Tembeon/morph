import 'package:flutter_test/flutter_test.dart';

Future<void> replayLabTouches(
  WidgetTester tester,
  List<Map<String, Object?>> rows,
) async {
  final touches = rows.where((row) => row['k'] == 'touch').toList();
  final gestures = <String, TestGesture>{};
  final ids = <String, int>{};
  double? origin;
  var elapsed = 0.0;
  for (final row in touches) {
    final time = (row['t']! as num).toDouble();
    origin ??= time;
    final next = time - origin;
    if (next < elapsed) throw StateError('Touch times must not go backwards');
    await tester.pump(Duration(microseconds: ((next - elapsed) * 1e6).round()));
    elapsed = next;
    final pointer = row['pointer'] as String? ?? '0';
    final timestamp = Duration(microseconds: (next * 1e6).round());
    final point = Offset(
      (row['x']! as num).toDouble(),
      (row['y']! as num).toDouble(),
    );
    switch (row['phase']) {
      case 0:
        if (gestures.containsKey(pointer)) {
          throw StateError('Pointer already down: $pointer');
        }
        ids.putIfAbsent(pointer, () => ids.length + 1);
        final gesture = await tester.createGesture(pointer: ids[pointer]);
        gestures[pointer] = gesture;
        await gesture.down(point, timeStamp: timestamp);
      case 1:
      case 2:
        await gestures[pointer]!.moveTo(point, timeStamp: timestamp);
      case 3:
        await gestures.remove(pointer)!.up(timeStamp: timestamp);
      case 4:
        await gestures.remove(pointer)!.cancel(timeStamp: timestamp);
    }
  }
  if (gestures.isNotEmpty) throw StateError('Trace ends with active pointers');
}
