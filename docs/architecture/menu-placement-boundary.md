# P2: граница расчёта размещения и проверки source paint

2026-10-18, база `f96094e4`. Внутренняя перестройка example-прототипа; поведение admission и active retirement сохраняется. Это не новая публичная архитектура библиотеки и не разрешение landing после IME.

## Вызов

```dart
ProbeMenuSource.measured(
  button: localButton,
  menuBuilder: buildMenu,
)
```

Параметры прежние. State измеряет attachment, RenderBox, uniform transforms и конечную форму source. `_admitMenuPlacement` принимает эти проверенные данные вместе с presentation View и minimum из tuning. В одной операции находятся чтение физических safe/IME metrics, max вместо суммы, DPR/inverse projection, пересечение с overlay, minimum-fit и полное вхождение кнопки. Результат — допустимый available rectangle или null. Отдельного пути projection без admission нет.

Это операция без изменений состояния, но она читает живые свойства FlutterView; её результат относится к моменту наблюдения. Нового MediaQuery, observer, ticker или скопированного набора SDK metrics нет.

## Snapshot и authority

Сессия хранит один `_MenuGeometry`; available и source-факты не получают независимые mutable lifetimes. Padding выводится из available/bounds. Полный `agrees` по-прежнему требует identity source/overlay, map/button/bounds/source shape и available equality. Null полного reader, включая непомещающийся minimum или покрытый source, сохраняет прежний смысл.

`admitGeometry` допускает relayout той же модели только в полном закрытом source-owned покое. Snapshot устанавливается перед readiness callback; после него остаются повторные проверки модели, attachment и свежей геометрии. Любое наблюдённое активное расхождение по-прежнему необратимо отзывает старый endpoint, даже если метрики восстановлены до кадра. Показанный popup сохраняет прежнюю модель/placement/input, hidden preparation и reservation завершаются адресно, source tail останавливается без скрытого ticker.

## Paint

Measured source painter вызывает `session.readSourcePaintGeometry()` внутри прежнего `measured && restingButton != null`, до проверки owner. Метод сохраняет snapshot перед `checkGeometry`, затем при закрытом idle делает дополнительный fresh read/full agreement. Если переносимый contour рисовать нельзя, painter использует прежнюю resting форму.

Метод может отозвать source через `checkGeometry`, поэтому это явно вызываемая операция, а не getter. Он скрывает от painter условия session lifetime и оставляет same-frame land→layout fence на прежнем месте. Fixed replay и route painter не получают source-only проверку. Source clock, input, route sampling и hand-back сохраняют свои прежние проверки и порядок: отзыв source не запрещает старому popup закончить движение и принимать последующий ввод.

## Выбор и границы

Вариант с отдельным immutable endpoint внутри admission жизнеспособен, но пока все потребители требуют полного admission. Выбрана граница операций без дополнительного типа или аллокации endpoint. Два кандидата и свежий judge оценивали один и тот же контракт; это независимые запуски одной модели. Дополнительное сравнение только source-полей не добавлено без настоящего потребителя.

[Native selection/reopen](menu-native-ime.md) подтверждает новое размещение на новом открытии и функциональное переиспользование source. Оно не определяет непрерывную оптическую посадку или возврат при движении source. Здесь эти разные вопросы названы и расчёт placement локализован, но combined validity намеренно остаётся консервативной. Для будущего разрешения endpoint при недопустимом новом placement потребуется пересмотреть nullable reader после соответствующих измерений.

Проверка использует прежние geometry/callback/paint сценарии и independent contour oracles без изменения ожиданий; результаты и ревизии — [отчёт](../../tool/audit/foundation-p2-2026-10-18/placement-boundary/report.md). P2, P3, optical gate и перенос на main остаются открытыми.
