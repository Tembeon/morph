# P2: владение вводом и вложенное закрытие

2026-10-16, база `cfade883`. Только `example/lib/proto/`; P2 не завершён, продуктовый presenter не выбран. Продолжение `menu-route-lifecycle.md`.

## Вызов приложения

```dart
ProbeMenuSource(
  pointerInput: true,
  menuBuilder: (_) => PopScope<void>(canPop: canDismiss, child: menu),
)
```

Настройка источника ввода или отдельная policy приложению не нужна. SDK `Navigator`, scopes, focus, Actions и Router dispatcher сохраняют свои обязанности. Глобальный перехват клавиатуры не добавлен.

## Три права

| Право | Владелец | Основание |
|---|---|---|
| Начать source gesture | Source Listener | Настоящий hit, primary button, View и currentness всех modal/Navigator предков |
| Принять новый pointer для меню | Session | Её текущий non-closing route в том же View |
| Продолжить принятую последовательность | Session | Точный объект sequence, pointer/view IDs и живая eligibility |
| Продвигать физику и рисовать | Transfer lease | Один текущий владелец модели, независимо от нового input |

Binding-global router остаётся транспортом. Совпадение координат с кнопкой больше не даёт права захватить новый source gesture. После hand-back отсутствие `activeRoute` тоже не является таким правом. Соседний source под невидимой текущей подготовкой проверяет всю цепочку modal routes, поскольку его ближайшая nested page может всё ещё быть current.

View берётся из настоящего source context и сохраняется при независимом исчезновении source. Смена View отзывает sequence; входящие pointer/view IDs сверяются. Это не доказательство полноценной работы в нескольких View или произвольного cross-view hosting: отдельного multi-View стенда здесь нет.

## Отзыв и повторный вход

Потеря текущего route на cover немедленно очищает session sequence. Приватный leased `cancelPointer` отменяет удержание на текущем каноническом времени модели через существующий `motion.pointerCancel`; поддельный `PointerCancelEvent` в binding не создаётся. Поздние физические move/up/cancel не возобновляют старое взаимодействие после uncover.

Если callback выполняется внутри model command, отмена откладывается до выхода из самого внешнего вызова. Есть один depth и один idempotent cancellation slot для точного transfer; очереди произвольных операций нет. Отмену нельзя применить к новому transfer после принудительного удаления route. Source и route clock advance используют ту же границу.

Перед pointer command выполняется advance к единожды рассчитанному stamp, затем повторно проверяются sequence, transfer, lease и eligibility. Это нужно, потому что due action может перекрыть/удалить route до выполнения самого up. После pointer command проверка повторяется: `onTrackedHighlight` может изменить навигацию внутри down/move. Устаревший event/time не публикуется с frame новой модели. Отложенная отмена после command убирает glow/flex, которые метод успел запланировать после callback.

Это не прерывание внутреннего `runDue`. Один advance выполняет due work до возврата. Уже подтверждённый отпусканием action сохраняется, исполняется один раз в измеренное время и может выполниться под cover. Отзыв живого удержания запрещает его последующему up подтвердить ещё один выбор. Полная выборочная отмена pending actions потребовала бы другого контракта модели/typed effects; timeline не очищается и модель не заменяется ради обычного cover.

## Hit testing при закрытии

Логический pop опережает следующий widget rebuild. Старые page и barrier до этого rebuild могли перекрывать настоящий source. В pointer-прототипе обе поверхности обёрнуты приватным RenderProxyBox, который читает live `closing/disposed` прямо в hitTest и сразу пропускает hit ниже. Отрисовка и передача хвоста продолжаются. Публичный render API и собственная библиотечная система gestures не добавляются.

Сохраняется прежнее правило раннего push: Source Listener готовит route на down только при `activeRoute == null`. Расширение этого правила на уже closing route было отклонено: оно преждевременно меняло lease и готовность содержимого. Записанные быстрые tap-reopen сохраняют все 40 hand-back, а не только равенство чисел геометрии. Удерживаемый reopen до hand-back и непрерывность stateful content/focus при таком переносе ещё не доказаны; этот проход их не объявляет исправленными.

## Пассивное движение и SDK TickerMode

Отзыв ввода не закрывает меню, не обнуляет springs и не останавливает часы по `!isCurrent`. Под прозрачным cover видимый source-tail продолжает завершаться. Непрозрачный route штатно приглушает State ticker через SDK `TickerMode`; невидимый хвост заканчивается после uncover. Обходить это приглушение ради теста не нужно. Продуктовый clock и его формулы не менялись.

## Escape и Back: проверенные области

| Сцена | Проверенный результат |
|---|---|
| Невидимая подготовка, обычный или nested WidgetsApp, Escape | Фокус остаётся source; подготовка не закрывается клавишей |
| Та же сцена, настоящий binding platform Back | Root preparation отменяется, builder не вызывается |
| Раскрытый popup, обычный или nested WidgetsApp, Escape | SDK action текущего popup закрывает меню |
| Router с `PopNavigatorRouterDelegateMixin`, platform Back | Root delegate передаёт Back своему Navigator, подготовка закрывается |
| Router с обработавшим Back приоритетным child dispatcher | Child получает Back, root preparation остаётся текущей |

Hidden Escape определяется сохранённым focus и ближайшим SDK `DismissIntent` action, а Router Back — явным приоритетом dispatcher. Это характеристики конкретных стендов. Они не обещают root-first для любого приложения, кастомных Actions, редактора/IME или accessibility. Библиотека не меняет глобальный приоритет клавиш и не перехватывает событие в другом окне.

## Синтез и доказательства

`architect`: A сохраняет global transport с ограниченной authority; B маршрутизирует каждый physical pointer отдельно и приобретает ввод через локальные поверхности. У B для pre-render outside input всё равно нужен временный global bridge и protocol публикации hit surface. Выбран A (13/15 против 10/15); взяты разделение acquisition/transport и синхронный closing hit gate из B. Дополнительный early push для closing source удалён. Кандидаты и judge — разные запуски одной модели, не multi-model consensus.

23 новых проверки покрывают closed/open source под cover, held source/menu sequence, немедленный uncover, committed release, повторный вход из tracking/due callbacks, принудительное удаление, source-tail/TickerMode, два source и SDK Escape/Back/Router. Всего 217 проверок прототипов. Измеренные replay/константы/допуски не меняются. Отчёт: `tool/audit/foundation-p2-2026-10-16/input-ownership/report.md`.

Остаются: принятие цены раннего root push, pre-handback held reopen и stateful content/focus, multi-View и преобразование source geometry, inherited context/доступность, оставшийся menu API, полный бар/оптика, устройства/perf и граница уже выданного SDK pop success.
