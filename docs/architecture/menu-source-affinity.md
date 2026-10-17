# P2: source и граница представления

2026-10-17, база `d9973893`. Только root-menu прототип; продолжение `menu-held-reopening.md`. P2 открыт.

## Контракт вызывающего кода

```dart
final oldPopup = source.currentState!.open();
// Приложение переносит тот же GlobalKey source в другой root Navigator.
await nextFrame();
final newPopup = source.currentState!.open();
```

Публичный State сохраняется. Его наблюдения и команды относятся к новой привязке; старый popup остаётся в прежнем Navigator со своей моделью, clock, content State, focus и policy. Его закрытие и disposal не передают модель перемещённому source и не сбрасывают новую сессию. Возврат A → B → A создаёт третью сессию, а не возрождает первую. Перенос между nested Navigators одного root/View сохраняет сессию; право на ввод по-прежнему проверяет modal/Navigator цепочку.

## Приватная граница

Один immutable affinity хранит идентичности root Navigator, source FlutterView и FlutterView настоящего root overlay. Сама сессия служит токеном callbacks: source build, present, eligibility и attachment closures захватывают конкретную сессию. Перед работой они сверяют её с текущей и с живой привязкой. Deactivate запрещает ancestor reads до activate, но сам по себе не отсоединяет сессию. Изменения тем не создают новый lifetime.

Сессия создаётся после появления inherited dependencies. `TickerProviderStateMixin` допускает последовательные source clocks в одном State; старый clock уничтожается перед созданием нового. Старые route clocks принадлежат исходным Navigators. View ввода popup фиксирован на весь lifetime и больше не переписывается перемещённым источником.

Перед hand-back проверяются текущая сессия, живое прикрепление source, фактический route/lease и pinned Navigator. Потеря source необратима для этой сессии. В отличие от eligibility, attachment не требует current source page: её покрывает само меню.

## Завершение прежней сессии

Смена привязки происходит в том числе при заблокированном дереве. Поэтому source authority, pointer sequence и clock отключаются сразу; наблюдаемые cancel/route изменения выполняются в microtask, захватывающей только прежнюю сессию. Pending cancellation не может обойти эту границу при выходе из вложенной model command. Освобождение unused session идемпотентно.

Показанный popup остаётся самостоятельным: принимает новые menu pointers из прежнего View и обычное SDK/semantic dismissal. Его непрерывная модель завершается на прежнем route clock без посадки. Editor State, controller, focus и PopScope сохраняются.

Скрытая preparation не имеет самостоятельного содержимого: отменяет hold и pending open, закрывается до настоящего покоя на прежнем route clock и удаляет точный route, сохраняя cover. Reservation завершается один раз без позднего promotion или pop нового root. Уже подтверждённое, но ещё скрытое открытие также отменяется при потере attachment.

Если модель уже вернулась source и доигрывает хвост, смена привязки прекращает её сэмплирование. Это **брошенный хвост**, который может остаться численно не settled. Его не переносят, не принуждают к покою и не обслуживают невидимым дополнительным ticker. Новая сессия начинается независимо в покое.

## Проверки и границы

Три исправных исходных контрпримера воспроизводят старый activeRoute после move, чужой hand-back и принятие pointer нового View старым popup. Расширенный набор проверяет два настоящих root Navigator, сохранённый GlobalKey State, A → B → A, nested relocation, closing и source-owned tail, held/committed hidden preparation под cover, reservation до и после hand-back, stale source callbacks, factory reentry и повторный вход из отложенной отмены.

Multi-View стенд использует два настоящих framework View/render tree с публичным TestFlutterView. Второй View не выводит Scene/Semantics в ОС; это host proof владения и маршрутизации, а не проверка нативных окон. Source под другим View относительно root overlay отклоняет raw/semantic acquisition; явный `open()` выбрасывает StateError до push.

Геометрия по-прежнему фиксирована. Идентичность root/View не доказывает совпадение global pointer space и локальных координат painter: offsets, scale, scroll, rotation, insets и active retargeting остаются следующим рубежом. Между разными Views преобразование координат не выдумывается. `MorphMenuMotion.relayout` пока допускает только idle.

17 новых проверок дают 292 прототипа и 382 example, анализатор без замечаний. Все 20 replay, восемь async timing records, backdate control и шесть flat-сцен/459 кадров совпадают с предыдущим этапом.

Результаты и точные хеши: `tool/audit/foundation-p2-2026-10-17/source-affinity/report.md`. Production model/host/clock/timeline, transfer adapter, tuning, зависимости и exports не меняются. Native multiwindow/accessibility/IME, устройство/perf, полный menu API и бар/оптика остаются открытыми.
