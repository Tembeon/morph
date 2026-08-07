import 'dart:ui';

import 'package:morph/src/liquid_field.dart';

/// The fixed scenes shared by the geometry snapshot test and its dump
/// helper. Chosen to cover the topologies that matter: a fused pair, a
/// neck at rip distance, a ring with a hole, a budgeted mega-cluster.
final Map<String, LiquidField> goldenScenes = <String, LiquidField>{
  'fusedPair': const LiquidField(<LiquidShape>[
    LiquidBox(.fromLTWH(20, 30, 140, 80), radius: 18),
    LiquidBox(.fromLTWH(170, 60, 90, 50), radius: 16),
  ], k: 30),
  'neckAtRipDistance': const LiquidField(<LiquidShape>[
    LiquidBox(.fromLTWH(0, 0, 100, 60), radius: 12),
    LiquidBox(.fromLTWH(118, 0, 100, 60), radius: 12),
  ], k: 24),
  'ringWithHole': LiquidField(<LiquidShape>[
    LiquidBox(
      .fromCenter(center: const Offset(20, 20), width: 44, height: 44),
      radius: 14,
    ),
    LiquidBox(
      .fromCenter(center: const Offset(220, 20), width: 44, height: 44),
      radius: 14,
    ),
    LiquidBox(
      .fromCenter(center: const Offset(120, 180), width: 44, height: 44),
      radius: 14,
    ),
    const LiquidBridge(Offset(20, 20), Offset(220, 20), radius: 10),
    const LiquidBridge(Offset(220, 20), Offset(120, 180), radius: 10),
    const LiquidBridge(Offset(20, 20), Offset(120, 180), radius: 10),
  ], k: 10),
  'budgetedGrid': LiquidField(<LiquidShape>[
    for (int i = 0; i < 24; i++)
      LiquidBox(
        .fromLTWH((i % 6) * 115.0, (i ~/ 6) * 95.0, 100, 70),
        radius: 16,
      ),
  ], k: 22),
};
