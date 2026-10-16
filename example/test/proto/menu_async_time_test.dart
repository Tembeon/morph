import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/motion.dart';

MorphMenuMotion _motion() => MorphMenuMotion(
  button: const Rect.fromLTWH(24, 80, 44, 44),
  bounds: const Size(402, 874),
  itemCount: 3,
);

void main() {
  test(
    'negative control: backdating approval cannot replay integrated kicks',
    () {
      final continuous = _motion();
      final delayed = _motion();
      continuous.open(0);
      delayed.open(0);
      continuous.advance(1);
      continuous.close(1);
      continuous.advance(2);
      delayed.advance(2);
      delayed.close(1);
      continuous.advance(2.01);
      delayed.advance(2.01);
      expect(continuous.progress, closeTo(delayed.progress, 1e-9));
      expect((continuous.menuKick - delayed.menuKick).abs(), greaterThan(1));
      expect(delayed.time, 2.01);
      // ignore: avoid_print
      print(
        'P2_BACKDATE ${jsonEncode({'requestedAt': 1, 'approvedAfter': 2, 'sampledAt': 2.01, 'continuousKick': continuous.menuKick, 'backdatedKick': delayed.menuKick, 'continuousProgress': continuous.progress, 'backdatedProgress': delayed.progress})}',
      );
    },
  );
}
