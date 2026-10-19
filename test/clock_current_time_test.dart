import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/clock.dart';

class _Reader extends StatefulWidget {
  const _Reader({super.key});

  @override
  State<_Reader> createState() => _ReaderState();
}

class _ReaderState extends State<_Reader>
    with SingleTickerProviderStateMixin<_Reader>, MorphClock<_Reader> {
  bool running = true;

  @override
  void advanceMotion(double t) {}

  @override
  bool get motionSettled => !running;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  for (final writerFirst in [true, false]) {
    testWidgets('input from another ticker reads the current frame, '
        '${writerFirst ? 'writer' : 'reader'} ticks first', (tester) async {
      final key = GlobalKey<_ReaderState>();
      final reads = <({double clock, double current})>[];
      final writer = const TestVSync().createTicker((_) {
        final reader = key.currentState;
        if (reader == null) return;
        reads.add((clock: reader.clock, current: reader.currentTime));
      });
      addTearDown(writer.dispose);
      if (writerFirst) unawaited(writer.start());
      await tester.pumpWidget(_Reader(key: key));
      key.currentState!.wake();
      if (!writerFirst) unawaited(writer.start());
      final sampled = <double>[];
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(microseconds: 8333));
        sampled.add(key.currentState!.clock);
      }
      for (var i = 4; i < sampled.length; i++) {
        final read = reads[reads.length - sampled.length + i];
        expect(read.current, closeTo(sampled[i], 1e-5));
        expect(
          read.clock,
          closeTo(writerFirst ? sampled[i - 1] : sampled[i], 1e-9),
          reason: 'the last tick time depends on the order',
        );
      }
      key.currentState!.running = false;
      writer.stop();
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }
}
