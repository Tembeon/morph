# P2: измерение source в root overlay

2026-10-17, база `67afab10`. Только прототип; P2 открыт. Продолжение `menu-source-affinity.md`.

Следующий этап 2026-10-18 добавляет системную доступную область: [safe area и клавиатура](menu-viewport.md). Описанный ниже нулевой padding относится к исходному этапу, не к текущему measured admission.

## Вызов

```dart
ProbeMenuSource.measured(
  button: const Rect.fromLTWH(24, 80, 44, 44),
  sourceHeight: 64,
  sourceRadius: 22,
  pointerInput: true,
  menuBuilder: (_) => const EditorMenu(),
)
```

`button` задаётся локально относительно source. Размер представления берётся из настоящего root overlay; пользователь не передаёт Matrix4, размеры экрана или controller. Параметры sourceHeight/sourceRadius описывают исходную форму, а не размеры меню. `onMotionReady` позволяет стенду настроить существующую модель после измерения, до первого open/pointer command. Это экспериментальный API, не новая публичная форма библиотеки.

Обычный конструктор `ProbeMenuSource` сохраняет фиксированное пространство записей: его button/bounds, фабрика модели и соседи служат контролем replay. Продуктовая совместимость со старым API этим не добавляется.

## Пространства

Один private snapshot сессии хранит source/overlay RenderBox identity, source→overlay map, точный button, фактические overlay bounds и масштабированные sourceHeight/radius. Модель, popup painter и Flow работают в root-overlay logical coordinates. Масштаб source меняет исходную форму; ширина меню, строки и параметры движения остаются в единицах root.

Original global pointer используется для времени, identity и наблюдений. Только для вызова неизменённого transfer adapter создаётся копия с position в overlay. Обратная карта root→global читается заново. В исходном этапе движение всего root сохраняет локальную геометрию модели и endpoint; с viewport admission это верно лишь при неизменном effective available rect (см. `menu-viewport.md`). Source painter отображает полный переносимый контур обратно в свой canvas; popup не получает дополнительного source transform.

Разрешены только конечные положительные равномерные 2D scale и translation. Коэффициенты семейства проверяются точно; rotation, shear, anisotropic scale, reflection, perspective, singular и nonfinite не заменяются bounding box. Произведения масштаба на размеры формы тоже должны быть конечными. Чужой FlutterView по-прежнему недопустим.

Перед admission нужны laid-out/attached boxes и source вне Offstage; вся кнопка должна находиться внутри overlay. Это консервативный допуск, не полная проверка ancestor clipping, opacity или occlusion. Placement padding в этом этапе нулевой: safe area и keyboard insets пока не учитываются, адаптация к IME не заявлена.

## Начальное состояние и callbacks

До измерения существует номинальная модель в покое: её frame имеет source-local координаты, source рисуется локально. Она не получает input/open и не публикует measured samples, включая ignored global pointer. Это частная граница стенда, не контракт готового MorphSourceLink.

Перед первым взаимодействием сессия измеряет source и обновляет существующую модель через idle-only relayout. Допуск требует source lease, отсутствия route/reservation/pointer, !presented/arming/pending и полного покоя. Одного isSettled недостаточно: открытое неподвижное меню тоже settled. После полного закрытия idle movement/scroll учитываются при следующем admission без замены модели.

`onMotionReady` вызывается один раз на модель, после установки snapshot. Повторный вход проверяет current session, model и geometry. SDK persistent phase (build/layout/paint) отклоняется до relayout/callback/push, даже если boxes уже имеют размеры. Синхронный open до layout или с неподдержанной геометрией выбрасывает StateError без отложенного открытия; raw/semantic activation просто отклоняется.

## Потеря геометрии

Во время активного lifetime snapshot фиксирован. Изменение source→overlay карты, исходной формы или overlay size отключает endpoint; активная модель не пересоздаётся и не retargets. Новый source получает свежую private session через безопасную microtask, старые callbacks не перенаправляются на неё.

Показанный popup сохраняет свой model/clock/content/policy и завершает движение самостоятельно, без посадки на сместившийся source. Hidden preparation и reservation завершаются адресно прежним путём. Уже переданный source-owned tail прекращается и может остаться численно не settled; скрытого retirement ticker нет.

Проверки стоят перед admission, source sampling, вводом, hand-back и source paint. Painter проверяет геометрию до проверки owner, даже когда модель у popup. Это наблюдаемая инвалидация snapshot, а не постоянное сопровождение source: неподвижный popup может обнаружить изменение только при следующем наблюдении.

Tick-time hand-back предшествует build/layout. Если source перемещается позже в том же кадре, paint fence подавляет устаревший tail и завершает endpoint. Уже записанный handBack остаётся фактом передачи на момент проверки; его не удаляют задним числом. Полная согласованность фаз остаётся задачей P3.

## Проверки и оставшиеся границы

Три исходных ошибки: настоящий tap после offset не открывает меню; scaled root ломает tap; первый popup frame появляется с центром (46,102) вместо измеренного (126,142). Новые проверки добавляют фактические размеры/смещение overlay, DPR 1/2, source scale без масштабирования menu metrics, настоящий hold/move/up и выбор строки, semantic/programmatic admission, idle movement/scroll, invalid matrices, pre-layout и повторный layout, callback reentry/cover, hidden/reserved/shown/tail loss.

Pixel-стенд сравнивает переносимый source contour с независимо управляемой моделью в root space. Включён последний кадр покоя: ранняя подмена renderer обычным RRect давала реальную разницу и удалена. Retained paint и same-frame land→layout проверяются отдельно. 34 проверки проходят отдельно и внутри полного example: 416 тестов, анализатор без замечаний. Новая сцена совпадает на 64 tail-кадрах; прежние replay/async/459 flat-кадров неизменны. Итоговые конфигурации — `tool/audit/foundation-p2-2026-10-17/source-geometry/report.md`.

Не доказаны active follow/retargeting при scroll/resize/rotation, safe area/IME policy, произвольные affine/3D source shapes, полная видимость/clipping, native multiwindow/assistive focus, оптика и устройство/perf. Production model/clock/timeline, transfer adapter, измеренные параметры, зависимости и exports не меняются. P2 и переход на main остаются открытыми.
