# P2: safe area и клавиатура в координатах overlay

2026-10-18, база `3095d2fe`. Продолжение [измерения source](menu-source-geometry.md). Только прототип в example; P2 открыт.

## Вызов

```dart
ProbeMenuSource.measured(
  button: localButton,
  menuBuilder: buildMenu,
)
```

Новых параметров нет. Перед открытием прототип измеряет доступную область настоящего root overlay. Кнопка должна целиком находиться в ней. Если фиксированная ширина меню или минимальная высота строки не помещаются, programmatic open бросает StateError до callback/push. Raw и semantic activation отклоняются. Измеренные размеры меню не сжимаются.

Обычный `ProbeMenuSource` сохраняет фиксированные координаты replay и прежний нулевой padding. Это контроль эксперимента, не обязательство сохранять старый продуктовый API.

## Системная область

Источник метрик — `session.affinity.presentationView`, общий для source и overlay. Physical size, viewPadding и viewInsets переводятся в logical pixels через DPR. На каждой стороне берётся максимум safe area и keyboard inset. Складывать их нельзя: нижний home inset не добавляется поверх уже занимающей его клавиатуры.

Из view-global безопасного прямоугольника через обратную positive-uniform карту overlay→view получается overlay-local прямоугольник. Он пересекается с настоящими bounds overlay. Расстояния от краёв overlay до этого пересечения становятся padding для существующего idle-only `MorphMenuMotion.relayout`.

Так root, уже заканчивающийся выше клавиатуры, получает bottom=0. Смещение и масштаб root меняют положения границ и единицы расстояний; копирование чисел MediaQuery было бы неверно. Частично находящийся за пределами View root также ограничивается пересечением.

Source-local MediaQuery, включая удалённые padding и подложный size, не отменяет системные ограничения popup. Это выбранная политика прототипа. API виртуального viewport, display features, fold и floating keyboard с непрямоугольным перекрытием этим не определяются.

На границе проверяются finite positive DPR/size, finite nonnegative сырые отступы, вычисленные координаты и размеры. Конечная матрица может дать переполнение при обратном делении на очень малый scale, поэтому проверяются и производные значения. Пустой или перевёрнутый прямоугольник отклоняется. Минимальные размеры берутся из tuning фактической модели, без копирования констант.

## Snapshot и активная смена

Один immutable `_MenuGeometry` хранит эффективный `available`, а padding выводится из него и bounds. Agreement сравнивает доступный прямоугольник, а не сырые метрики или глобальную матрицу. Изменение keyboard inset, не затрагивающее меньший overlay, сохраняет сессию. Движение всего root сохраняет её только при неизменной эффективной доступности.

Пересчёт существующей модели допустим лишь при полном закрытом покое source, без pointer, route или reservation. Snapshot устанавливается до onMotionReady; после callback геометрия и authority измеряются повторно. Изменение метрик внутри callback не позволяет протолкнуть устаревший push. Если callback уже открыл popup повторным входом, обнаруженное расхождение отзывает его endpoint. Недопустимая активная геометрия также отзывает endpoint сразу при admission; восстановление метрик до следующего кадра не возвращает старое право landing.

Активное расхождение использует прежний sticky detach. Показанный popup сохраняет прежние модель, время, content и placement; к старому source он больше не возвращается. Он может остаться за появившейся клавиатурой. Hidden preparation и reservation заканчиваются адресно, source-owned tail останавливается без скрытого ticker и может остаться численно unsettled. Новая source session не наследует старые callbacks.

Проверки выполняются в существующих admission/input/frame/hand-back/paint точках. Отдельного observer или постоянного ticker нет. Settled popup может заметить смену метрик лишь при следующем наблюдении. Это ограниченный контракт admission и безопасной потери endpoint, не active IME following и не нативная keyboard policy. Same-frame paint fence сохраняется; полная согласованность фаз остаётся P3.

## Выбор архитектуры и проверки

Два независимых запуска одной модели предложили snapshot extension и attachment-owned WidgetsBindingObserver. Свежий judge выбрал snapshot: дополнительный lifecycle observer не улучшает расчёт placement, а его уведомление settled popup сейчас не требуется. Из второго варианта взяты явная проверка minimum tuning и тест frozen MediaQuery. Это сравнение нескольких запусков, не нескольких моделей.

Новый сценарий сначала воспроизвёл меню до y=266 при доступной границе y=254. После исправления проходят 28 новых проверок и все 34 прежние geometry-проверки. Матрица покрывает все стороны safe area/IME, максимум вместо суммы, DPR 1/2, translation/scale, меньший уже безопасный overlay, точный width/minimum-height fit, narrow/short/empty/covered-source decline, inverse overflow, callback reentry, invalid admission с восстановлением до кадра, настоящий MediaQuery.removeViewInsets, settled/frozen observation, idle reuse и active shown/hidden/reserved/tail loss.

Независимая root-space модель с заданным padding совпадает с переносимым source contour на 64 кадрах хвоста, включая покой. Исходная zero-inset сцена также сохраняет 64 совпадающих кадра. Это host same-renderer доказательство; оптика, устройство и поведение UIKit здесь не проверены.

Полные результаты, SDK baseline, reviews и хеши — [viewport report](../../tool/audit/foundation-p2-2026-10-18/viewport/report.md). Production model/clock/timeline, prototype transfer/clock, tuning, зависимости и exports не меняются. Main не затрагивается.
