import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/proto/menu_route_probe.dart';

const _step = Duration(microseconds: 8333);
const _button = Rect.fromLTWH(24, 80, 44, 44);

typedef _Environment = ({
  int theme,
  Color color,
  double fontSize,
  double inset,
});
const _root = (theme: 10, color: Color(0xFFAA0000), fontSize: 12.0, inset: 0.0);
const _local = (
  theme: 20,
  color: Color(0xFF0000AA),
  fontSize: 25.0,
  inset: 99.0,
);

class _Palette extends InheritedTheme {
  const _Palette({required this.value, required super.child});
  final int value;

  static int of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Palette>()!.value;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      _Palette(value: value, child: child);

  @override
  bool updateShouldNotify(_Palette oldWidget) => value != oldWidget.value;
}

class _Accent extends InheritedTheme {
  const _Accent({required super.child});

  @override
  Widget wrap(BuildContext context, Widget child) => _Accent(child: child);

  @override
  bool updateShouldNotify(_Accent oldWidget) => false;
}

class _PageData extends InheritedWidget {
  const _PageData({required this.value, required super.child});
  final String value;

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PageData>()!.value;

  @override
  bool updateShouldNotify(_PageData oldWidget) => value != oldWidget.value;
}

class _Words {
  const _Words(this.region);
  final String region;
}

class _WordsDelegate extends LocalizationsDelegate<_Words> {
  const _WordsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<_Words> load(Locale locale) =>
      SynchronousFuture(_Words(locale.countryCode!));

  @override
  bool shouldReload(_WordsDelegate old) => false;
}

class _Content extends StatefulWidget {
  const _Content({required this.harness, super.key});
  final _Harness harness;

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  final controller = TextEditingController(text: 'draft');
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.harness.mounts++;
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.harness;
    h.contentBuilds++;
    h.palette = _Palette.of(context);
    h.accent = context.dependOnInheritedWidgetOfExactType<_Accent>() != null;
    h.text = DefaultTextStyle.of(context).style;
    h.icon = IconTheme.of(context);
    h.media = MediaQuery.of(context);
    h.direction = Directionality.of(context);
    h.locale = Localizations.localeOf(context);
    h.words = Localizations.of<_Words>(context, _Words)!.region;
    h.pageData = _PageData.of(context);
    h.menuNavigator = Navigator.of(context);
    h.menuRoute = ModalRoute.of(context);
    h.menuFocus = FocusScope.of(context);
    return PopScope<void>(
      canPop: h.canPop,
      child: EditableText(
        controller: controller,
        focusNode: focus,
        style: h.text!,
        cursorColor: const Color(0xFF000000),
        backgroundCursorColor: const Color(0xFF000000),
      ),
    );
  }

  @override
  void dispose() {
    widget.harness.disposals++;
    controller.dispose();
    focus.dispose();
    super.dispose();
  }
}

class _Harness {
  final navigator = GlobalKey<NavigatorState>();
  final nested = GlobalKey<NavigatorState>();
  final source = GlobalKey<ProbeMenuSourceState>();
  final content = GlobalKey<_ContentState>();
  final root = ValueNotifier<_Environment>(_root);
  final local = ValueNotifier<_Environment>(_local);
  final present = ValueNotifier(true);
  bool canPop = true;
  bool pointerInput = false;
  bool extraTheme = false;
  bool accent = false;
  Locale rootLocale = const Locale('en', 'US');
  TextDirection rootDirection = .ltr;
  WidgetBuilder? customBuilder;
  int mounts = 0;
  int contentBuilds = 0;
  int disposals = 0;
  int? palette;
  TextStyle? text;
  IconThemeData? icon;
  MediaQueryData? media;
  TextDirection? direction;
  Locale? locale;
  String? words;
  String? pageData;
  NavigatorState? menuNavigator;
  ModalRoute<Object?>? menuRoute;
  FocusScopeNode? menuFocus;
  FocusScopeNode? sourceFocus;

  Widget themes(_Environment env, Widget child) => _Palette(
    value: env.theme,
    child: DefaultTextStyle(
      style: TextStyle(color: env.color, fontSize: env.fontSize),
      child: IconTheme(
        data: IconThemeData(color: env.color, size: env.fontSize),
        child: child,
      ),
    ),
  );

  Widget app(
    WidgetTester tester, {
    bool useNested = false,
    bool overrides = true,
  }) {
    final button = ProbeMenuSource(
      key: source,
      pointerInput: pointerInput,
      now: () => Duration(
        microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
      ),
      menuBuilder: (context) =>
          customBuilder?.call(context) ?? _Content(key: content, harness: this),
    );
    final sourceTree = ValueListenableBuilder<bool>(
      valueListenable: present,
      builder: (_, exists, _) => exists
          ? ValueListenableBuilder<_Environment>(
              valueListenable: local,
              child: Builder(
                builder: (context) {
                  sourceFocus = FocusScope.of(context);
                  return button;
                },
              ),
              builder: (context, env, child) => Localizations.override(
                context: context,
                locale: const Locale('en', 'GB'),
                child: Directionality(
                  textDirection: .rtl,
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(viewInsets: EdgeInsets.only(bottom: env.inset)),
                    child: _PageData(
                      value: 'page',
                      child: overrides
                          ? themes(
                              env,
                              extraTheme ? _Accent(child: child!) : child!,
                            )
                          : child!,
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.expand(),
    );
    return ValueListenableBuilder<_Environment>(
      valueListenable: root,
      builder: (_, env, _) => WidgetsApp(
        color: const Color(0xFFFFFFFF),
        locale: rootLocale,
        supportedLocales: const [Locale('en', 'US'), Locale('en', 'GB')],
        localizationsDelegates: const [_WordsDelegate()],
        navigatorKey: navigator,
        builder: (context, child) => themes(
          env,
          MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: EdgeInsets.only(bottom: env.inset),
              textScaler: TextScaler.linear(env.fontSize / 12),
              platformBrightness: env.theme == 10 ? .light : .dark,
              highContrast: env.theme != 10,
              disableAnimations: env.theme != 10,
            ),
            child: Directionality(
              textDirection: rootDirection,
              child: _PageData(value: 'root', child: child!),
            ),
          ),
        ),
        onGenerateRoute: (_) => PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => useNested
              ? Navigator(
                  key: nested,
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    transitionDuration: Duration.zero,
                    pageBuilder: (_, _, _) => sourceTree,
                  ),
                )
              : sourceTree,
        ),
      ),
    );
  }

  Future<ProbeMenuRoute> open(WidgetTester tester) async {
    await tester.tapAt(_button.center);
    final route = source.currentState!.activeRoute!;
    await _until(tester, () => route.animation!.isCompleted);
    return route;
  }

  Future<void> close(WidgetTester tester, ProbeMenuRoute route) async {
    navigator.currentState!.pop();
    await _until(tester, () => route.disposed);
    if (source.currentState case final state?) {
      await _until(tester, () => state.motionSettled);
    }
    expect(tester.binding.transientCallbackCount, 0);
  }

  void dispose() {
    root.dispose();
    local.dispose();
    present.dispose();
  }
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await tester.pump(_step);
  }
  expect(done(), isTrue);
}

void main() {
  for (final nested in [false, true]) {
    testWidgets('source themes reach root menu, nested=$nested', (
      tester,
    ) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(h.app(tester, useNested: nested));
      final route = await h.open(tester);
      expect(h.palette, 20);
      expect(h.text!.color, _local.color);
      expect(h.text!.fontSize, _local.fontSize);
      expect(h.icon!.color, _local.color);
      expect(h.icon!.size, _local.fontSize);
      expect(h.menuNavigator, same(h.navigator.currentState));
      expect(h.menuRoute, same(route));
      expect(h.menuFocus, isNot(same(h.sourceFocus)));
      await h.close(tester, route);
    });
  }

  testWidgets('local theme refresh preserves editor, focus and PopScope', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.app(tester, useNested: true));
    final route = await h.open(tester);
    final editor = h.content.currentState!;
    editor.controller.text = 'edited';
    editor.focus.requestFocus();
    await tester.pump();
    h.canPop = false;
    h.local.value = (
      theme: 30,
      color: const Color(0xFF00AA00),
      fontSize: 28,
      inset: 77,
    );
    await tester.pump();
    await tester.pump();
    expect(h.palette, 30);
    expect(h.text!.color, h.local.value.color);
    expect(h.icon!.size, 28);
    expect(h.content.currentState, same(editor));
    expect(editor.controller.text, 'edited');
    expect(editor.focus.hasFocus, isTrue);
    expect(h.mounts, 1);
    expect(h.disposals, 0);
    expect(await h.navigator.currentState!.maybePop(), isTrue);
    expect(route.closing, isFalse);
    await h.close(tester, route);
  });

  testWidgets('root system environment stays live and page data stays scoped', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.app(tester));
    final route = await h.open(tester);
    expect(h.media!.viewInsets.bottom, 0);
    expect(h.direction, TextDirection.ltr);
    expect(h.locale, const Locale('en', 'US'));
    expect(h.words, 'US');
    expect(h.pageData, 'root');
    h.rootLocale = const Locale('en', 'GB');
    h.rootDirection = .rtl;
    h.root.value = (theme: 11, color: _root.color, fontSize: 24, inset: 150);
    await tester.pump();
    await tester.pump();
    expect(h.locale, const Locale('en', 'GB'));
    expect(h.words, 'GB');
    expect(h.direction, TextDirection.rtl);
    expect(h.media!.viewInsets.bottom, 150);
    expect(h.media!.textScaler.scale(10), 20);
    expect(h.media!.platformBrightness, Brightness.dark);
    expect(h.media!.highContrast, isTrue);
    expect(h.media!.disableAnimations, isTrue);
    expect(h.content.currentState!.mounted, isTrue);
    await h.close(tester, route);
  });

  testWidgets('themes above root Navigator are not frozen by source capture', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.app(tester, overrides: false));
    final route = await h.open(tester);
    expect(h.palette, 10);
    h.root.value = (
      theme: 11,
      color: const Color(0xFFAA00AA),
      fontSize: 18,
      inset: 0,
    );
    await tester.pump();
    await tester.pump();
    expect(h.palette, 11);
    expect(h.text!.color, h.root.value.color);
    expect(h.icon!.size, 18);
    expect(h.mounts, 1);
    await h.close(tester, route);
  });

  testWidgets(
    'source removal keeps last local themes and live root environment',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(h.app(tester));
      final route = await h.open(tester);
      final editor = h.content.currentState!;
      h.present.value = false;
      await tester.pump();
      expect(h.source.currentState, isNull);
      expect(h.palette, 20);
      h.root.value = (theme: 11, color: _root.color, fontSize: 18, inset: 100);
      await tester.pump();
      await tester.pump();
      expect(h.palette, 20);
      expect(h.media!.viewInsets.bottom, 100);
      expect(h.content.currentState, same(editor));
      await h.close(tester, route);
      expect(h.disposals, 1);
    },
  );

  testWidgets('builder explicitly re-provides page data in popup context', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.app(tester, useNested: true));
    final sourceContext = h.source.currentContext!;
    final data = _PageData.of(sourceContext);
    final locale = Localizations.localeOf(sourceContext);
    final direction = Directionality.of(sourceContext);
    h.customBuilder = (context) => Localizations.override(
      context: context,
      locale: locale,
      child: Directionality(
        textDirection: direction,
        child: _PageData(
          value: data,
          child: _Content(key: h.content, harness: h),
        ),
      ),
    );
    final route = await h.open(tester);
    expect(h.pageData, 'page');
    expect(h.locale, const Locale('en', 'GB'));
    expect(h.words, 'GB');
    expect(h.direction, TextDirection.rtl);
    expect(h.menuRoute, same(route));
    expect(h.menuNavigator, same(h.navigator.currentState));
    h.present.value = false;
    await tester.pump();
    expect(h.source.currentState, isNull);
    expect(h.content.currentState, isNotNull);
    await h.close(tester, route);
  });

  for (final cancel in [false, true]) {
    testWidgets('theme refresh during hidden preparation, cancel=$cancel', (
      tester,
    ) async {
      final h = _Harness();
      h.pointerInput = true;
      addTearDown(h.dispose);
      await tester.pumpWidget(h.app(tester));
      final gesture = await tester.startGesture(_button.center);
      final route = h.source.currentState!.activeRoute!;
      await tester.pump(const Duration(milliseconds: 50));
      h.local.value = (
        theme: 40,
        color: const Color(0xFF00AAAA),
        fontSize: 29,
        inset: 10,
      );
      await tester.pump();
      await tester.pump();
      expect(h.mounts, 0);
      if (cancel) {
        await gesture.cancel();
        await _until(tester, () => route.disposed);
        expect(h.mounts, 0);
        expect(tester.binding.transientCallbackCount, 0);
      } else {
        await _until(tester, () => route.animation!.isCompleted);
        expect(h.palette, 40);
        expect(h.mounts, 1);
        await gesture.up();
        await h.close(tester, route);
      }
    });
  }

  testWidgets('several local value changes publish latest without remounting', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.app(tester));
    final route = await h.open(tester);
    final editor = h.content.currentState!;
    h.local.value = (theme: 31, color: _local.color, fontSize: 26, inset: 0);
    h.local.value = (theme: 32, color: _local.color, fontSize: 27, inset: 0);
    await tester.pump();
    await tester.pump();
    expect(h.palette, 32);
    expect(h.text!.fontSize, 27);
    expect(h.content.currentState, same(editor));
    expect(h.mounts, 1);
    await h.close(tester, route);
  });

  testWidgets('theme refresh stays safe during route removal and reopening', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.app(tester));
    final route = await h.open(tester);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      h.navigator.currentState!.removeRoute(route);
    });
    h.local.value = (theme: 33, color: _local.color, fontSize: 26, inset: 0);
    await tester.pump();
    await tester.pump();
    expect(route.disposed, isTrue);
    expect(h.disposals, 1);
    h.local.value = (theme: 34, color: _local.color, fontSize: 27, inset: 0);
    await tester.pump();
    final next = await h.open(tester);
    expect(h.palette, 34);
    expect(h.mounts, 2);
    await h.close(tester, next);
  });

  testWidgets('motion frames do not rebuild theme content', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.app(tester));
    await tester.tapAt(_button.center);
    final route = h.source.currentState!.activeRoute!;
    await tester.pump();
    await tester.pump();
    final builds = h.contentBuilds;
    expect(builds, greaterThan(0));
    for (var i = 0; i < 30; i++) {
      await tester.pump(_step);
    }
    expect(h.contentBuilds, builds);
    expect(h.mounts, 1);
    await h.close(tester, route);
  });

  testWidgets('open route keeps theme kinds; next route adopts new topology', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.app(tester));
    final route = await h.open(tester);
    final editor = h.content.currentState!;
    expect(h.accent, isFalse);
    h.extraTheme = true;
    h.local.value = (theme: 35, color: _local.color, fontSize: 30, inset: 0);
    await tester.pump();
    await tester.pump();
    expect(h.palette, 20);
    expect(h.accent, isFalse);
    expect(h.content.currentState, same(editor));
    expect(h.mounts, 1);
    await h.close(tester, route);
    final next = await h.open(tester);
    expect(h.palette, 35);
    expect(h.accent, isTrue);
    expect(h.mounts, 2);
    await h.close(tester, next);
  });
}
