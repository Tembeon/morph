import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

import 'support/glass_backdrop_keys.dart';

Widget _button(String label) => MorphGlassButton(
  key: ValueKey<String>(label),
  onPressed: () {},
  child: Text(label),
);

void main() {
  setUpAll(() => isLocalTest = true);
  tearDownAll(() => isLocalTest = false);

  testWidgets('a section in its own BackdropGroup reads a copy of its own', (
    tester,
  ) async {
    final page = BackdropKey();
    final section = BackdropKey();
    Future<Set<BackdropKey?>> keys({required bool own}) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: MorphTheme(
            data: const MorphThemeData(glass: .tier(MorphGlassTier.liquid)),
            child: BackdropGroup(
              backdropKey: page,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _button('first'),
                    const ColoredBox(
                      color: Color(0xFFFF3B30),
                      child: SizedBox(height: 40, width: 200),
                    ),
                    if (own)
                      BackdropGroup(
                        backdropKey: section,
                        child: _button('second'),
                      )
                    else
                      _button('second'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      tester.takeException();
      await tester.pump();
      return glassBackdropKeys(tester).toSet();
    }

    expect(await keys(own: false), {page});
    expect(await keys(own: true), {page, section});
  });
}
