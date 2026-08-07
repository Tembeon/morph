/// Instrument-only scene definitions, shared by the JIT microbenchmarks
/// (benchmark/liquid_benchmark_test.dart) and the release benchmark
/// mode of the example app (--dart-define=MORPH_BENCH=true): one source
/// of truth, so the two harnesses can never measure different scenes.
/// Not exported from the package.
library;

import 'package:morph/src/liquid_field.dart';

/// A button fused to a card - the typical static case.
const LiquidField benchFusedPair = LiquidField(<LiquidShape>[
  LiquidBox(.fromLTWH(24, 60, 200, 100), radius: 22),
  LiquidBox(.fromLTWH(232, 84, 84, 52), radius: 18),
], k: 24);

/// Six pieces in two far-apart clusters on a large canvas - the
/// cluster-splitting stress.
const LiquidField benchSandboxSpread = LiquidField(<LiquidShape>[
  LiquidBox(.fromLTWH(40, 40, 180, 100), radius: 20),
  LiquidBox(.fromLTWH(230, 70, 90, 44), radius: 16),
  LiquidBox(.fromLTWH(120, 160, 70, 70), radius: 35),
  LiquidBox(.fromLTWH(640, 380, 180, 100), radius: 20),
  LiquidBox(.fromLTWH(830, 420, 90, 44), radius: 16),
  LiquidBox(.fromLTWH(700, 300, 70, 70), radius: 35),
], k: 18);

/// Two fused neighbors plus a mid-flight blob far away - the worst
/// frame of a cross-screen flight at the field level.
const LiquidField benchFlightFar = LiquidField(<LiquidShape>[
  LiquidBox(.fromLTWH(40, 300, 120, 70), radius: 16),
  LiquidBox(.fromLTWH(170, 310, 110, 50), radius: 18),
  LiquidBox(.fromLTWH(620, 60, 300, 250), radius: 24),
], k: 24);

/// Twelve pieces across a large canvas.
final LiquidField benchManyPieces = LiquidField(<LiquidShape>[
  for (int i = 0; i < 12; i++)
    LiquidBox(
      .fromLTWH(60.0 + (i % 4) * 220, 60.0 + (i ~/ 4) * 180, 140, 80),
      radius: 18,
    ),
], k: 16);

/// The stress-lab worst case: 64 pieces fused into one screen-wide
/// cluster. Measure with the default eval budget (grid coarsens to
/// fit) and unbounded to see what the budget buys.
final LiquidField benchMegaCluster64 = LiquidField(<LiquidShape>[
  for (int i = 0; i < 64; i++)
    LiquidBox(.fromLTWH((i % 8) * 105.0, (i ~/ 8) * 85.0, 95, 70), radius: 16),
], k: 24);

/// The animated-frame scenario: one piece moves, the rest of the scene
/// (two more clusters) is static. A cached tracer re-traces only the
/// moving cluster; the pure function re-traces everything.
LiquidField benchOneMovingFrame(int frame) {
  final double dx = (frame % 48).toDouble();
  return LiquidField(<LiquidShape>[
    LiquidBox(.fromLTWH(40 + dx, 40, 120, 70), radius: 16),
    const LiquidBox(.fromLTWH(200, 60, 90, 50), radius: 14),
    const LiquidBox(.fromLTWH(640, 380, 180, 100), radius: 20),
    const LiquidBox(.fromLTWH(830, 420, 90, 44), radius: 16),
    const LiquidBox(.fromLTWH(120, 420, 100, 70), radius: 18),
  ], k: 18);
}
