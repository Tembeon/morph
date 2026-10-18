import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/haptics.dart';
import 'package:morph/widgets.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> calls;

  setUp(() {
    calls = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add(call.arguments as String? ?? 'vibrate');
        }
        return null;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  Future<BuildContext> pump(WidgetTester tester, {bool? haptics}) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MorphTheme(
        data: MorphThemeData(haptics: haptics ?? true),
        child: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('each haptic plays its declared Flutter feedback', (
    tester,
  ) async {
    final context = await pump(tester);
    for (final haptic in MorphHaptic.values) {
      morphPlayHaptic(context, haptic);
    }
    await tester.pump();
    expect(calls, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.heavyImpact',
    ]);
  });

  testWidgets('the theme switch silences every haptic', (tester) async {
    final context = await pump(tester, haptics: false);
    for (final haptic in MorphHaptic.values) {
      morphPlayHaptic(context, haptic);
    }
    await tester.pump();
    expect(calls, isEmpty);
  });

  testWidgets('a switch toggled by touch plays a light impact', (tester) async {
    var value = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: StatefulBuilder(
            builder: (context, setState) => MorphSwitch(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MorphSwitch));
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(calls, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('a switch set by its owner plays nothing', (tester) async {
    Widget host({required bool value}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: MorphSwitch(value: value, onChanged: (_) {}),
      ),
    );
    await tester.pumpWidget(host(value: false));
    await tester.pumpWidget(host(value: true));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets('a context menu plays its preview tap when the hold opens it', (
    tester,
  ) async {
    var holds = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Center(
          child: MorphContextMenuRegion(
            onHold: () => holds++,
            menu: <MorphMenuEntry>[
              MorphMenuWidget(
                height: 40,
                builder: (BuildContext context) => const Text('action'),
              ),
            ],
            child: Container(
              width: 120,
              height: 48,
              color: const Color(0xFF334455),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MorphContextMenuRegion)),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(holds, 1);
    expect(calls, ['HapticFeedbackType.heavyImpact']);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
