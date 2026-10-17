# P2: семантика и время жизни меню

2026-10-16–17, база `65dce59f`. Только root-menu прототип в `example/lib/proto/`. Продолжение `menu-source-environment.md`; P2 открыт.

## Вызов приложения

```dart
ProbeMenuSource(
  semanticLabel: 'Show actions',
  menuSemanticLabel: 'Actions',
  menuBuilder: (popupContext) => const EditorMenu(),
)
```

Это имена кнопки и представленного route. Значения по умолчанию явно относятся к прототипу; продуктовый localization API не вводится. Содержимое использует обычные SDK widgets и PopScope. Отдельного semantic controller, копии модели или искусственных PointerEvent нет.

Публичный `open()` открывает меню в обоих режимах стенда. Ранний настоящий pointer-down и model-driven presentation вызывают приватную preparation без дополнительной команды открытия. Поэтому измеренные hold/drag и tap deadline сохраняются.

## Один lifetime, разные обязанности

Единственный `_MenuStage` заменяет прежние writable `closing` и `_revealed`. Lease/disposal по-прежнему определяют владельца модели.

| Stage | Content | Семантика popup | Ввод |
|---|---|---|---|
| preparing | Не смонтирован | Отсутствует; нижняя страница остаётся доступна | Исходный held pointer, подготовка |
| shown | Смонтирован | Scoped/named route, один dismiss action | Текущий владеющий route |
| closingPreparation | Не смонтирован | Отсутствует | Закрыт |
| closingContent | Сохраняет State до визуального завершения | Исключена; нижняя страница снова доступна | Закрыт |

SDK ExcludeSemantics оборачивает всю barrier-ветвь, включая её BlockSemantics. Невидимая preparation не скрывает страницу. При логическом pop семантика закрывающегося меню исчезает до окончания оптического хвоста. Это не заставляет раньше размонтировать редактор или policy.

Scoped/named Semantics, Flow, theme wrapper и policy передаются как стабильный `ValueListenableBuilder.child`. Stage builder меняет только lazy mount и исключение семантики. Иначе переход shown → closingContent повторно запускает menuBuilder; первый полный прогон воспроизвёл восемь таких регрессий, исправленных без изменения старых тестов.

Семантическое присутствие не проверяет `isCurrent`: modality покрывающего route остаётся обязанностью SDK. Право выполнить сохранённый action строже и проверяется синхронно. Hit testing, requestFocus и paint lifetime сохраняют свои обязанности.

## Доступное открытие

Источник объявляет одну именованную кнопку с tap action. В закрытом состоянии проверяется currentness всей цепочки modal/Navigator предков. Для собственной hidden preparation допускается только точная identity её исходной root page, которая ещё `isActive`; остальные nested предки обязаны оставаться current. Одного `State.mounted` недостаточно: removeRoute делает страницу неактивной раньше следующего pump и удаления её State.

Сохранённый action не открывает меню под новым root/nested cover, после удаления страницы, из shown/closing или устаревшего popup. Собственная current preparation может перейти в открытое меню через domain-команду. Held pointer предварительно отменяется; его последующий физический up не создаёт action.

Transfer, lease, route и source eligibility перепроверяются после отмены указателя, advance/open и наблюдаемого `.open`. Callback может синхронно покрыть или удалить route. Такие изменения прекращают оставшуюся публикацию; отдельный флаг разрешения не хранится. Явный программный `open()` сохраняет свою роль управляемой вызывающим команды.

`expanded` вычисляется при сборке source. Открытый modal popup скрывает source; отдельная подписка для наблюдения expanded под modal barrier не вводится и этим проходом не обещается.

## Доступное закрытие

Показанный route имеет один dismiss action. Callback принимает только свой живой current/shown владеющий route и вызывает SDK `maybePop`. PopScope veto, async permission, coalescing и LocalHistoryEntry проходят существующий протокол. Командный SDK barrier сохраняет физический tap, но не дублирует dismiss action. Удаление source само по себе не лишает независимо живущий popup права закрыться.

Сохранённый dismiss после cover или логического pop не закрывает чужую страницу. Более сильная атомарность уже выданного успешного ответа и последующего SDK commit не доказана.

## Отмена скрытой preparation под cover

Reentrant callback отмены указателя может поставить другой экран поверх preparation. Обычный `Navigator.pop()` в этот момент закрывает cover. Немедленный `removeRoute(preparation)` выбирает верный route, но generic disposal сбрасывает ещё живую модель и обрывает видимое через прозрачный cover расслабление кнопки. Оба варианта воспроизведены и отвергнуты.

Current preparation сохраняет прежний SDK pop. Noncurrent preparation входит в closingPreparation через общий приватный `_beginClosing`, без вызова ложного SDK didPop. Ввод и семантика закрыты, прежние часы завершают целую модель. В существующей точке hand-back или полного покоя оставшийся `isActive` route удаляется по identity; sampling сразу завершается. При успешной передаче disposal уже не владеет моделью. Если скрытая idle-модель не входит в closing phase, удаление ждёт полного покоя, включая press channel.

Прозрачный cover проверяется отдельным replay: исходная модель и непрерывная reference получают те же pointer/cancel/close/frame команды и каноническое время. Press scale и время совпадают с `1e-9`; новая модель не создаётся до покоя прежней, cover остаётся current, menuBuilder не вызывается.

## Геометрия Semantics

Flow рисовал новую матрицу, сохраняя старую semantic geometry между repaint. После перевода physical bounds в logical pixels воспроизведено left `29.993305998578332` вместо `29.89416948953169`. Приватный RenderFlow при markNeedsPaint также помечает семантику dirty. Delegate остаётся единственным владельцем transform; отдельной матрицы, ticker и сборки content на каждом кадре нет. Проверка opening frames сохраняет исходную точность `1e-6`.

## Выбор, проверка и границы

Два независимых кандидата одной модели сравнили SDK Semantics/ExcludeSemantics и собственный render admission gate. Выбран SDK-вариант, 14/15 против 13/15; из второго сохранено разделение exposure/action authority и требование проверить Flow. Generic render gate не нужен. Независимый review обнаружил removed-source race; итоговый diff и сохранение press-tail приняты после воспроизведения.

21 новая проверка использует настоящие semantics actions в WidgetsApp-only harness, включая plain/nested source, stale callbacks до следующего pump, veto/async/local history, hidden/closing lifetime, геометрию и reentrancy. Всего 251 проверка прототипов и 341 example; анализатор без замечаний. Прежние replay/timing/flat-scene показатели сохраняются. Отчёт: `tool/audit/foundation-p2-2026-10-16/accessibility/report.md`.

Это host Semantics, а не проверка VoiceOver/TalkBack, announcement или assistive focus на устройстве. Полные item roles/actions, Reduce Motion, large text, native IME, pre-handback held reopen/content continuity, source transforms и cross-View остаются отдельными границами. Ранний root push всё ещё меняет observer/currentness/traversal до reveal; его продуктовая цена не принята. Production host/model/clock/timeline, exports, зависимости и измеренные параметры не меняются.
