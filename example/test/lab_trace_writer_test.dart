import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/lab/lab_trace_writer.dart';

void main() {
  test('rows arriving during a blocked flush survive in order', () async {
    final received = <int>[];
    final release = Completer<void>();
    final sink = IOSink(_DelayedConsumer(release.future, received));
    final writer = LabTraceWriter(sink);
    writer.add({'gesture': 0});
    final first = writer.flush();
    var firstCompleted = false;
    unawaited(first.then((_) => firstCompleted = true));
    await Future<void>.delayed(Duration.zero);
    expect(firstCompleted, isFalse);
    for (var gesture = 1; gesture < 100; gesture++) {
      writer.add({'gesture': gesture});
    }
    final second = writer.flush();
    writer.add({'gesture': 100});
    final close = writer.close();
    release.complete();
    await Future.wait([first, second, close]);
    await sink.close();
    final rows = utf8.decode(received).trim().split('\n');
    expect(
      rows.map((row) => (jsonDecode(row) as Map<String, Object?>)['gesture']),
      orderedEquals(List<int>.generate(101, (index) => index)),
    );
    expect(() => writer.add({'gesture': 101}), throwsStateError);
  });
}

class _DelayedConsumer implements StreamConsumer<List<int>> {
  _DelayedConsumer(this.release, this.received);

  final Future<void> release;
  final List<int> received;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await release;
    await for (final bytes in stream) {
      received.addAll(bytes);
    }
  }

  @override
  Future<void> close() async {}
}
