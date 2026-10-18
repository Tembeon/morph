# How: viewport, safe area и IME в measured menu prototype

Дата: 2026-10-18. Read-only разбор исходников на `3095d2fe20308c17bc97ed8bcac7af541534b76f`; application code не менялся, тесты этим агентом не запускались. Роль: один scoped explainer по `how`, без дополнительных explorers. Прочитаны `CLAUDE.md`, `CLAUDE.local.md`, how/explainer prompt и pstack-runtime/config.

Репозиторий: `/Volumes/Dev/projects/morph`, logical alias `/Users/tembeon/IdeaProjects/morph`. Проверенный SDK: Flutter **3.47.7 stable**, revision `abaf9c523780a608bd46686fd5e53740a07077f8`, Dart **3.13.5**. SDK root `/Volumes/Dev/tools/mise/installs/flutter/3.47.7-stable`; версия из `bin/cache/flutter.version.json`. Упоминание 3.47.2 в repo rules уже не описывает фактическую установку. Ниже SDK anchors относительно этого root; repo anchors относительно репозитория.

## Overview

Measured source уже переводит исходную кнопку в координаты реального root overlay, а затем передаёт одну модель между source и popup. Safe area и keyboard пока отсутствуют: `ProbeMenuSource.measured` явно документирует нулевой padding (`example/lib/proto/menu_route_probe.dart:66`), а `admitGeometry` вызывает `relayout` без padding (`:717`). Поэтому следующий небольшой шаг — вычисление допустимого прямоугольника в overlay coordinates перед admission; это не требует новой модели анимации.

У активного меню геометрия зафиксирована на lifetime сессии. `MorphMenuMotion.relayout` игнорирует обновление вне idle; существующий host при изменении геометрии прекращает source endpoint и даёт показанному popup закончить своё движение. Нельзя объявлять эту конструкцию поддержкой активного следования за клавиатурой: такой policy и native timing ещё не измерены.

## Key Concepts

- `_MenuAffinity` связывает root Navigator и два `FlutterView`; source и presentation обязаны быть в одном view (`menu_route_probe.dart:153`, `:162`, `:499`). Insets нужно брать из presentation view, а не из произвольного source-local `MediaQuery`.
- `_UniformMap` допускает только конечный positive uniform scale + translation (`:516`). Отдельно валидируются source→overlay и overlay→global. Rotation/shear/perspective нельзя превратить в axis-aligned bounding box и продолжить как будто условия прежние.
- `_MenuGeometry` — pinned snapshot source/overlay identities, source→overlay map, button, bounds и source shape (`:565`). Обратное преобразование input использует **текущую** overlay→global карту (`:593`), поэтому перемещение целого root само по себе сейчас сохраняет локальную модель.
- `_MenuSession` владеет моделью, clock/input/reservation и endpoint lifetime (`:602`). `ProbeMenuTransfer` остаётся единственным адаптером владения; геометрия не создаёт нового writer.
- `FlutterView.viewPadding` и `viewInsets` заданы в **physical pixels**. Первый описывает частично перекрытые системными элементами края и не исчезает при keyboard; второй — полностью перекрытые края. `MediaQueryData.fromView` делит их на DPR (`SDK bin/cache/pkg/sky_engine/lib/ui/window.dart:198`, `:223`; `SDK packages/flutter/lib/src/widgets/media_query.dart:300`).
- `MediaQuery.padding` вычислен с учётом `viewInsets`; он не является неизменным safe-area perimeter. `SafeArea` и remove-фабрики вправе потреблять/менять descendant metrics (`SDK media_query.dart:503`, `:524`, `:1000`, `:1037`).

## How It Works

### Текущий admission и lifetime

`_readGeometry` находит source RenderBox и фактический `navigator.overlay` RenderBox, требует attached/laid-out конечные ненулевые размеры, отвергает Offstage и неподдержанные карты. Кнопка должна целиком лежать в overlay bounds; размеры source shape масштабируются source→overlay, menu metrics остаются root-local (`menu_route_probe.dart:192`). Это допуск геометрии, не доказательство полной видимости или отсутствия ancestor clipping.

Перед raw, semantic или programmatic открытием `admitGeometry` снимает snapshot. Только полностью idle source-owned сессия без route/reservation/pointer/presentation/arming/pending может выполнить `relayout` (`:684`, `:705`). Callback `onMotionReady` вызывается после установки snapshot, после чего проверяются model/session identity и свежая геометрия: пользовательский callback может переместить source или открыть cover. Persistent scheduler phase отвергается до relayout/callback/push.

Пока движение активно, `checkGeometry` сравнивает snapshot перед sampling, input, hand-back и source paint (`:695`, `:952`, `:1105`, `:1609`, `:1838`). При несовпадении `_loseGeometry` отключает старый endpoint и создаёт новую source session через microtask (`:247`). `detachSource` сразу снимает source authority и ticker, затем безопасно заканчивает hidden/reserved работу (`:980`). Показанный route продолжает владеть старой моделью; `land` запрещает возврат к недействительному source. Source-owned tail прекращается без скрытого ticker и может остаться численно unsettled.

Это **наблюдаемая** инвалидация: settled popup не имеет постоянного geometry watcher. Само изменение системных metrics не гарантирует немедленный вызов `checkGeometry`. Вводить listener и обещать моментальную реакцию — отдельное решение с проверкой фаз, а не следствие чтения FlutterView.

### Преобразование viewport для bounded поддержки

Рекомендуемая authority для этого узкого прототипа — системные metrics `session.affinity.presentationView` плюс реальные overlay box/bounds. Это осознанная политика: source-local `MediaQuery.removePadding`, `SafeArea` или подложный size не должны превращать системную клавиатуру в нулевой inset root popup. Consumer overrides для виртуального viewport, fold/display features и floating keyboard здесь не решены.

Пусть logical view size получается как physicalSize / DPR, а каждый закрытый край равен `max(viewPadding, viewInsets) / DPR`. Max, а не сумма, исключает двойное резервирование одной нижней полосы. Это предложенная conservative placement policy; SDK определяет сами metrics, но не поведение UIKit меню.

```text
FlutterView physical metrics
        ↓ divide by finite positive DPR
view-global allowed rectangle
        ↓ inverse overlay→global uniform map
allowed rectangle in overlay coordinates
        ↓ intersect with [0, overlay.size]
finite nonempty placement rectangle
        ↓ EdgeInsets relative to actual overlay bounds
idle-only MorphMenuMotion.relayout(padding: ...)
```

Нужно преобразовать **положения краёв**, а не просто разделить сырые inset numbers. Для overlay map `global = local * s + offset` left безопасной зоны равен `(safeGlobal.left - offset.dx) / s`; аналогично остальные края. После intersection padding — расстояния от границ overlay до полученного прямоугольника. Overlay, уже заканчивающийся выше keyboard, получает bottom=0; смещённый вниз overlay не должен снова резервировать уже оставленный status-bar gap. Root scale влияет на единицы этих расстояний. Если root частично вне view, пересечение учитывает также невидимую часть, даже когда все системные insets нулевые.

`_UniformMap.inverse` уже даёт нужную точечную операцию (`:558`). Проверять надо конечность derived rectangles, deltas и преобразованных размеров: конечные исходные значения не гарантируют конечный результат деления на очень маленький scale. Пустой/перевёрнутый safe viewport должен отказать до callback/push, а не передать model отрицательное пространство.

В snapshot достаточно хранить эффективный padding/placement rect, влияющий на модель. Raw metrics могут меняться без изменения доступного пространства конкретного overlay; такая перемена сама по себе не требует новой сессии. Напротив, движение всего root теперь может изменить его пересечение с системным safe rectangle, даже если source→overlay и bounds неизменны. Тогда это реальное изменение placement; прежнее обещание сохранения endpoint при root movement применимо только когда effective placement тоже сохраняется.

### Ограничения существующей модели

`MorphMenuMotion._cap` ограничивает высоту safe area и `maxHeight`, но имеет минимум **rowHeight + 2×verticalPadding** (`lib/src/widgets/menu_motion.dart:1460`). `_place` всегда использует **tuning.menuWidth**, не сжимает ширину (`:2934`). Статический `place` сначала выбирает направление по середине safe area, выравнивает по кнопке и затем clamps левый/верхний край (`:2785`). Если safe rectangle уже fixed menu width или ниже model minimum height, clamp не делает результат помещающимся. Поэтому conservative admission должен отклонить такой viewport либо отдельно определить новый product/model policy; молчаливое сжатие означало бы изменение измеренных metrics.

`relayout` увеличивает revision, но затем немедленно возвращается при `_phase != idle` (`:1470`). `updateLayout` меняет content/cards/height, не обновляет `_bounds`/`_padding` и не заменяет active geometry relayout (`:1495`). Протаскивание keyboard metrics туда не создаст корректного active retargeting.

## Where Things Live

| Место | Назначение |
| --- | --- |
| `example/lib/proto/menu_route_probe.dart:192` | RenderBox measurement и геометрический допуск |
| `example/lib/proto/menu_route_probe.dart:565` | Snapshot identity и global pointer mapping |
| `example/lib/proto/menu_route_probe.dart:684` | Idle-only capture, active snapshot loss |
| `example/lib/proto/menu_route_probe.dart:980` | Endpoint retirement без лишнего writer |
| `example/test/proto/menu_source_geometry_test.dart:291` | Smaller/offset/scaled root и DPR1/2 |
| `example/test/proto/menu_source_geometry_test.dart:411` | Existing root movement invariant |
| `example/test/proto/menu_source_geometry_test.dart:674` | Independent root-space tail pixel oracle |
| `lib/src/widgets/menu_motion.dart:1460` | Safe area height cap и idle-only relayout |
| `lib/src/widgets/menu_motion.dart:2794` | Pure placement with padding |
| `lib/src/target.dart:446` | Legacy engine helper для safe area + keyboard; источник идеи, не готовый корректный scaled-root adapter |
| `docs/architecture/menu-source-geometry.md:29` | Явно оставленные safe area/IME/P3 ограничения |
| `SDK packages/flutter/lib/src/widgets/media_query.dart:2337` | Framework metrics observer и обновление fromView data |

## Gotchas

1. Legacy `_morphOverlayInsets` использует ambient `MediaQuery.size` и вычитает global overlap, но не переводит полученное расстояние обратно через overlay scale (`lib/src/target.dart:486`). Его прямое переиспользование сломает scaled root; этот разбор не разрешает менять legacy engine.
2. `getTransformTo(null)` даёт global **logical** pixels; DPR применяется к FlutterView metrics один раз. Дополнительное деление pointer или overlay map на DPR будет ошибкой (`SDK rendering/object.dart:3661`). Метод игнорирует `paintsChild`, поэтому наличие карты не доказывает видимость.
3. Чтение `FlutterView` само по себе не подписывает widget на изменения. `MediaQuery.fromView` подписывается через `WidgetsBindingObserver` и вызывает `_updateData` из `didChangeMetrics` (`SDK media_query.dart:2353`, `:2388`, `:2409`). Source локальный MediaQuery dependency не является надёжным уведомлением, если его metrics были удалены/заменены. Для bounded наблюдаемой политики достаточно проверять fresh metrics в существующих fences; proactive reaction требует отдельного явно проверенного механизма.
4. Нельзя вызывать inherited dependency getters из painter или принимать post-frame bounds за текущие при уже обновившихся physical metrics без phase constraints. Текущий admission phase guard и source paint fence остаются обязательными.
5. Новый placement snapshot должен охватить hidden prep, reopen reservation и source tail, а не только показанный route. Изменение metrics в `onMotionReady` должно провалить повторную проверку до push. Insets ни в коем случае не дают stale callback право попасть в свежую session.
6. Минимальная проверяемая матрица: status/home inset; keyboard до открытия; unequal overlap на четырёх краях; already-safe smaller overlay; translated/scaled root; DPR1/2; source-local fake/removed MediaQuery; empty/too narrow/too short viewport; active shown/hidden/reserved/tail snapshot loss; idle recapture после полного close; callback reentry; zero-insets replay/pixels unchanged.
7. Неизвестно: сохраняет ли UIKit открытый menu при IME appearance, пересчитывает ли направление/scroll/anchor, когда и по какой кривой это делает. Current native passport/geometry document не доказывают эту policy. Host-only fail-closed endpoint behavior можно проверить как наш прототипный контракт, но нельзя называть native parity или завершённой IME integration.
