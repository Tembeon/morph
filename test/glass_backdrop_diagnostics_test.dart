import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/backdrop_capture_debug.dart';

void main() {
  testWidgets('renderer P3 independent captures log only when enabled', (
    tester,
  ) async {
    final messages = <String?>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message);
    addTearDown(() {
      debugPrint = original;
      BackdropCaptureDebug.enabled = false;
      BackdropCaptureDebug.reset();
    });
    debugRegisterBackdropCapture(Object(), null);
    debugRegisterBackdropCapture(Object(), null);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(messages, isEmpty);
    BackdropCaptureDebug.enabled = true;
    debugRegisterBackdropCapture(Object(), null);
    debugRegisterBackdropCapture(Object(), null);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(messages.single, startsWith('morph:'));
    debugPrint = original;
    BackdropCaptureDebug.enabled = false;
    BackdropCaptureDebug.reset();
  });
}
