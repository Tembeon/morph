# Композиция стекла и устройство liquid-слоя

База `809c5fd4` (main, 2026-10-19). Владелец принял проект 2026-10-19 (ответы ниже); миграция идёт шагами M0 - M9 на ветке `glass-composition`. Два связанных предмета: (1) как поверхности делят чтение подложки и фильтры; (2) границы модулей внутри `lib/src/glass/renderer/rendering/liquid_glass_layer.dart` и шов между ним и виджетным слоем.

## Проблема

**Композиция.** Решение "что читает это стекло и в каком проходе оно рисуется" сегодня принимают шесть механизмов в двух слоях и в разное время:

| механизм | что решает | где и когда | доказательства |
|---|---|---|---|
| `BackdropGroup` / `useBackdropGroup` / `backdropKey` | общее чтение: снимок у первого члена | виджеты (`GlassAdaptiveScope`, `glass_tier`, `menu.dart`, локальная группа в `LiquidGlassLayer`), build | одно общее чтение экономит 0.2 - 0.5 ms GPU (аудит 2026-10-12) |
| `MorphChromeBackdrop(Scope)` | ключ полосы баров, контента шторки, контекстного меню; заодно не пускает бары в контейнер страницы | виджеты, build | то же |
| `MorphGlassContainer`, `MorphGlassStage`, `Gate`, `Barrier`, `StageFade`, `GlassRasterAnchor` | слить стекло нескольких хостов в один слой (один matte, один фильтр) | элементы: `still` кадра, обход предков, `admit` по числу форм, бит `joined` в структуре хоста | iPhone 16/32 кнопки raster p50 2.50 -> 1.19 / 3.53 -> 1.46; Pixel 4/8 кнопок -18/-22 % raster; под масштабом выигрыша нет (3611bf0) |
| `solidBackdrop` (слой, контейнер, stage) | рисовать шейдер поверх цвета, без фильтра | параметр слоя | list stages IDENTICAL (host max 1) |
| `GlassBackdropCache(Route, Scope)` | рисовать поверх кэша маршрута под презентацией | scope + render | шторка GPU 515 -> 393 ms/s, 1119 -> 833 mW |
| плоскость (`exp/glass-plane`, `MORPH_GLASS_PLANE`) | один объект фильтра на группу, члены рисуют свои прямоугольники | addToScene | Pixel GPU p95 12.3 -> 12.8 ms на кнопках шторки: выигрыша нет, не слита (1025eb21) |

Правила допуска продублированы: `morphGlassJoinLook` + `morphGlassContainerReaches` (элементы) против `_planeIneligibility` + `poolPlane` (render). Вход и выход из контейнера - смена структуры хоста, то есть пересборка его стеклянного дерева при каждом нажатии, glow или движении. `MorphGlassFrame.still` пишут 11 производителей ради одного читателя (допуск в контейнер).

**Liquid-слой.** 3247 строк смешивают выбор шейдера и упаковку uniform, matte-путь (точные rest-матты, плотность), analytic-путь и его rest-режим, композицию (ключи, идентичность фильтра, слои, seed, solid, кэш), glow и зонды стоимости. Узлы, которые агент не видит из одного места:

- индексы uniform: 29 литеральных `setFloat(N)` и 4 `initialIndex` в 8 методах, зеркало деклараций GLSL; прототип плоскости дописал девятый;
- правило идентичности фильтра (движок копирует uniform в нативный фильтр при конверсии): флаг `_shaderInputsChanged = true` пишется в 9 местах; от него зависят glow без перерисовки и ревизия плоскости;
- состояние экземпляров шейдера (`_staleShaders`, `_solidShaders`: новый `FragmentShader` не обнулён);
- результат геометрии присваивается по полям в двух местах (`paintFrame`, `refreshRetainedGeometry`);
- зонд стоимости прошит через 5 методов (10 ссылок `debugGlassCostProbe`);
- аналитические шейдеры выбираются по позиции в списке (`_analyticSet[2]` = tint), а не по таблице вариантов;
- мёртвый параметр `LiquidGlassLayer.outlineOf` (читал только удалённый fake tier).

Виджетный слой импортирует 20 разных внутренних файлов рендерера.

Ограничения из Phase A, которые форма обязана соблюсти:

- подложка никогда не опаздывает на кадр (owner);
- член общей группы читает проход таким, каким он был у первого члена (Impeller, iOS resolve texture; так же правило UIKit для стекла в контейнере); контент, нарисованный между членами, второй член не видит, и это нельзя обнаружить покадрово (у картинок нет границ);
- слить можно только там, где порядок отрисовки принадлежит владельцу плоскости: слитое стекло рисуется в позиции плоскости, под всем, что нарисовано внутри неё;
- analytic: до 8 форм и 600 000 device px, однородный вид или различие только по tint; matte: до 32 форм; Metal: 31 слот деклараций; frost-варианты держат 64 регистра на Mali-G78;
- `alwaysNeedsAddToScene`-слой не смеет вызывать `markNeedsAddToScene` (сеттер `BackdropFilterLayer.filter` вызывает);
- два GalleryApp в одном host-тесте попадают в одно из двух дискретных состояний (max 121): A/B только внутри одного приложения;
- composition на Pixel стоит машинерия Impeller: живое чтение 0.4 - 1.1 ms раз за кадр, две MSAA-проходки и композит на отдельную поверхность (0.2 - 0.8 ms в сценах аудита), frost и шейдер внутри фильтра 0.4 - 2.0 ms на больших поверхностях. Реорганизация композиции сама по себе выигрывает мало; её цель - меньше движущихся частей и ноль пересборок, а производительность допускается только по замеру.

Upstream `liquid_glass_renderer` 1.0.0-dev.0 (46e875d) устроен как исходник morph до форка: один `LiquidGlassLayer` = один фильтр, чтение делится через `BackdropGroup` / `backdropKey`, слияние геометрии через `LiquidGlassBlendGroup`, слой 1731 строка без разделения на модули. Модели композиции, которую можно взять, там нет; полезный прецедент только в разделении на виджет/render-база/blend group.

## Использование (взгляд вызывающего)

Приложение. Ничего не оптимизирует; публичная поверхность не растёт.

```dart
// Стекло всех контролов читает экран один раз на плоскость.
MorphTheme(data: data, child: app);

// Ряд кнопок, между которыми приложение ничего не рисует: один проход.
MorphGlassContainer(
  child: Row(children: [MorphGlassButton(...), MorphGlassButton(...)]),
);

// То же на непрозрачном цвете страницы: без чтения подложки вовсе.
MorphGlassContainer(solidBackdrop: pageColor, child: row);

// Секция, нарисованная поверх раннего стекла, читает своё.
BackdropGroup(child: section);
```

Автор виджета пакета. Объявляет плоскости, не стратегии.

```dart
// Контент шторки: стекло над шторкой читает один снимок.
GlassPlaneScope(child: content);

// Бар навигации и тулбар экрана делят одно чтение.
GlassPlaneScope(readKey: _barsBackdrop, child: bar);

// Карточка секции списка: порядок отрисовки принадлежит пакету, строки рисуют
// текст между стеклом, но вне его контуров; стекло видит только цвет ячейки.
GlassPlaneScope(
  paintOrder: GlassPaintOrder.outsideGlass,
  backdrop: GlassBackdrop.solid(look.cellColor),
  child: rows,
);

// Маршрут презентации: стекло со своим чтением рисует поверх копии маршрута ниже.
GlassPlaneScope(backdrop: GlassBackdrop.cached(backdropCache), child: sheet);

// Строка, чья подсветка рисуется под аксессуарами, выводит их из слияния.
GlassPlaneBreak(active: highlightShown, child: accessories);

// Поиск: пока тулбар гаснет, плоскость только делит чтение.
GlassPlaneScope(
  paintOrder: fading ? GlassPaintOrder.shared : GlassPaintOrder.owned,
  child: toolbar,
);
```

Painter (`glass_liquid_draw.dart`). Каждый хост всегда строит свой слой; ветки `joined` нет.

```dart
LiquidGlassLayer.live(
  live: source.live,
  settingsOf: () => settings.value,
  fieldOf: fieldOf,
  glowOf: () => glow.value,
  glows: source.glows,
  read: chrome ? GlassRead.own : lifted ? GlassRead.lifted : GlassRead.plane,
  child: shapes,
);
```

Тесты и инспектор читают перепись плоскости, а не обходят элементы.

```dart
final census = RenderGlassPlane.debugCensusOf(tester.element(find.byType(MorphListSection)));
expect(census.strategy(button), GlassStrategy.merged);
expect(census.splitReason(pressed), 'glow');
```

## Форма

### Модель

**Плоскость** - единица композиции: набор стекла, которое читает одну подложку. Каждый `LiquidGlassLayer` с `read: plane` принадлежит ровно одной плоскости, ближайшей сверху; корневую ставит `GlassAdaptiveScope` (там, где сейчас `BackdropGroup`). Стекло с `read: own` (плавающий хром: бары, меню, шторка, алерт) и `read: lifted` (поднятая линза, ручка, бегунок; seed вокруг себя) плоскостью не является: решать там нечего, кроме подложки, которую оно наследует от ближайшей объявленной (`cached`).

Плоскость - это **объявление** (виджетная сторона) плюс **стратегия** (render-сторона, один владелец):

- объявление: `readKey` (общий ключ нескольких поддеревьев, иначе свой), `paintOrder` (что владелец гарантирует о рисовании между плоскостью и её стеклом), `backdrop` (live, solid, cached);
- стратегия выбирается `RenderGlassPlane` на каждом своём paint, до отрисовки членов, из render-фактов этого кадра.

| стратегия | допускается | что делает Impeller | доказательства | статус |
|---|---|---|---|---|
| split | всегда | свой фильтр, layer pass и композит у каждого члена; чтение общее по ключу | база | сейчас: группы |
| merged | `paintOrder` owned или outsideGlass; члены в покое; совместимый вид | один geometry-проход и один фильтр в позиции плоскости, клип по объединению | контейнеры (таблица выше); под масштабом нет выигрыша | сейчас: контейнеры и stages |
| painted | `backdrop` solid или cached | `drawRect` финального шейдера, без фильтра | solid list stages; кэш шторки | сейчас: `solidBackdrop`, кэш |
| pooled | - | один фильтр на весь снимок, члены рисуют свои прямоугольники | Pixel 12.3 -> 12.8 ms GPU p95, без выигрыша | не строится |

Стратегии приватны: добавить или удалить строку таблицы - изменение одного файла и одного замера на Pixel; вызывающие не меняются.

**Допуск члена в merged** - одна функция `RenderGlassPlane._admit` над фактами этого кадра (порядок проверки = порядок отказа в переписи):

1. плоскость объявляет owned или outsideGlass; для outsideGlass у члена нет frost (иначе ядро размытия читает текст строк: бывший `sharpOnly`);
2. член читает плоскость (`read: plane`), не поднят, без glow, без пропуска размытия;
3. между слоем члена и плоскостью нет render-объектов, меняющих пиксели: opacity (кроме видимости тега при 1), клипы, image/color filter, shader mask, backdrop filter, follower, viewport, нетрансляционный transform, активный `GlassPlaneBreak` (бывшие reach check, `Barrier`, `StageFade`);
4. плоскость не масштабирована относительно своего прохода (бывший `Gate`, теперь выводится);
5. настройки равны, вид равен с точностью до tint, суммарно не больше 32 форм;
6. геометрия члена в покое по `GlassRestWatch` (тот же сторож, что у analytic `changes`; бывший `still`).

Остальные члены этого кадра - split. Сдвиг растровой фазы каждого слитого члена считается от его собственного слоя: слой и есть якорь (`GlassRasterAnchor` не нужен).

Инварианты в типах:

- `GlassRead` - один enum вместо пары булевых `shared` + `ownBackdrop`, комбинации которых были неявными;
- `GlassBackdrop` - sealed: solid и cached не могут встретиться на одном слое;
- `GlassGeometry` - sealed: `AnalyticGeometry` | `MatteGeometry`; кто держит матт, не держит аналитических форм;
- `GlassPlaneMember` - интерфейс фактов члена: плоскость не видит приватных полей чужого слоя.

Чего модель не делает: не группирует автоматически стекло корневой плоскости в один проход (порядок отрисовки страницы не принадлежит пакету); не меняет правило чтения у первого члена; не опаздывает подложкой (все стратегии читают текущий кадр; кэш - по прежнему правилу "никогда не старше").

### Типы

Объявления (`lib/src/glass/renderer/plane/glass_plane.dart`, всё `@internal`, кроме `MorphGlassContainer`):

```dart
/// What the glass of a plane reads.
sealed class GlassBackdrop {
  /// The backdrop as it stands where the plane's first glass paints.
  const factory GlassBackdrop.live() = LiveGlassBackdrop;

  /// One opaque color is all the glass would read.
  const factory GlassBackdrop.solid(Color color) = SolidGlassBackdrop;

  /// A copy of the route below, re-taken when what the glass samples changes.
  const factory GlassBackdrop.cached(GlassBackdropCache cache) = CachedGlassBackdrop;
}

/// What the owner of a plane guarantees about painting between the plane and
/// its glass.
enum GlassPaintOrder {
  /// Members share the read and paint their glass at their own place.
  shared,

  /// Nothing paints between the plane and its members' glass.
  owned,

  /// Content paints between, never inside a member's glass outline.
  outsideGlass,
}

/// Where one glass layer reads its backdrop.
enum GlassRead {
  /// The nearest plane's read.
  plane,

  /// A read of its own: chrome that floats over content.
  own,

  /// A read of its own around its glass: a small frost that animates.
  lifted,
}

/// Declares a plane for the glass in [child].
class GlassPlaneScope extends SingleChildRenderObjectWidget {
  const GlassPlaneScope({
    required super.child,
    this.paintOrder = GlassPaintOrder.shared,
    this.backdrop = const GlassBackdrop.live(),
    this.readKey,
    super.key,
  });

  final GlassPaintOrder paintOrder;
  final GlassBackdrop backdrop;

  /// A read shared with other scopes (a screen's bars), or null for its own.
  final BackdropKey? readKey;

  @override
  RenderGlassPlane createRenderObject(BuildContext context) =>
      throw UnimplementedError();
}

/// Keeps the glass in [child] out of a merge while [active].
class GlassPlaneBreak extends SingleChildRenderObjectWidget {
  const GlassPlaneBreak({required this.active, super.child, super.key});

  final bool active;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      throw UnimplementedError();
}
```

Стратегия (`plane/render_glass_plane.dart`):

```dart
enum GlassStrategy { split, merged, painted }

/// What a plane reads from a member, compared by value each paint.
@immutable
final class GlassMemberFacts {
  const GlassMemberFacts({
    required this.read,
    required this.settings,
    required this.look,
    required this.shapeCount,
    required this.glows,
    required this.lifted,
    required this.blurPass,
    required this.resting,
  });

  final GlassRead read;
  final LiquidGlassSettings settings;

  /// The appearance with its tint cleared.
  final LiquidGlassAppearance look;
  final int shapeCount;
  final bool glows;
  final bool lifted;
  final bool blurPass;
  final bool resting;
}

abstract interface class GlassPlaneMember {
  GlassMemberFacts get facts;

  /// The member's shapes go to [plane]'s merged pass while non-null.
  set mergedInto(RenderGlassPlane? plane);
}

class RenderGlassPlane extends RenderProxyBox {
  BackdropKey get readKey => throw UnimplementedError();
  GlassBackdrop get backdrop => throw UnimplementedError();

  void join(GlassPlaneMember member) => throw UnimplementedError();
  void leave(GlassPlaneMember member) => throw UnimplementedError();

  /// A member's facts changed without this plane painting: a glow, a lift,
  /// new settings, a tag hiding it.
  void memberChanged(GlassPlaneMember member) => markNeedsPaint();

  @override
  void paint(PaintingContext context, Offset offset) {
    // TODO: admit members from this frame's facts; hand the admitted shapes
    // to the merged pass's link and the rest back to their own; paint the
    // merged pass (a LiquidGlassLayer over that link) under the child.
    throw UnimplementedError();
  }

  @visibleForTesting
  static GlassPlaneCensus debugCensusOf(Element element) =>
      throw UnimplementedError();
}
```

Liquid-слой после разделения (`rendering/liquid_glass_layer.dart`, координатор):

```dart
class RenderLiquidGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin, MorphLiveBinding
    implements GlassPlaneMember {
  final GlassFinalPass _pass;
  final GlassGeometryEncoder _encoder;
  final GlassBackdropDraw _draw;
  GlassGeometry? _geometry;

  set glow(LiquidGlassGlow? value) {
    // TODO: _pass.writeGlow(value); a merged member tells its plane; else
    // _draw.refreshFilter(_pass) or markNeedsPaint.
    throw UnimplementedError();
  }

  @override
  void paintFrame(PaintingContext context, Offset offset, Rect? bounds) {
    // TODO: states empty / idle / active; _adopt(_encoder.encode(...)) once;
    // _pass.write(_geometry!); _draw.paint(context, offset, bounds, _pass).
    throw UnimplementedError();
  }
}
```

Финальный проход (`pass/final_pass.dart`, `pass/final_pass_layout.dart`):

```dart
/// The float indices of the final shader's uniforms, in the order
/// liquid_glass_final_render_core.glsl and analytic_geometry.glsl declare
/// them; test/final_pass_layout_test.dart reads the GLSL.
abstract final class FinalPassLayout {
  static const int size = 0;
  static const int matteBounds = 2;
  static const int common = 6;
  static const int materialCenter = 34;
  static const int mapping = 47;
  static const int frostFlags = 53;
  static const int backdropBounds = 55;
  static const int matteScale = 59;
  static const int shrinkAxis = 63;
  static const int solidBackdrop = 65;
  static const int glow = 69;
  static const int analytic = 81;
}

/// The final shader of one glass pass: its variant, its uniforms and the
/// one image filter over them.
final class GlassFinalPass {
  GlassFinalPass(Map<LiquidShaderVariant, FragmentShader> matte);

  /// Picks the variant from [LiquidShaderVariant]'s switches, never by list
  /// position.
  void select({
    required GlassGeometry geometry,
    required LiquidGlassAppearance appearance,
    required bool frost,
  }) => throw UnimplementedError();

  void writeCommon(LiquidGlassSettings settings, LiquidGlassAppearance appearance) =>
      throw UnimplementedError();
  void writeMapping(GlassPassMapping mapping) => throw UnimplementedError();
  void write(GlassGeometry geometry) => throw UnimplementedError();
  void writeGlow(LiquidGlassGlow? glow) => throw UnimplementedError();

  /// The same object while no uniform changed since it was made: the engine
  /// copies the uniforms into the native filter when it converts it.
  ImageFilter filter({required double blurSigma}) => throw UnimplementedError();

  Paint paintOver(Color solid, Size deviceSize) => throw UnimplementedError();
  Paint paintOverCopy(ui.Image copy, Offset corner, Color overlay) =>
      throw UnimplementedError();
}
```

Геометрия (`geometry/glass_geometry.dart`, `geometry/glass_rest.dart`):

```dart
sealed class GlassGeometry {
  Rect get matteBounds;
  Offset get materialCenter;
  List<LiquidGlassAppearance> get appearances;
}

final class AnalyticGeometry extends GlassGeometry {
  /// The same shapes moved by [delta] device pixels, as a uniformly
  /// translated matte moves its bounds.
  AnalyticGeometry translated(Offset delta) => throw UnimplementedError();
}

final class MatteGeometry extends GlassGeometry {
  ui.Image get image => throw UnimplementedError();
  ui.Image? get material => throw UnimplementedError();
  double get density => throw UnimplementedError();
  Offset? get passPhase => throw UnimplementedError();
}

/// Encodes shapes, from one layer or from a plane's merged members, as
/// analytic uniforms or a matte.
final class GlassGeometryEncoder {
  GlassGeometry encode(
    List<GlassShapeInput> shapes, {
    required GlassEncodeContext context,
  }) => throw UnimplementedError();

  bool rasterGridStale(GlassGeometry geometry, Matrix4 layerToPass) =>
      throw UnimplementedError();
}

/// Counts unchanged geometry frames and asks for one more frame to settle.
final class GlassRestWatch {
  bool get resting => throw UnimplementedError();
  void noteFrame({required bool changed}) => throw UnimplementedError();
}
```

Композиция (`composition/backdrop_draw.dart`, `composition/glass_cost_probe.dart`):

```dart
sealed class GlassDrawPath {}

/// The engine layers one glass pass draws into and the mapping of its
/// fragment coordinates.
final class GlassBackdropDraw {
  void paint(
    PaintingContext context,
    Offset offset,
    Rect glassBounds,
    GlassFinalPass pass,
    GlassDrawPath path,
  ) => throw UnimplementedError();

  /// The compositing hook: a cached copy, or the filter for this frame.
  void composite(GlassFinalPass pass) => throw UnimplementedError();

  /// Compositor-only motion: clips and mapping follow without a paint.
  bool translate(Offset translation, GlassFinalPass pass) =>
      throw UnimplementedError();

  /// Hands the retained filter a new filter over changed uniforms; false
  /// when the pass must paint (glass recorded into a picture).
  bool refreshFilter(GlassFinalPass pass) => throw UnimplementedError();
}
```

### Карта модулей

| модуль | владеет | правила в его dartdoc | строк (оценка) |
|---|---|---|---|
| `rendering/liquid_glass_layer.dart` | виджет, `RenderLiquidGlassLayer`: состояния кадра (empty, idle, active), live-привязки, сеттеры, `_adopt` | порядок retained refresh; когда кодировать заново | 3247 -> ~700 |
| `rendering/liquid_glass_render_object.dart` | формы, retained-кадр, опрос компоновщика (как есть) | без изменений | 812 |
| `pass/final_pass.dart`, `final_pass_layout.dart` | варианты (из `liquid_shader_variants.dart`), экземпляры шейдеров, все записи uniform, устаревшие и solid-экземпляры, флаг входов, создание фильтра и paint | копия uniform при конверсии фильтра; новый шейдер не обнулён; 31 слот Metal; флаги frost; glow пропускается при нуле | ~500 |
| `geometry/glass_geometry.dart` | упаковка форм (базис, cull, rse, границы), допуск analytic и загрузка программ, кодирование матта, плотность, пиксели прохода, растровая сетка и фаза | 12-битный матт и nearest; плотность [0.5, 2]; material map при плотности 1; точный rest-закон; analytic <= 8 форм и 600 000 px | ~700 |
| `geometry/glass_rest.dart` | `AnalyticGeometryMode`, `GlassRestWatch`, возврат текстур, debug-флаги геометрии и реестр слоёв | покой после 2 кадров; возврат после 120; приложение уходит в idle | ~200 |
| `composition/backdrop_draw.dart` | handles слоёв движка, клип фильтра по корзинам пикселей, seed, solid-слот, кэш, отображение в проход, синхронизация с компоновщиком, замена фильтра для glow | клип размытия внутри прохода; начало seed-прохода; координаты paint у solid; кэш не старше кадра | ~600 |
| `composition/backdrop_cache.dart` | перенос из `internal/` | как есть | 444 |
| `composition/glass_cost_probe.dart` | все зонды: фильтр, ключ, solid, пропуск | зонды меняют пиксели и живут только на устройстве | ~80 |
| `plane/glass_plane.dart`, `render_glass_plane.dart` | объявления, членство, допуск, стратегии, перепись | чтение у первого члена; контракт `paintOrder`; таблица стратегий с доказательствами | ~550 новых, минус ~650 в `glass_container.dart` и `chrome_group.dart` |
| `liquid_glass_glow.dart` | упаковка glow и CPU-эталон (как есть) | одна подсветка на проход слоя | 127 |

Путь кадра проходит не больше трёх файлов:

- живой кадр: `MorphClock` -> хост -> `MorphGlassChannel.push` -> сеттеры `LiquidGlassLayer.live` / `LiquidGlass.live` -> [paint плоскости: допуск] -> `paintFrame` -> `encoder.encode` -> `pass.write` -> `draw.paint`;
- только glow: `MorphClock.glows` -> `MorphGlassHost(glows:)` -> `channel.pushGlows` -> `layer.glow` -> `pass.writeGlow` -> `draw.refreshFilter`, без paint; слитый член сообщает плоскости и выходит в split один раз;
- только компоновщик: persistent callback -> `runCompositorPoll` -> `draw.translate` -> `pass.writeMapping` -> замена фильтра.

### Шов с виджетным слоем

- `LiquidGlassLayer.live(live, settingsOf, fieldOf, glowOf, glows, read)` и `LiquidGlass.live(frames)`: всё, что painter даёт слою. Уходят `useBackdropGroup`, `backdropKey`, `blursOwnBackdrop`, `solidBackdrop`, `outlineOf` и локальная `BackdropGroup` слоя.
- `GlassPlaneScope`, `GlassPlaneBreak`: всё, что объявляют виджеты пакета.
- Хост (`glass_channel.dart`) теряет допуск в контейнер: `_container`, `_clearPath`, бит `joined` в структуре; `debugMorphGlassHostOf.joined` берётся из переписи. `MorphGlassFrame.still` удаляется вместе с 11 производителями.
- `glass_liquid_draw.dart` теряет ветки `joined ? GlassRasterAnchor(...) : _layer(...)` в `morphLiquidLayer` и `_slottedLayer`.
- Glow из `MorphClock` идёт прежним каналом; правило "одна подсветка на проход слоя" не меняется.
- `test/architecture_test.dart` запрещает `lib/src/widgets` импорт `renderer/internal/`, `pass/`, `geometry/`, `composition/`, `rendering/`; разрешены `renderer.dart` (экспорт шейдингового API, `GlassField`, `LiquidGlassGlow`, способности и прогрева) и `plane/glass_plane.dart`. Список исключений короткий и только сокращается.

### Глубина интерфейса

Виджетная сторона видит три типа объявлений и один enum чтения. За ними спрятаны три действующие стратегии, шесть групп фактов допуска, растровые сдвиги, кэш, seed и зонды. Сегодня автор виджета пакета выбирает из `BackdropGroup`, `MorphChromeBackdrop(Scope)`, `MorphGlassStage(open, sharpOnly, solidBackdrop)`, `Gate`, `Barrier`, `StageFade`, `GlassBackdropCacheScope` и двух булевых в `_layer`, и неверная комбинация компилируется. После: `GlassPlaneScope` с тремя полями и `GlassPlaneBreak`. Внутри рендерера `GlassFinalPass` прячет 17 вариантов, раскладку и правило идентичности фильтра за восемью методами; `GlassGeometryEncoder` прячет выбор analytic/matte, плотность и растровую фазу за `encode`; `GlassBackdropDraw` прячет пять путей композиции за четырьмя методами.

## Решение синтеза

Оба кандидата набросаны в этой сессии одной моделью (Opus 5.5) по runner-prompt архитектора. Независимых runner'ов и cross-judge не было: владелец запретил subagent'ов в morph из-за лимитов, а сессия, начатая другой сессией, не может стартовать новые. Это два прохода одной модели, а не согласие разных; разброс между кандидатами меньше, чем дала бы арена.

Рубрика (по 3 балла): (1) один владелец у каждого решения композиции; (2) изменение, верное в одном файле, верно для всего репозитория; (3) глубина интерфейса; (4) форма не зависит от неизмеренного выигрыша и удаляет проигравшее; (5) миграция малыми проверяемыми шагами, пиксели идентичны до намеренного шага.

| кандидат | суть | 1 | 2 | 3 | 4 | 5 | итого |
|---|---|---|---|---|---|---|---|
| A: плоскость на render-стороне | объявления на виджетах; стратегию и допуск решает `RenderGlassPlane` на paint из фактов кадра | 3 | 3 | 3 | 3 | 2 | 14 |
| B: плоскость на виджетной стороне | группы, chrome, контейнер и stage сливаются в один `MorphGlassPlane`; допуск остаётся элементным и структурным | 1 | 2 | 2 | 3 | 3 | 11 |
| D: вычитание | плоскость = только чтение и объявленная подложка; слияние удаляется | 3 | 3 | 2 | 1 | 3 | 12 |

Красные флаги (`design-red-flags.md`): у B раздвоенное владение (допуск собирают `still` кадра, обход предков, `admit` ссылки и `structureOf`), список, синхронизируемый руками (правило "всё, на чём ветвится дерево, в структуре" включает `joined`), импортируемые внутренности (инспектор зовёт `morphGlassContainerBlocker`), два способа (формы регистрируются в своём слое или в слое контейнера в зависимости от дерева). У A флаг риска: регистрация форм переключается между ссылкой члена и ссылкой слитого прохода, то есть у неё два возможных места; владелец переключения один (плоскость), ссылка члена только пересылает. У D флагов нет, но он удаляет оптимизацию, отгруженную по замеру (контейнеры), без нового замера; это нарушает правило допуска.

База - A. Привито:

- из B: объявленное переключение контракта вместо вывода всего из render-фактов. Затухание тулбара поиска (`paintOrder: shared` на время затухания) и скрытие тега (уведомление плоскости) знает пакет; угадывать их по альфе в обходе предков ненадёжно, потому что смена альфы не перерисовывает плоскость. Публичное имя `MorphGlassContainer` сохраняется (UIKit `UIGlassContainerEffect`);
- из D: таблица стратегий допускает строку только по замеру. После прогона 1025eb21 pooled не строится, а одиночные чтения (`own`, `lifted`) не становятся плоскостями из одного члена: объектов больше, решений нет.

Отклонено: pooled как стратегия (разбор ниже); C и E ниже.

### Может ли pooled окупиться

Нет, пока Impeller работает как сейчас. Путь равных фильтров (canvas.cc 1858 - 1890) вычисляет фильтр один раз над всем чтением, без подсказки покрытия: снимок размером с проход (на корне - весь экран, MSAA) и финальный шейдер над ним, с ранним выходом вне форм. Члены экономят только свой layer pass и композит.

- Экономия на члене: зонд `pooled` против `copy` дал 0.20 - 0.22 ms на сцену с двумя-тремя отдельными слоями и 0.79 ms на шторке (около пяти слоёв), то есть около 0.1 - 0.16 ms на член.
- Цена пула: зонд `pooledShader` - около +0.3 ms над identity-пулом за вычисление шейдера над всем чтением; у настоящей плоскости ещё analytic в покое вместо выборки матта (больше ALU на каждый пиксель стекла каждый кадр).
- Безубыточность: n x (0.1 - 0.16) > 0.3 + analytic в покое, то есть n >= 3 - 4 даже без штрафа покоя, и только в кадрах, где ни один член не распался (нажатие, glow, затухание, другой вид распадают всю плоскость: Impeller пулит ключ, только если все фильтры равны). Замер при n = 3 (10d4696e, Pixel 6a, один запуск на вариант): m/sheet/buttons-open-close GPU p95 12.3 -> 12.8 ms, 860 -> 897 mW; контроль m/sheet/open-close 7.4 -> 7.6 ms.
- Где n велико, pooled проигрывает другой стратегии: если порядок отрисовки принадлежит владельцу, merged считает один фильтр под клипом объединения, а не всего прохода; если не принадлежит (стекло приложения в корневой плоскости), члены разбросаны по экрану, чтение полноэкранное, а интерактивные экраны распадаются на каждом касании.

Значит, композиция идёт другим путём: merged там, где пакет или приложение владеют порядком отрисовки, painted там, где подложка объявлена или кэширована, split везде ещё. pooled станет осмысленным только с подсказкой покрытия для пути равных фильтров в движке (альтернатива E). Рычаги GPU остаются внутри поверхности (frost и шейдер внутри фильтра, площадь больших поверхностей) и в объявленных подложках, а не в композиции.

Проверка синтеза: шаги миграции M7 и M9 сохраняют каждую сегодняшнюю пару "кто с кем делит чтение" и "кто с кем слит" в покое, это host-проверяемо (`perf_counts` captures, `glass_backdrop_group_test`, переписи); выигрыш по сборкам и поведение слияния на устройстве - только после M9b.

## Принятые компромиссы

- Мы принимаем, что `RenderGlassPlane` читает render-факты членов и обходит их предков на paint, в обмен на удаление обхода элементов, бита `joined`, `GlassRasterAnchor`, `Gate`, `StageFade`, `Barrier` и `MorphGlassFrame.still`.
- Мы принимаем перерисовку ближайшей границы плоскости, когда член входит в слияние или выходит из него (нажатие, glow, подъём), в обмен на ноль пересборок хоста. Сегодня это пересборка стеклянного дерева хоста.
- Мы принимаем, что слияние остаётся по объявлению (контейнер, stage), в обмен на гарантию никогда не рисовать стекло под контентом, которого пакет не видит. Стекло приложения вне контейнера получает только общее чтение, как сегодня.
- Мы принимаем перенос файлов (конфликты у параллельных сессий) ради модулей с одним владельцем; шаги переноса идут по одному и только перемещают код.
- Мы принимаем, что `GlassPlaneBreak` остаётся объявлением: подсветку строки под аксессуарами render-сторона не видит (у картинок нет границ).
- Мы принимаем, что смена стратегии merged <-> split сдвигает пиксели на 1 - 3 шага канала (растровая фаза), как сегодня вход и выход из контейнера.

## Рассмотренные альтернативы

- **B: плоскость на виджетной стороне.** Один `MorphGlassPlane` вместо групп, chrome, контейнеров и stages, допуск по кадрам при сборке. Дешёвая миграция (переименование и слияние), но интерфейс мелкий: вызывающие по-прежнему координируют `open`, `sharpOnly`, ворота и барьер, а каждое нажатие пересобирает дерево хоста. Проиграла по владению и безопасности для агента.
- **C: всё в шейдере.** Подсветка, видимость и glow по форме в финальном проходе, чтобы плоскость никогда не распадалась. Упирается в бюджет: frost-варианты уже на 64 регистрах Mali-G78, у fused tint 31 слот Metal занят полностью. Пересмотреть, только если когда-нибудь pooled выиграет и распад станет главной потерей.
- **D: вычитание.** Только чтение и подложка, без слияния. Меньше всего частей, но выбрасывает измеренный выигрыш контейнеров на плотных экранах (iPhone -52/-59 % raster p50, Pixel -18/-22 %) без нового замера.
- **E: патч движка.** Дочерний backdrop filter рисует результат прямо в родительский проход, снимки фильтра без MSAA, чтение из resolve на Vulkan: самый большой рычаг на поверхность, но нужен форк Flutter. Вне рамок.
- **Upstream как есть.** Один слой = один фильтр, группы для чтения, blend group для слияния: это исходная точка, от которой morph ушёл ради контейнеров, кэша и solid. Брать нечего, кроме деления файлов.

## Открытые вопросы и риски

Ответы владельца (2026-10-19):

1. Публичный API: остаются `MorphGlassContainer` (имя UIKit) и Flutter `BackdropGroup` (граница чтения, плоскости её уважают); нового публичного типа плоскости нет.
2. Моменты допуска, сдвинутые render-фактами относительно `still`, приняты как NEAR (1 - 3 шага канала).
3. Pooled отклонён: `performance.md` обновлён в f622f32c, прототип под тегом `archive/2026-10-19/exp/glass-plane`. Шаг pooled после M9c не строится.
4. Подсказки `MorphGlassInspector` берутся из переписи плоскостей.
5. Папки `pass/`, `geometry/`, `composition/`, `plane/` с запретами импорта в `architecture_test`, без `part`-файлов.

Риски:

- **Точность допуска между перерисовками плоскости.** Факты, меняющиеся без paint плоскости: сеттеры члена (glow, настройки, вид, подъём) - член зовёт `memberChanged`; скрытие тега - уведомление от его render-объекта; движение члена только компоновщиком - опрос форм в ссылке слитого прохода, как у контейнера сейчас; opacity-виджеты предков блокируют при любой альфе. Новый host-тест: член гаснет под собственным `Opacity`, пока плоскость удерживается.
- **Порядок форм при делегировании.** Формы переходят между ссылками на paint плоскости; порядок регистрации = порядок отрисовки, от него зависят маркеры blend и tie-правило analytic. Host-оракул слияния против сегодняшнего контейнера.
- **Конфликты с параллельной работой.** M1 - M5 перемещают код, который другие сессии правят сегодня. Каждый шаг - отдельный коммит, только перенос, после того как текущие слияния рендерера легли; координатор назначает окно.
- **Известные красные host-тесты на базе** (`blur_bound_host_test` 14 > 8, `shader_parity_host_test` regular-dark, `solid_backdrop_host_test` list section): фиксировать значения до шага и сравнивать с ними, не с зелёным.
- **Шум двух приложений в host Impeller**: A/B стратегий только внутри одного приложения (переключатель стратегии и повторное добавление слоёв).

## План миграции

Каждый шаг - один коммит (`git commit --only`), `flutter analyze` на нуле, `glass.md` и `VENDORED` правятся в том же коммите, что и поведение. Pixel 6a - только где меняется стоимость отрисовки, один прогон `tool/bench/bench.py` против `baseline.json`; прогоны собирает координатор в общий батч.

| шаг | изменение | удаляет | host-гейты | Pixel 6a |
|---|---|---|---|---|
| M0 | вычитание без поведения | `LiquidGlassLayer.outlineOf` и его pick в `_layer`; устаревший комментарий про `GlassShadow` | `glass_frames_test`, `perf_counts` без изменений | нет |
| M1 | `FinalPassLayout` + тест, читающий GLSL; литералы -> имена | 29 литеральных индексов | `analytic_geometry_test`, `glass_glow_shader_test`, `glass_rim_constants_test`, новый `final_pass_layout_test`; host Impeller `shader_parity_host_test`, `solid_backdrop_host_test`, `backdrop_cache_host_test`, `analytic_geometry_host_test` байт в байт против базы | нет |
| M2 | `GlassFinalPass`: варианты по таблице, записи, устаревшие и solid-экземпляры, флаг входов, фильтр, paint-over | позиционный `_analyticSet[i]`, разбросанные `_shaderInputsChanged` | M1 + `perf_counts` (все liquid-сцены), `glass_frames_test`, `glass_glow_timeline_test`; новый host-тест: кадр только с glow не рисует и даёт новый объект фильтра | нет |
| M3 | `GlassGeometryEncoder` + sealed `GlassGeometry` + единый `_adopt` | двойное присваивание по полям | `analytic_*_host_test`, `raster_phase_host_test`, `raster_phase_idle_host_test`, `scaled_matte_host_test`, `glass_raster_phase_test`, `perf_counts` (traced outlines, snapshots, idle) | нет |
| M4 | `GlassRestWatch` и владелец debug-флагов геометрии | статические флаги и реестр в слое | `analytic_mode_host_test`, `analytic_toggle_host_test`, `raster_phase_idle_host_test`, `perf_counts` idle frames | нет |
| M5 | `GlassBackdropDraw` + `glass_cost_probe.dart`; отображение в проход переезжает в композицию | 10 ссылок на зонд в слое | `frost_seed_host_test`, `solid_backdrop_host_test`, `backdrop_cache_host_test`, `glass_repaint_host_test`, `blur_bound_host_test` (против базы 14), `glass_backdrop_diagnostics_test`, `glass_inspector_test`, `perf_counts` captures и offscreen | нет |
| M6 | шов: `renderer.dart` экспортирует нужное виджетам; `architecture_test` запрещает внутренности | 20 прямых импортов -> короткий список исключений | `architecture_test`, весь `flutter test` | нет |
| M7 | объявления при тех же пикселях: `GlassPlaneScope` (ключ и подложка), `LiquidGlassLayer(read:)`; корень, `glass_tier`, меню, chrome, кэш, solid слоя и контейнера переходят на плоскости | `useBackdropGroup`, `backdropKey`, `blursOwnBackdrop`, `solidBackdrop`, `backdropCache` слоя, его локальная группа, `MorphChromeBackdrop(Scope)`, `GlassBackdropCacheScope` | `glass_backdrop_group_test`, `backdrop_section_test`, `tab_bar_accessory_glass_test`, `glass_inspector_test`, `perf_counts` все сцены (captures неизменны), `lifecycle_counts`, `glass_frames_test`, host-оракулы solid, cache, frost seed | нет |
| M8 | членство на render-стороне и перепись; инспектор читает перепись | обход элементов в подсказках инспектора | `glass_inspector_test`, `perf_counts` | нет |
| M9a | merged в `RenderGlassPlane` за `MORPH_GLASS_PLANES` (по умолчанию выкл): допуск из фактов, делегирование форм, сдвиг фазы от слоя члена, `memberChanged` | ничего | A/B в одном приложении против контейнера: `glass_container_test`, `list_glass_stage_test`, `glass_container_tag_test`, тулбар поиска, density-rest-4/8/16, max <= 3 шага; новый тест гаснущего члена; `perf_counts` с флагом | нет |
| M9b | включить: контейнеры и stages становятся плоскостями; хосты не ветвятся по `joined`; `paintOrder` вместо `open`/`sharpOnly` | `MorphGlassFrame.still` (11 производителей), бит `joined` в структуре | `perf_counts` (density-wave и search-press: сборки вниз, храповик), `lifecycle_counts`, `control_goldens` (flat без изменений), `glyph_strikes` без изменений, оракулы M9a, `glass_frames_test` | да, один прогон: стенд плотности n4/n8/n16 rest и wave, list, search-press, sheet (масштаб), controls page; время кадра и энергия |
| M9c | удалить наследие | `MorphGlassContainerScope`, `MorphGlassContainerLink`, `morphGlassJoinLook`, `morphGlassContainerReaches`, `morphGlassContainerBlocker`, `MorphGlassContainerGate`, `MorphGlassStageFade`, `MorphGlassStage`, `MorphGlassContainerBarrier` (-> `GlassPlaneBreak`), `GlassRasterAnchor`, `debugMorphGlassStagesOpen`, флаг `MORPH_GLASS_PLANES` | весь `flutter test` и `example`, `public_api_test` (диф `public_api.txt` по ответу на вопрос 1) | нет: те же пути, что в M9b |

Pooled после M9c не строится (ответ 3).

## Следующий шаг

M0, затем M1: вынести индексы uniform в `FinalPassLayout` с тестом, который читает декларации ядра GLSL, и заменить ими 29 литералов в слое, байт в байт на host-оракулах.
