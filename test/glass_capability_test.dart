import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/liquid_capability.dart';
import 'package:morph/widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('G1 unsupported GPU resolves to frosted and logs once', () async {
    final messages = <String?>[];
    var loads = 0;
    final capability = LiquidCapability(
      load: () async {
        loads++;
        throw StateError('GPU disabled');
      },
      log: (message, {wrapWidth}) => messages.add(message),
    );
    expect(capability.value, isFalse);
    await Future.wait([capability.precache(), capability.precache()]);
    await capability.precache();
    expect(capability.value, isFalse);
    expect(loads, 1);
    expect(messages.single, contains('using frosted'));
    await MorphGlassRenderer.precache();
    expect(MorphGlassRenderer.liquidAvailable, isFalse);
    expect(const MorphGlassRenderer().effectiveTier, MorphGlassTier.frosted);
    capability.dispose();
  });

  test(
    'G1 liquid becomes available only after successful initialization',
    () async {
      final capability = LiquidCapability(load: () async {});
      expect(capability.value, isFalse);
      await capability.precache();
      expect(capability.value, isTrue);
      capability.dispose();
    },
  );
}
