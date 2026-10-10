// The test reads the renderer's internals.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/glass_shadow.dart';
import 'package:morph/src/glass/renderer/internal/glass_defaults.dart';
import 'package:morph/src/glass/renderer/internal/glass_shadow_shader.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

/// A glass shadow loads its shader itself when the option is on, so an app
/// that never runs the renderer's precache still draws shader shadows.
///
/// A file of its own: the shader is loaded once per isolate, and this test
/// needs it unloaded before the shadow attaches.
void main() {
  setUpAll(() => isLocalTest = true);
  tearDown(() => MorphGlassShadowShader.debugEnabled = null);

  testWidgets('an attached shadow loads the shader', (tester) async {
    MorphGlassShadowShader.debugEnabled = true;
    expect(MorphGlassShadowShader.ready, isFalse);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 96,
            height: 44,
            child: GlassShadow(
              shape: LiquidRoundedSuperellipse(borderRadius: 22),
              shadows: [MorphGlassDefaults.bodyShadow],
              settings: LiquidGlassSettings(),
              appearanceVisibility: 1,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(MorphGlassShadowShader.ready, isTrue);
  });
}
