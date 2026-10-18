# Эскиз API и модулей morph

Статус: типы и сигнатуры принятого направления, 2026-10-15. Сигнатуры ниже не компилировались и не являются готовым example. Отдельный сокращённый host-прототип P1 уже компилируется и проходит 32 проверки, отчёт в `tool/audit/foundation-p1-2026-10-15/report.md`; он не реализует весь этот эскиз. Обоснование находится в `foundation-review.md`. Имена предварительные, окончательный список фиксирует golden `test/api/public_api.txt`.

## Использование

### Быстрый старт в `WidgetsApp`

```dart
import 'package:flutter/widgets.dart';
import 'package:morph/morph.dart';

void main() => runApp(
  WidgetsApp(
    color: const Color(0xFF007AFF),
    builder: (context, navigator) => MorphTheme(
      data: const MorphThemeData(tint: Color(0xFF34C759)),
      child: navigator!,
    ),
    onGenerateRoute: (_) => PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => const MorphNavigationStack(
        pages: [MorphNavigationPage(child: SettingsScreen())],
      ),
    ),
  ),
);
```

Root Navigator приложения держит один обычный route со стеком, а также модальные представления. `MorphNavigationStack` является единственным контейнером навигации morph, он владеет своим Navigator и барами. Страницы внутри стека являются `MorphNavigationRoute`, их кладут через `Navigator.push` или описывают как `MorphNavigationPage` в декларативном API. Это выбор SDK между императивным и декларативным API, а не второй путь morph. `MorphTheme` стоит над root Navigator, поэтому каждый route наследует тему без переноса. Делегат локализации не обязателен. Без него `MorphLocalizations.of` отдаёт встроенные английские строки, делегат нужен только для других языков. Плоский рендерер выбирается полем темы `glass: const MorphGlassRenderer.tier(MorphGlassTier.flat)`, по умолчанию tier выбирается адаптивно.

Hero между `MorphNavigationRoute` в первом релизе не обещан. `WidgetsApp` не устанавливает `HeroController`. Прототип P1 записывает поведение Hero на проецируемой анимации с установленным `HeroController`.

### Управляемый switch с отказом

```dart
MorphSwitch(
  value: cellularData,
  onChanged: (next) async {
    if (!next) {
      setState(() => cellularData = false);
      return;
    }
    final allowed = await confirmRoamingCost(context);
    if (allowed && mounted) setState(() => cellularData = true);
  },
)
```

Родитель владеет значением. Если родитель не перестроился с `next`, после кадра switch возвращает движение к `widget.value` от места, где thumb оставил жест, со скоростью жеста. Pointer, клавиатура через `ActivateIntent` и semantics `onTap` проходят через одно предложение `onChanged`.

### Sheet из кнопки с живым редактором во вложенном стеке

```dart
class _ComposeButtonState extends State<ComposeButton> {
  final _compose = MorphSourceLink();
  @override
  Widget build(BuildContext context) => MorphGlassButton(
    source: _compose,
    onPressed: _open,
    child: const Text('Compose'),
  );
  Future<void> _open() async {
    final draft = await showMorphSheet<String>(
      context,
      from: _compose,
      detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
      builder: (context) => const DraftEditor(),
    );
    if (!mounted || draft == null) return;
    widget.onDraft(draft);
  }
}

class _DraftEditorState extends State<DraftEditor> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => MorphNavigationStack(
    pages: [
      MorphNavigationPage(
        child: MorphNavigationScaffold(
          title: const Text('Draft'),
          trailing: [
            MorphBarButton(
              label: const Text('Done'),
              onPressed: () => Navigator.of(context).pop(_text.text),
            ),
          ],
          child: EditableText(
            controller: _text,
            focusNode: _focus,
            style: MorphTypography.body,
            cursorColor: const Color(0xFF007AFF),
            backgroundCursorColor: const Color(0xFF8E8E93),
          ),
        ),
      ),
    ],
  );
}
```

Sheet является route. `Navigator.pop` с результатом, veto через `PopScope` и возврат фокуса работают как у любого route. Стек внутри sheet сам передаёт системный back своему Navigator через `NavigatorPopHandler`, поэтому back сначала снимает страницу стека, затем закрывает sheet. `context` в `onPressed` принадлежит State редактора над Navigator стека, поэтому `pop` закрывает sheet. Контроллер и focus node живут в State содержимого route, `_compose` не требует dispose. Если источник исчезнет во время показа, sheet растворится при закрытии вместо посадки.

### Меню на кнопке бара

```dart
MorphNavigationScaffold(
  title: const Text('Notes'),
  trailing: [
    MorphBarButton(
      label: const Text('Sort'),
      menu: [
        MorphMenuItem(title: const Text('By Date'), onPressed: _sortByDate),
        MorphMenuItem(title: const Text('Delete'), destructive: true, onPressed: _delete),
      ],
    ),
  ],
  child: notes,
)
```

Меню является route на root navigator. Back, Esc, нажатие снаружи и `Navigator.pop` закрывают его. Нажатие, протяжка и отпускание выбирают пункт одним жестом. Кнопка сама является источником меню и доигрывает его посадку, оставаясь слитой с соседями в баре.

### Стекло приложения и собственный painter

```dart
MorphGlassEffect(
  shape: const MorphGlassShape.rounded(22),
  style: MorphGlassStyle.clear,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Text(title),
  ),
)

class BrandGlassPainter extends MorphGlassPainter {
  const BrandGlassPainter(this.brand);
  final Color brand;
  @override
  ImageFilter? backdropFilter(MorphGlassScene scene) =>
      ImageFilter.blur(sigmaX: 14, sigmaY: 14);
  @override
  void paint(Canvas canvas, MorphGlassScene scene) {
    final fill = Paint();
    for (final surface in scene.surfaces) {
      fill.color = brand.withValues(alpha: 0.18 * surface.opacity);
      surface.drawShape(canvas, fill);
    }
  }
  @override
  bool shouldRepaint(BrandGlassPainter oldPainter) => oldPainter.brand != brand;
}

MorphTheme(
  data: MorphTheme.of(context).copyWith(
    glass: const MorphGlassRenderer.painted(BrandGlassPainter(brand)),
  ),
  child: const PlayerScreen(),
)
```

Painter получает сцену только для чтения: поверхности с ролью, формой, opacity и подъёмом, а также слитый контур, если пакет слил поверхности. Canvas уже обрезан по контуру, запрошенный фильтр backdrop применён в том же кадре. Painter рисует и все контролы morph ниже темы. Layout, hit targets и принятые значения от painter не зависят.

Ограничения этого предложения ещё не приняты. В сигнатурах ниже surface не передаёт `MorphGlassStyle`, а обрезанный Canvas не позволяет рисовать свечение за контуром. До удаления старого шва в единице 6 пример должен показать regular и clear рядом, движущийся фон, слитую шейку и внешнее свечение. По нему решается, нужны ли `style` во view и отдельный проход внешних эффектов либо ограничение painter принимается явно. Более богатая сцена сама по себе ограничение clipping не снимает.

## Публичные сигнатуры

### `package:morph/morph.dart`, около 100 имён

| Группа | Имена | Число |
| --- | --- | --- |
| Тема | `MorphTheme`, `MorphThemeData`, `MorphAppearance`, `MorphLocalizations`, `MorphTypography`, `MorphGlassRenderer`, `MorphGlassTier` | 7 |
| Стекло приложения | `MorphGlassEffect`, `MorphGlassContainer`, `MorphGlassStyle`, `MorphGlassShape` | 4 |
| Источник | `MorphSource`, `MorphSourceLink` | 2 |
| Представления | `showMorphSheet`, `showMorphAlert`, `showMorphActionSheet`, `MorphNavigationRoute`, `MorphNavigationPage`, `MorphSheetDetent`, `MorphAlertAction`, `MorphAlertActionStyle`, `MorphAlertTextField` | 9 |
| Контролы | `MorphActivityIndicator`, `MorphBadge`, `MorphBarButton`, `MorphBarButtonGroup`, `MorphContextMenuRegion`, `MorphSatellite`, `MorphDatePicker`, `MorphGlassButton`, `MorphLargeTitle`, `MorphListAccessory`, `MorphListRow`, `MorphListSection`, `MorphSliverListSection`, `MorphMenuButton`, `MorphMenuSource`, `MorphNavigationBar`, `MorphNavigationConfig`, `MorphNavigationScaffold`, `MorphNavigationSearch`, `MorphNavigationStack`, `MorphPageControl`, `MorphProgressView`, `MorphScrollEdgeEffect`, `MorphScrollIndicator`, `MorphSearchField`, `MorphSearchTabBar`, `MorphSearchToolbar`, `MorphSegment`, `MorphSegmentedControl`, `MorphSlider`, `MorphStepper`, `MorphSwitch`, `MorphTabBar`, `MorphTabItem`, `MorphToolbar`, `MorphContentScrollScope` | 36 |
| Элементы меню | `MorphMenuEntry`, `MorphMenuItem`, `MorphMenuSection`, `MorphSubmenu`, `MorphMenuDivider`, `MorphMenuDeferred`, `MorphMenuWidget` | 7 |
| Перечисления | `MorphActivityIndicatorSize`, `MorphBackButtonDisplayMode`, `MorphBarButtonStyle`, `MorphDatePickerMode`, `MorphDatePickerStyle`, `MorphLargeTitleDisplayMode`, `MorphListBackground`, `MorphMenuElementSize`, `MorphMenuIconVisibility`, `MorphMenuOrder`, `MorphMenuState`, `MorphMenuTrigger`, `MorphNavigationBarHiding`, `MorphPageControlBackgroundStyle`, `MorphProgressViewStyle`, `MorphScrollEdgeEffectStyle`, `MorphTabBarMinimizeBehavior`, `MorphTabRole` | 18 |
| Appearances | `MorphActivityIndicatorAppearance`, `MorphAlertAppearance`, `MorphBarAppearance`, `MorphDatePickerAppearance`, `MorphGlassButtonAppearance`, `MorphListAppearance`, `MorphMenuAppearance`, `MorphPageControlAppearance`, `MorphProgressViewAppearance`, `MorphScrollEdgeEffectAppearance`, `MorphSearchFieldAppearance`, `MorphSegmentedControlAppearance`, `MorphSheetAppearance`, `MorphSliderAppearance`, `MorphStepperAppearance`, `MorphSwitchAppearance`, `MorphTabBarAppearance` | 17 |

Контролы сохраняют текущие параметры конструкторов, кроме удалённых tunings и metrics. Контрол, который может быть источником представления, принимает `source: MorphSourceLink?`. `MorphSource(link:)` только называет источник представления вокруг произвольного виджета. `MorphMenuSource` делает другое: превращает произвольный виджет в триггер меню и сам владеет своей ссылкой. `MorphNavigationRoute` и `MorphNavigationPage` публичны, потому что являются единственным типом страницы стека, скрыты только модальные классы route. Ниже показаны типы, которые меняются по форме.

```dart
class MorphTheme extends InheritedTheme {
  const MorphTheme({required this.data, required super.child, super.key});
  final MorphThemeData data;
  static MorphThemeData of(BuildContext context) => throw UnimplementedError();
  @override
  Widget wrap(BuildContext context, Widget child) => throw UnimplementedError();
  @override
  bool updateShouldNotify(MorphTheme oldWidget) => throw UnimplementedError();
}
@immutable
class MorphThemeData {
  const MorphThemeData({this.brightness, this.tint, this.haptics = true,
      this.glass = const MorphGlassRenderer.adaptive(), this.appearances = const []});
  final Brightness? brightness;
  final Color? tint;
  final bool haptics;
  final MorphGlassRenderer glass;
  final Iterable<MorphAppearance> appearances;
  T? appearance<T extends MorphAppearance>() => throw UnimplementedError();
  MorphThemeData copyWith({Brightness? brightness, Color? tint, bool? haptics,
      MorphGlassRenderer? glass, Iterable<MorphAppearance>? appearances}) =>
      throw UnimplementedError();
  static MorphThemeData lerp(MorphThemeData a, MorphThemeData b, double t) =>
      throw UnimplementedError();
}
enum MorphGlassTier { flat, fake, liquid }
sealed class MorphGlassRenderer {
  const MorphGlassRenderer();
  const factory MorphGlassRenderer.adaptive() = _AdaptiveGlass;
  const factory MorphGlassRenderer.tier(MorphGlassTier tier) = _FixedGlass;
  const factory MorphGlassRenderer.painted(MorphGlassPainter painter) = _PaintedGlass;
}
enum MorphGlassStyle { regular, clear }
sealed class MorphGlassShape {
  const MorphGlassShape();
  const factory MorphGlassShape.capsule() = _Capsule;
  const factory MorphGlassShape.circle() = _Circle;
  const factory MorphGlassShape.rounded(double radius) = _Rounded;
}
class MorphGlassEffect extends StatelessWidget {
  const MorphGlassEffect({required this.child, this.shape = const MorphGlassShape.capsule(),
      this.style = MorphGlassStyle.regular, this.tint, this.interactive = false, super.key});
  final Widget child;
  final MorphGlassShape shape;
  final MorphGlassStyle style;
  final Color? tint;
  final bool interactive;
  @override
  Widget build(BuildContext context) => throw UnimplementedError();
}
final class MorphSourceLink {
  MorphSourceLink();
  bool get isAttached => throw UnimplementedError();
}
enum MorphSheetDetent { medium, large }
Future<T?> showMorphSheet<T>(BuildContext context, {required WidgetBuilder builder,
    MorphSourceLink? from, List<MorphSheetDetent> detents = const [MorphSheetDetent.large],
    MorphSheetDetent? initialDetent, MorphSheetDetent? largestUndimmedDetent,
    bool grabberVisible = false, bool dismissible = true, bool scrollingExpandsSheet = true,
    MorphSheetAppearance? appearance, String? semanticLabel,
    ValueChanged<MorphSheetDetent>? onDetentChanged}) => throw UnimplementedError();
class MorphNavigationRoute<T> extends PageRoute<T> with MorphMotionRoute<T> {
  MorphNavigationRoute({required this.builder, this.from, super.settings, super.fullscreenDialog});
  final WidgetBuilder builder;
  final MorphSourceLink? from;
  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) => throw UnimplementedError();
}
```

`MorphNavigationPage<T>` является `Page<T>` с полями `child` и `from` и создаёт `MorphNavigationRoute`. `MorphSource({required MorphSourceLink link, required Widget child})` присоединяет к ссылке любой виджет. `MorphAppearance` является базой с единственным методом `lerp`, таблицы appearance объявлены как `static const tables` у своего класса, например `MorphSwitchAppearance.tables`. `MorphLocalizations` отдаёт `dismissLabel`, `backLabel` и `cancelLabel` и имеет `delegate` для других языков. `MorphSwitch` сохраняет текущий конструктор (`value`, `onChanged`, `appearance`, `semanticLabel`).

### `package:morph/glass_painter.dart`, 5 имён

Сейчас эта библиотека экспортирует 6 имён. Новая экспортирует `MorphGlassPainter`, `MorphGlassScene`, `MorphGlassSurface`, `MorphGlassOutline` и `MorphGlassRole`. Эти типы объявлены в `lib/src/theme/glass_painter.dart`, поэтому тема ссылается на painter без импорта сцены. Три views являются интерфейсами только для чтения. Сцена реализует их переиспользуемыми объектами без выделения на кадр. GPU-типы, shader, uniforms и render objects не публикуются. Новые views появляются в единице 6 и в том же commit заменяют старые публичные классы `MorphGlassSurface` и `MorphGlassOutline`.

Модификаторы трёх views ниже пока показывают намерение запретить внешнюю реализацию, но несовместимы с указанным размещением: `abstract final` запрещает `implements` из другой Dart-библиотеки, в том числе из `scene/`. До единицы 6 выбрать `abstract interface` с разрешённой внешней реализацией либо разместить внутренние реализации в той же Dart-библиотеке. Текущие сигнатуры не являются компилируемым контрактом.

```dart
abstract class MorphGlassPainter {
  const MorphGlassPainter();
  ui.ImageFilter? backdropFilter(MorphGlassScene scene) => null;
  void paint(Canvas canvas, MorphGlassScene scene);
  bool shouldRepaint(covariant MorphGlassPainter oldPainter);
}
enum MorphGlassRole { track, lens, button, bar, menu, sheet, container }
abstract final class MorphGlassSurface {
  MorphGlassRole get role;
  ui.RSuperellipse get shape;
  double get opacity;
  double get lift;
  Color? get tint;
  void drawShape(Canvas canvas, Paint paint);
}
abstract final class MorphGlassOutline {
  Rect get bounds;
  void draw(Canvas canvas, Paint paint);
}
abstract final class MorphGlassScene {
  Iterable<MorphGlassSurface> get surfaces;
  MorphGlassOutline? get outline;
}
```

### Внутреннее ядро, только сигнатуры

```dart
final class MorphSpringState {
  MorphSpringState(MorphSpring spring, double value);
  void retarget(double t, double target, {MorphSpring? spring});
  double value(double t);
  double velocity(double t);
  double reach(double t);
}
abstract interface class MorphMotion<E extends Object> {
  double get time;
  void advance(double t);
  bool get isSettled;
  double? get wakeTime;
  void settle();
  List<E> drainEvents();
}
final class MorphMotionClock {
  MorphMotionClock({required TickerProvider vsync, required MorphFrameOutcome Function(double t) onFrame});
  Listenable get frames;
  double stamp(PointerEvent event);
  double timeAt(Duration absolute);
}
abstract class MorphHost<W extends StatefulWidget, E extends Object> extends State<W> {
  MorphMotion<E> createMotion(double frameRate);
  void onMotionEvent(E event);
  void reconcileAfterFrame(bool Function() apply);
  Widget buildControl(BuildContext context);
}
abstract interface class MorphPresentationMotion implements MorphMotion<MorphPresentationEvent> {
  double get progress;
  MorphHandBack get handBack;
  void present(double t);
  void dismiss(double t);
  void scrub(double t, double progress);
  void release(double t, {required bool commit, double velocity});
  MorphMotionSnapshot capture(Duration absolute);
  void resume(MorphMotionSnapshot snapshot, double t);
}
mixin MorphMotionRoute<T> on ModalRoute<T> implements PredictiveBackRoute {
  MorphPresentationMotion createPresentationMotion(double frameRate);
  Animation<double> createAnimation();
  TickerFuture didPush();
  void didAdd();
  void didReplace(Route<Object?>? oldRoute);
  void resumeFrom(MorphMotionRoute<Object?> closing);
}
final class MorphRouteAnimation extends Animation<double> {
  void update(double progress, AnimationStatus status);
}
final class MorphSettleSignal {
  TickerFuture start();
  void complete();
}
enum MorphPresentationLevel { window, context }
NavigatorState morphPresentationNavigatorOf(BuildContext context, MorphPresentationLevel level);
final class MorphSurfaceHandle {
  void write({required ui.RSuperellipse shape, double opacity, double lift});
  void configure({required MorphGlassRole role, required MorphGlassStyle style, Color? tint});
}
final class MorphSurfaceCarry {
  void lift();
  void land();
  set landing(Matrix4? transform);
}
sealed class MorphFusionLaw {
  static const MorphFusionLaw none = _NoFusion();
  const factory MorphFusionLaw.container(double spacing) = _ContainerLaw;
  const factory MorphFusionLaw.morph(double sigma) = _MorphLaw;
}
abstract final class MorphShaderRegistry {
  static Future<void> prepare(MorphGlassTier tier);
}
```

`MorphMotionRoute` ставит `transitionDuration` и `reverseTransitionDuration` в ноль, `finishedWhenPopped` в false, а `createAnimationController` отдаёт контроллер, который никто не слушает. `MorphRouteAnimation` пишет только свой route. Tiers рисуют через подклассы `RenderMorphScene`, которые на каждом кадре движения читают кадр сцены и помечают paint.

Это кандидат до P1. Во Flutter 3.47.2 базовые `didAdd` и `didReplace` меняют только внутренний controller (`routes.dart:353, 364`), поэтому эти обработчики обязаны отдельно согласовать движение и проекцию. P1 проверяет начальные `Pages`, `Navigator.replace` и restoration, включая значение, статус, непрозрачность overlay и завершение route. Проверка `pushReplacement` не заменяет эти сценарии. Вариант на SDK controller сравнивается по требованиям времени: `unbounded` и `animateWith` поддерживаются SDK, перелёт не является самостоятельной причиной отказа.

Сигнатура `MorphHost extends State` тоже является кандидатом. Общие механизмы времени, ввода, событий и согласования проверяются на switch, меню и sheet до массового перевода State. Если обязательная база мешает этим сценариям, допускаются композиция объектов и узкие mixin; route использует `MorphMotionClock` напрямую. После каждой команды ввода события движения доставляются до возврата из обработчика; после кадрового `advance` доставляются события времени, затем публикуется кадр. Очередь не меняет синхронность текущих `onChanged` и haptics.

Уточнение P2 от 2026-10-16: `capture/resume` обязаны переносить целую модель вместе с её непрерывным временем, включая timeline и driven channels. Первый host-прототип сохраняет каноническое время и меняет смещение к часам владельца; отдельный `rebase` в `MorphSpringState` из эскиза убран как неподтверждённая обязанность. При пробуждении источник получает актуальный локальный якорь, а первый кадр учитывает интервал от кадра передачи. Это проверено при сне и дрёме на 1× и 5×; окончательные сигнатуры capture/resume и часов уточняются после настоящего menu route и P3. Отчёт: `tool/audit/foundation-p2-2026-10-16/report.md`.

Продолжение P2: сокращённый настоящий root `PopupRoute` передаёт целую модель источнику и поддерживает reopen с обоих владельцев. Прототип явно останавливает часы отдающего владельца и возобновляет принимающие через `resumeAt(absoluteStamp)`. Для передачи на кадре берётся метка кадра, для команды между кадрами — текущее время engine clock; смешивать их после простоя нельзя. Общий внутренний контракт времени уточняется по этому результату и P3. Отчёт с 106 проверками прототипов: `tool/audit/foundation-p2-2026-10-16/route/report.md`. Полный menu API, геометрия source link и контур бара пока не реализованы этим стендом.

Записанный ввод P2 уточняет ещё три обязанности. Hold/drag требуют сохранения потока указателя: поздний push его отменяет, ранний скрытый route на source pointer-down проходит 20 replay с отложенными content/focus. Его влияние на observer/isCurrent проверяется до выбора. Veto требует события запроса закрытия до изменения фазы движения; очередь уже начавшегося закрытия не решает задачу. Наконец, `MorphSurfaceCarry` обязан сохранять контур/закон слияния: моментальная смена Gaussian-поля меню на контейнерное поле бара не проходит pixel-zero на изолированном кадре. Эти контрпримеры и 135 проверки прототипов записаны в `tool/audit/foundation-p2-2026-10-16/input/report.md`; полный бар и veto pointer-пути пока не приняты.

Синхронная часть veto и flat-перенос теперь подтверждены отдельно: 149 проверок прототипов и 459 кадров настоящего widget без разницы с непрерывной моделью. Прототип читает `popDisposition` до closing через внутренний допуск существующей модели; обратное уведомление SDK доставляет после команды/advance. `willHandlePopInternally` оставляет движение открытым, пока SDK снимает `LocalHistoryEntry`. Эта временная точка в `lib/src/widgets/menu_motion.dart` не экспортируется из библиотек пакета и удаляется вместе с callback-полями в 2.4. Она не заменяет контракт typed E и не решает асинхронное ожидание. Общий flat-путь сохраняет собственный Gaussian-контур меню до конца хвоста поверх контейнерной геометрии кнопки и соседей; SDF/оптика и полный продуктовый бар ещё требуют доказательства. Отчёт `tool/audit/foundation-p2-2026-10-16/admission/report.md`.

Async P2 уточняет время и будущую границу событий: sync сохраняет измеренный deadline, async сохраняет время первого запроса как provenance и закрывается из текущего состояния владельца. Retarget в прошлом не восстанавливает kicks. Проверены один pending request, одноразовый допуск к pop, отмена во время ожидания и 60/120 Гц при 1×/5×; суммарно 175 проверок прототипов. Route, а не модель, владеет SDK Future. Существующие clock/timeline не меняются. Для единицы 2.4 остаётся возобновляемая граница до финального сэмпла: очередь после полного advance неэквивалентна этому контракту. Запрос до mount policy и атомарность уже выданного SDK ответа остаются открыты. Протокол `docs/architecture/menu-dismissal-protocol.md`, отчёт `tool/audit/foundation-p2-2026-10-16/async/report.md`.

Первый mount P2 подтверждён отдельным gate реального поддерева с отменой ожидания; hidden preparation и открывающееся меню имеют разные правила Back. 194 проверки прототипов сохраняют replay. Цена раннего push тоже подтверждена: root observer/currentness и traversal меняются до видимого открытия, локальная nested page остаётся current. Это не выбор продуктового presenter; nested Escape/Router и ввод под покрывающим route ещё открыты. Lifetime-исправления часов затрагивают только прототип и не меняют время. Протокол `docs/architecture/menu-route-lifecycle.md`.

## Карта модулей

Направление зависимостей задаёт одна таблица в `test/architecture_test.dart`. Тест читает каждый `import` и `export` во всём `lib/`, включая точки входа и все ветви условных директив, и сверяет локальные связи с таблицей. Запрет пакетов проверяется также по достижимому графу сторонних runtime-зависимостей с границей SDK из плана. Golden API не заменяет проверку зависимостей. Отдельное правило для чистых `*_motion.dart` запрещает зависимость от widget/host, в том числе своего семейства. Отрицательные fixtures содержат запрещённый export, транзитивную runtime-зависимость и импорт host из motion. Там же лежит allow-list SDK. Разрешены `flutter/widgets`, `rendering`, `foundation`, `scheduler`, `services`, `physics`, `painting`, `gestures`, `animation`, `dart:ffi` за условным импортом и `flutter_gpu`. Запрещены `material_ui`, `cupertino_ui`, `package:flutter/material.dart`, `package:flutter/cupertino.dart` и `motor`. Таблица ниже повторяет правило для читателя, источник правила только тест.

| Каталог | Чем владеет | Что не импортирует |
| --- | --- | --- |
| `lib/src/motion/` | `MorphSpring`, `MorphSpringState`, `MorphRest`, `MorphTimeline`, `MorphChannel`, flex-интегратор и `MorphFlexInteraction`, `MorphMotion<E>`, `MorphMotionClock`, `MorphFrameGrid`, `MorphSettleSignal`, часы указателя (io и stub), `morphRubberband` | Другие каталоги morph. Из Flutter только foundation, scheduler, physics, gestures и `dart:ui`. |
| `lib/src/host/` | `MorphHost`, `MorphPress`, `MorphPressTracker`, `MorphTouchListener`, focus ring, `MorphStepIntent`, раздача haptics, фаза согласования кадра по итогам P3 | `presentation/`, `widgets/`, `scene/renderer/` |
| `lib/src/theme/` | `MorphTheme`, `MorphThemeData`, `MorphAppearance`, `MorphAppearanceTables`, `morphAppearanceOf`, lookups brightness, contrast и reduced motion, `MorphLocalizations`, `MorphTypography`, sealed `MorphGlassRenderer` и `MorphGlassTier`, типы painter-шва в `glass_painter.dart` | Всё остальное в morph. Сцена читает выбор рендерера из темы, тема сцену не импортирует. |
| `lib/src/scene/` | `MorphSurface`, `MorphSurfaceHandle`, `MorphSurfaceCarry`, `MorphSceneFrame`, `MorphOutline`, реализации views, `MorphSceneHost`, `live.dart`, `fusion/` (один конвейер, один tracer, `MorphFusionLaw`), `tiers/` (flat, fake, liquid, painter), `capability.dart`, `shaders.dart` (`MorphShaderRegistry`), `backdrop_cache.dart`, `renderer/` (vendored, читает `MorphSurface`) | `host/`, `presentation/`, `widgets/`. |
| `lib/src/presentation/` | `MorphMotionRoute`, `MorphRouteAnimation`, `MorphPopupRoute`, `MorphPresentationMotion`, `MorphMotionSnapshot`, `MorphHandBack`, `MorphSource`, `MorphSourceLink`, `morphPresentationNavigatorOf`, `MorphPresentationLevel`, маркер navigator стека, observer predictive back | `widgets/` |
| `lib/src/widgets/<family>/` | Каталог на семейство: `switch/`, `slider/`, `stepper/`, `segmented/` и `tab_bar/` с общим `lens/`, `button/`, `menu/`, `bars/`, `navigation/`, `sheet/`, `alert/`, `date_picker/`, `list/`, `glass/`, `progress/`, `page_control/`, `scroll/`. В каждом `<x>.dart` (виджет и host), `<x>_motion.dart` (чистое движение и его события), `<x>_appearance.dart` (класс и `static const tables`). | Файлы другого семейства, кроме общих `lens/` и `menu/`. |

Отладочные типы `MorphGlassInspector`, `MorphGlassCensus`, `MorphGlassHint` и `MorphGlassDeviceClass` остаются в `lib/src/scene/debug/` для галереи. Новый контрол копирует ближайший каталог семейства. Время он получает через общий механизм host в форме, подтверждённой единицей 3, стекло через `MorphSurfaceHandle`, вид через `morphAppearanceOf`.

## Что удаляется

Обозначения доказательств: P для `ground/presentation.md`, C для `ground/controls.md`, R для `ground/rendering.md`. Номер единицы указывает, где удаление происходит по плану.

### Legacy-движок

| Что | Единица | Почему безопасно |
| --- | --- | --- |
| Shuttle без vessel (flight.dart:1081-1460, 1797-2350), `route.dart` (618 строк), `anchor.dart` (257), `shared.dart` (469), `measure.dart` (126), пресеты `show.dart`, фабрики `MorphTargetSpec` кроме vessel, `frame.dart`, функции drag в `gesture.dart` кроме `morphRubberband`, `snapshotGhost`, публичный `skin.dart` (1649), `example/lib/gallery/engine_page.dart`, 54 legacy-теста. Экспорт `MorphController`, `closeAll`, `MorphFlightScope` и других имён движка без потребителя в слое виджетов | 1 | Ни одного потребителя в слое виджетов. `showMorph`, vessel и `morphRubberband` в тех же файлах живут до своих единиц. Страница галереи 1c159718 создана только чтобы держать их в работе (P, consumer matrix). |
| `MorphFlight`, `_MorphShuttle`, `_VesselFrame`, `MorphScope`, `MorphTag` и спутники, `MorphController`, `MorphScrimMotion`, `MorphScrimChannel`, `showMorph`, `MorphTargetSpec.vessel`, `morphAnchorRect`, `MorphPresentationBoundary`, `morphPresentationOverlayOf`, `MorphThemeCarrier`, жонглирование `LocalHistoryEntry`, двойная пружина меню, `_advanceDetached` | 5.3 | Каждую услугу vessel даёт `ModalRoute`: barrier с semantics, focus trap, Esc через `DismissIntent`, back, veto, блокировку нажатий при `reverse` (routes.dart:1154, 2280 в SDK 3.47.2). `morphTargetPaddingOf` переходит в layout меню. |
| `MorphMotionRouteMixin`, `MorphZoomSource` | 5.2 | Их заменяет `MorphMotionRoute`. Dissolve, скрытие источника, crossfade и радиус остаются одной копией в движении представления и в `MorphSourceLink` (P, legacy 2). |

### Дубли движения

| Что | Единица | Чем заменяется |
| --- | --- | --- |
| `motor`, `MorphSpring.toMotion`, реэкспорты motor, `SingleMotionController` (morph_context_menu.dart:393) | 2 | `MorphSpringState`. motor импортируют src/motion.dart:1, flight.dart:9, controller.dart:4, spring.dart:2 и morph_context_menu.dart:7. В единице 2 движение движка `MorphMotion` (src/motion.dart:24), `MorphController` и симуляции flight переходят на `MorphSpringState` и получают внутреннее имя `FlightSprings`, сами классы умирают в 5.3. |
| Собственный решатель в `MorphSpringState` | 2 | SDK `SpringSimulation`, совпадение с fixtures в пределах 1e-9. |
| `isAtRest(tolerance)` в 70+ местах, диалект запросов с явным `t`, callback-поля движений | 2 | `reach` и `MorphRest`, advance-then-read, `drainEvents` (C, duplications 3). |
| `MorphClock` mixin, `MorphControlHost` и около 16 собственных State | 3 | `MorphMotionClock` и общие механизмы host; обязательность базы `MorphHost` решается на switch, меню и sheet до массового перевода (C, duplications 8, 9). |
| `MorphFrameSync` (live.dart:75), microtask `_sync` (glass_channel.dart:326) | 3 | Вариант, выигравший P3. |
| `AnimationController` в scroll_indicator.dart | 3 | Движение через общие механизмы host в подтверждённой единицей 3 форме. |
| `AnimationController` и `SpringSimulation` в navigation_stack.dart | 5.2 | Движение navigation на `MorphMotionRoute`. `ScrollSpringSimulation` в navigation_bar.dart остаётся, прокрутка принадлежит Flutter. |

### Системы темы

| Что | Единица | Почему безопасно |
| --- | --- | --- |
| `MorphTheme` движка как ThemeExtension, `MorphWidgetsTheme`, `MorphWidgetsThemeScope`, обход предков `_themeHost`, три ручных разрешения appearance | 4 | `MorphThemeData.appearances` и `morphAppearanceOf` (C, duplications 4, 5). |
| `MorphGlassScope`, `MorphAdaptiveGlass`, `MorphGlassMaterial` | 4 | Поле `MorphThemeData.glass` и `MorphGlassStyle`. Материал toolbar выводится из роли (R, inventory 9). |
| Импорты `material_ui` в theme.dart, show.dart, route.dart, flight.dart, widgets_theme.dart, morph_context_menu.dart, а также `package:flutter/material.dart` в widgets_theme.dart (d84e1253) | 1, 4 | route.dart уходит в единице 1. theme.dart, widgets_theme.dart и morph_context_menu.dart чистятся в единице 4. В flight.dart и show.dart единица 4 заменяет `Theme.of(context).colorScheme` (flight.dart:1699) и чтения `MorphTheme.default*` (flight.dart:579-582) на `MorphThemeData`. В morph_context_menu.dart Material-символов нет (C, duplications 10). |
| `flutter_shaders` | 4 | Единственный helper `setFloatUniforms` переносится в `scene/shaders.dart` (R, boundaries). |
| `equatable` | 1 | Ноль импортов в lib, test и example (R, dead). |

### Дубли рендеринга и мёртвый код

| Что | Единица | Почему безопасно |
| --- | --- | --- |
| `MorphLiveBackdropFilter`, `LiquidGlassLayer.existsIn`, `consolidatesFakeSurface`, `backdropKey` scope, `consolidatesFakeBackdrop`, `LiquidGlassVisibility` | 1 | Нет вызовов, проверено `/usr/bin/grep` (R, dead). |
| `navigation_snapshot.dart` и `MORPH_NAV_SNAPSHOT`, `MORPH_SHADER_SHADOWS`, `MORPH_ANALYTIC_CAPSULE`, `MORPH_ANALYTIC_MODE=always` | 1 | Отклонённые эксперименты (ab5b970, R). `GlassCostProbe` переезжает в тестовый helper. |
| Kill switches выпущенных путей (`MORPH_ANALYTIC_GEOMETRY`, `FLAT_SHADER_BODIES`, `BACKDROP_CACHE`, `SHADER_FROST`, `EDGE_HALF_RESOLUTION`, `EDGE_FOLDED_FADE`, `TITLE_LAYER`) | 6 | Остаются matte-путь (больше 8 форм, меню) и трассированный flat-путь (больше 4 boxes). |
| `LiquidGlassShapeFrame`, семейство `LiquidShape`, пресеты `LiquidGlassSettings`, `LiquidGlassAppearance`, `LiquidGlassColorModel` | 6 | Рендерер читает `MorphSurface`, материал выводится из роли и стиля одной таблицей (R, inventory 8, 9). |
| Четыре скрытых варианта `MorphGlassOutline`, `MorphOutlineBoxes`, `MorphGlassOutlineParts` | 6 | Один `MorphOutline`. |
| `_OutlineTracer` в glass_outline.dart, blend `angularBlendRadius` в `gpu/sdf.glsl`, `gpu/material_sdf.glsl` и `analytic_geometry.glsl` | 6 | Один tracer и `fused_law` после проверки паритета на iPhone (R, merge laws). |
| Painter-шов на Widget (`buildSurface`, `buildFill`, `buildBody`, `buildGlow`, `buildLayer`), `MorphGlassLayer`, путь `_painted` в `MorphGlassHost` | 6 | Tiers на `RenderMorphScene` и Canvas-шов (R, flow 2). |
| 18 проверок `glass == null` в 12 файлах и собственные `_XPainter` | 6 | Flat является tier, отсутствующего painter больше нет (C, duplications 7). |
| Шесть кешей shader | 6 | `MorphShaderRegistry` (R, shader caches). |
| Имена `MorphMorphFixedSource`, логи "FakeGlass", текст "frosted" в hook, имя файла transform_tracking_repaint_boundary_mixin.dart | 6 | Устаревшие имена (R, dead). |

### Публичные имена

`foundation.dart`, `motion.dart` и `widgets.dart` удаляются целиком в единице 7. Вместе с ними уходят `MorphMenuTuning`, `MorphBarMenuTuning`, `MorphPushZoomTuning`, `MorphZoomTuning`, `MorphScrollIndicatorTuning`, `MorphBarMetrics`, `MorphListMetrics`, `MorphToolbarMetrics`, `MorphNavigationBarMetrics`, `MorphLargeTitleScrollPhysics` (ноль использований), `MorphSheetRoute`, `MorphAlertRoute`, `pushMorphZoom` (его заменяет `MorphNavigationRoute(from:)`), `MorphGlassKind` (его заменяет `MorphGlassRole`), `MorphGlassOptics`, `MorphGlassGlow`, `MorphTabAccessoryEnvironment` и `MorphContentScroll`. Старый класс `MorphGlassRenderer extends MorphGlassPainter` (glass_renderer.dart:113) в единице 4 становится внутренним `GlassBuiltInPainter`, имя переходит к sealed выбору рендерера. У `motion.dart` нет production-потребителя (C, inventory). Отступы контента приходят через `MediaQuery.padding` от scaffold.

## Контракт представлений

- Результат. `showMorphSheet` и другие функции показа завершают future в момент логического pop, как `Navigator.push`. Визуальное закрытие продолжается после этого. Route завершается в видимом покое или в точке передачи хвоста источнику.
- Veto. Back, barrier и Esc проходят через `PopScope`. Отклонённый pop не запускает закрытие и не отдаёт результат. Программный `Navigator.pop` сохраняет семантику Flutter.
- Отмена predictive back. Движение возвращается к открытому состоянию непрерывно, со скоростью жеста. Future не завершается.
- Повторное открытие во время закрытия. Новый route продолжает движение от текущего владельца, то есть от закрывающегося route или от источника, который доигрывает посадку. Старый владелец останавливается в том же кадре. Содержимое строится заново.
- Потеря источника. `MorphSourceLink` отсоединяется и хранит последнюю геометрию и захваченные темы. Закрытие растворяет представление вместо посадки. Route не читает State и RenderBox исчезнувшего источника.
- Вложенный Navigator. Меню, контекстное меню, alert и popover date picker идут на root navigator. Sheet идёт на ближайший navigator вне собственного navigator `MorphNavigationStack`. Страницы `MorphNavigationRoute` живут внутри `MorphNavigationStack`.
- Возврат фокуса. При `reverse` SDK освобождает фокус с первого кадра закрытия. После завершения route focus scope нижнего route возвращает фокус по правилам Flutter. Покрывающий route получает ввод, нижнее содержимое сохраняет State.
- Замена route. `pushReplacement` держит заменённый route, пока новый не встанет в покой.
- Добавление без push и замена через `Navigator.replace`. `didAdd` и `didReplace` явно согласуют движение и `route.animation` с жизненным циклом SDK. Начальные `Pages` и restoration не оставляют видимую страницу с проекцией `dismissed`, пока внутренний controller уже завершён.

P2 разделяет transfer lease и право на ввод. Настоящий source hit проверяет всю цепочку modal/Navigator предков; текущий popup получает свой поток, cover отзывает held sequence. Отложенная отмена на границе model command и проверки transfer identity защищают повторный вход; page/barrier закрывающегося popup перестают захватывать hit синхронно. Уже подтверждённый release сохраняет action. SDK Escape/Router приоритеты не переопределяются; hidden Escape остаётся отдельным продуктовым решением. 217 проверок прототипов сохраняют прежние replay/40 hand-back/459 flat-кадров. Результат и оставшиеся границы — `menu-input-ownership.md`; P2 не закрыт.

P2 проверил перенос local themes через SDK `InheritedTheme.capture` до root Navigator. Source регистрирует inherited dependencies, каждый route публикует свой снимок post-frame; общий root theme и system environment остаются живыми. Обычные обновления значений сохраняют editor/focus/PopScope; theme kinds открытого route фиксированы, после source loss остаётся последний снимок. Source-local locale/RTL/MediaQuery и произвольные providers автоматически не переносятся. Это граница прототипа, продуктовая locale/RTL policy ещё не выбрана. 230 проверок прототипов; контракт и ограничения в `menu-source-environment.md`.

P2, 2026-10-17, уточняет semantic lifetime: один private stage вместо writable revealed/closing; скрытая preparation и логически закрытый popup исключаются из семантики SDK wrappers, сохраняя lazy mount и stable content/policy child. Source tap выполняет domain open с проверками всей modal/Navigator цепочки; свой hidden popup освобождает только ещё активную captured root page. Один route dismiss идёт через maybePop и существующий sync/async policy. Flow repaint инвалидирует semantic geometry без новой матрицы или ticker. Отмена noncurrent hidden preparation закрывает ввод, завершает целую модель и удаляет точный route на hand-back/settled boundary, сохраняя press-tail под прозрачным cover. 251 проверка прототипов, 341 example и анализатор без замечаний; прежние replay/scene показатели неизменны. Контракт `menu-accessibility-lifecycle.md`; native accessibility, early-push product choice и остальные P2 gates открыты.

P2 held-reopen, 2026-10-17: SDK route резервируется на принятом source down до ancestor Navigator Listener, но модель остаётся у прежнего route/source до фактического isOpen. Reservation route/transfer/sequence сохраняет обычный first-zero hand-back и outgoing content без paint borrowing. Новый route получает модель от настоящих clock/lease и строит свежую policy/editor tree; State внутри каждого представления стабилен. Passive cover сохраняет committed release work; Back/удаление отменяют свою попытку на фактическом владельце. Первый content mount под cover ждёт uncover, не захватывая focus. 275 проверок прототипов, 365 example, прежние 40 hand-back/459 flat-кадров и анализатор чистый. Контракт `menu-held-reopening.md`; native held/IME/assistive focus и остальные P2 gates открыты.


P2 source affinity, 2026-10-17: идентичности root Navigator, source View и реального overlay View образуют lifetime привязки. Новый root/View получает отдельную session при сохранённом публичном State; старый popup остаётся самостоятельным и не возвращает модель перемещённому source. Same-root nested move сохраняет session. Captured callbacks и live attachment checks запрещают stale acquisition/landing; dependency refresh немедленно отключает authority/clock, а наблюдаемый retirement идёт через microtask. Потерянный source-owned tail прекращается без скрытого ticker и без заявления о settled. Source/overlay из разных Views не презентуются. `menu-source-affinity.md` отделяет этот контракт от будущей живой root-space geometry; P2 открыт.


P2 measured admission, 2026-10-17: source-local rect и форма измеряются в настоящий root overlay до первого взаимодействия. Snapshot принадлежит сессии; global pointer переводится live inverse root map, source рисует полный contour через обратную карту. Root меню сохраняет собственные метрики. Поддержаны только positive uniform2D scale/translation; idle scroll/move обновляют существующую полностью покоящуюся модель при следующем admission. Активная потеря geometry отключает endpoint прежним безопасным detach, не меняя старую модель. Painter проверяет snapshot перед owner filter и подавляет stale tail при более позднем same-frame paint-only move.34 новые проверки/64 pixel-zero tail-кадра; `menu-source-geometry.md`. Это snapshot invalidation, не active follow, safe area/IME или полный P3; production shape ещё не переносится в main.


### Системный viewport P2, 2026-10-18

Measured snapshot дополнен доступным прямоугольником actual root overlay. Safe area и keyboard берутся из physical presentation View, объединяются максимумом по каждой стороне и переводятся через DPR и обратную uniform map. Пересечение учитывает уже уменьшенный overlay и его положение в окне. Из available выводится padding существующего idle-only relayout; source-local MediaQuery не отменяет системные ограничения. Непомещающиеся menu minimums и перекрытый source отклоняются до push.

28 новых проверок, 62 geometry cases; исходный и inset tail совпадают с независимым root renderer на 64 кадрах каждый. Active availability mismatch отключает endpoint прежним путём, без retarget старой модели. Показанный popup может остаться за клавиатурой; немедленная реакция settled popup и native IME policy не заявлены. Контракт `menu-viewport.md`, evidence `tool/audit/foundation-p2-2026-10-18/viewport/report.md`. P2/main gate остаются открытыми.


### Native button-menu IME endpoints, 2026-10-18

На реальном iPhone проверены 9 сцен: короткий контроль и двукратное повторение трёх tall-режимов. У длинного UIButton.menu первая строка при изначальной клавиатуре выше на 275pt; после её show/hide четыре наблюдаемых ряда и source сохраняют точные endpoints. Клавиатура перекрывает нижние строки ранее открытого меню. Интервалы snapshot отделены от responder command и завершения keyboard transition; отрицательный контроль отвергается. Контракт `menu-native-ime.md`, evidence `tool/audit/foundation-p2-2026-10-18/native-ime/report.md`.

Это ограничение для следующего дизайна placement/source validity, не изменение текущего Dart-прототипа. Право landing из row endpoints не следует; закрытие/выбор после IME, editor focus, context-menu trigger/preview и непрерывная оптика остаются непроверенными. Текущий conservative endpoint detach сохраняется до этих проверок; P2 открыт.
