# P2: удержание источника во время закрытия

2026-10-17, база `1d4a595c`. Только root-menu прототип. Продолжение `menu-accessibility-lifecycle.md`; P2 открыт.

## Вызов и контракт содержимого

```dart
ProbeMenuSource(
  pointerInput: true,
  menuBuilder: (popupContext) => EditorMenu(controller: appController),
)
```

API не меняется. Новый физический down на источнике может начать удержание, пока прежнее меню уже логически закрыто, но ещё владеет моделью. Move и up должны дойти через настоящий binding после измеренного hold-open. Сам down не обращает движение в открытие.

Повторное представление строит новый content State, как записано в исходном плане. Прежний редактор остаётся живым и рисуется на своём закрывающемся route до обычной передачи хвоста или фактического открытия следующего. Следующий route лениво строит одну новую policy/editor tree. Контроллер приложения может сохранять данные; сохранение route-local State между двумя представлениями не обещается.

## Почему недостаточно ранней передачи

До этого этапа новый route устанавливался при срабатывании hold. Navigator уже записывал down и отменял physical stream при push: тест получил down → PointerCancel вместо down → move → up. Поздний push не исправляется игнорированием cancel, поскольку binding теряет hit-test path.

Простая передача модели новому route на down тоже неверна. Прежний опыт уже показал 4 → 2 hand-back у быстрых tap-reopen при одинаковой геометрии. Кроме того, `_relinquish` преждевременно удаляет старое содержимое, а новый hidden route ещё не построил своё. Собственная система paint-only заимствования добавила бы второе владение представлением, не вернув настоящую передачу модели.

## Резервирование SDK route

Один приватный immutable объект связывает новый route, точный transfer и принятую pointer sequence. Source Listener устанавливает route на настоящем down до ancestor Listener Navigator, но `didPush` только регистрирует lifetime. Он не передаёт модель, не запускает sampler, не строит содержимое и не запрашивает фокус.

`activeRoute` по-прежнему означает владельца модели, а не последнюю запись Navigator. Прежние lease/clock/Flow продолжают сэмплировать и рисовать. Если закрытие пересекает ноль раньше hold, обычный hand-back переводит ту же модель источнику и сохраняет reservation. В момент `isOpen` существующий acquire переводит модель от фактического текущего владельца уже установленному route; второго push нет. Source и route callbacks прекращают публикацию после смены lease или disposal.

Полная modal/Navigator цепочка source остаётся обязательной. Для продолжения своей принятой sequence допускается только собственный current reservation и точная ещё активная root page под ним. Новый nested cover, удалённая страница и чужой route не получают исключения. Global router остаётся транспортом; резервирование не разрешает произвольный global down.

## Завершение попытки

Retirement очищает reservation identity до вызова модели и навигационных callbacks. Не владеющий моделью route не сбрасывает transfer. UI-уведомление и адресное удаление откладываются до microtask: source может исчезнуть во время locked-tree disposal. Уже удалённый route повторно не финализируется. SDK pop отличается от remove: только первый завершает собственную проекцию dismissed.

Три причины завершения выражены приватным enum. Обычная отмена held sequence сохраняет старый анимационный хвост и ранее подтверждённый release. Явный Back отменяет и ожидающее открытие через clock/lease фактического владельца. Потеря source, forced removal или отклонённое приобретение отменяют открытие именно захваченной модели, если оно ещё pending либо уже началось. Transfer и lease перепроверяются после callbacks, чтобы не закрыть новый reentrant owner.

Удаление reservation ровно на opening frame раньше могло отклонить acquire, а затем создать другой popup через общий present fallback. Теперь эта попытка потребляется отменой, сохраняя конечный хвост. Проверены removal successor и source page на этой границе. Насильно закончить уже popped predecessor в тесте позволяет SDK finalizeRoute; removeRoute уже popping entry является no-op этого SDK.

## Focus, policy и cover

Source semantic activation проверяет собственный reservation, отменяет физическое удержание и выполняет open на настоящем владельце до acquire. Callback, который в этот момент ставит cover, прекращает активацию. Новая policy принадлежит новому route и сохраняет прежний first-mount gate; старые PopScope/LocalHistory/permission не переносятся.

Под обычным cover подтверждённый tap-open сохраняет движение модели. Первый mount нового содержимого и focus откладываются до current/uncover. Иначе новый EditableText с autofocus захватывал primary focus под чужим экраном. Показанное ранее содержимое при cover сохраняет State и обычный SDK focus restoration. Дополнительный FocusScope gate отвергнут: он нарушал эту существующую проверку. При uncover скрытый route раскрывается и пробуждает свой прежний clock, включая случай уже settled модели.

Nested page cover может остановить source clock через SDK TickerMode после hand-back. Ожидание покоя выполняется после uncover; отдельный обход TickerMode не добавляется.

## Выбор и проверка

Два независимых кандидата одной модели сошлись на разделении установки route и владения моделью. Выбран triple route/transfer/sequence из A, 13/15 против 12/15 у B с predecessor identity; из B взяты явные команды на actual owner для semantics/Back. Отдельный predecessor не нужен: нынешнего владельца уже определяют transfer и activeRoute. Структурно иной immediate-acquire с удержанием старого paint отвергнут по прежнему контрпримеру hand-back.

24 новые проверки дают 275 прототипов и 365 example, анализатор без замечаний. Восемь held traces на 60/120 Гц и 1×/5× сравнивают время, progress, content opacity, kicks, fusion radius и RRect geometry с непрерывной моделью. Реальный down/move/up выбирает одну строку на единственной модели; ранний/поздний hold проверяет обе стороны hand-back. Цветной content проверяется в preparation и на первом новом кадре с положительной видимой alpha; это проверка присутствия, а не полное pixel-zero сравнение редакторов. Старый editor сохраняет данные до retirement, новый получает собственные State/focus/policy.

Отмена, release вне source, Back/pending Back, cover, source loss, forced successor removal, early predecessor finalization, semantics и reentrant removal проверяются с конечным teardown без оставшихся callbacks. Прежние 20 replay, 40 hand-back, восемь async timing records и шесть flat-сцен/459 кадров сохраняются. Отчёт: `tool/audit/foundation-p2-2026-10-17/held-reopen/report.md`.

Production model/clock/timeline, transfer adapter, tuning, зависимости и exports не меняются. Это интеграция существующего измеренного поведения, не новое доказательство UIKit held-reopen/IME/assistive focus. Полные native/device/perf gates, transformed source geometry и multi-View, оставшийся menu API, полный бар/оптика и продуктовая цена раннего push остаются открытыми.
