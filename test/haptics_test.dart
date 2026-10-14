import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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
      MorphWidgetsThemeScope(
        data: MorphWidgetsTheme(haptics: haptics),
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
}
