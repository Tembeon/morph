# P2: окружение источника и root popup

2026-10-16, база `65b080d3`. Только прототип `example/lib/proto/menu_route_probe.dart`. Продолжение `menu-input-ownership.md`; P2 открыт.

## Вызов приложения

Обычный вызов сохраняется:

```dart
DefaultTextStyle(
  style: localStyle,
  child: ProbeMenuSource(
    menuBuilder: (popupContext) => const EditorMenu(),
  ),
)
```

`popupContext` принадлежит меню на root Navigator. `Navigator.of`, `ModalRoute.of`, `PopScope` и Focus разрешаются в этом контексте. Closure builder сама по себе не переносит inherited-зависимости места объявления.

## Что переносится

| Значение | Проверенный контракт прототипа |
|---|---|
| Локальные `InheritedTheme` между source и root Navigator | SDK capture, ближайшая тема каждого runtime type; обновления значений при живом source |
| `DefaultTextStyle`, `IconTheme`, пользовательская тема | Участвуют в том же capture, отдельных каналов нет |
| Темы над root Navigator | Обычное живое наследование popup; capture их не замораживает |
| `MediaQuery` | Живые данные root route, включая keyboard insets, text scale, brightness и accessibility flags |
| `Localizations`, `Directionality` | Живое окружение root route |
| Произвольные page providers и другие `InheritedWidget` | Автоматически не переносятся; общие зависимости располагаются над root Navigator или передаются содержимому явно |
| Navigator, modal policy, focus, Actions | Принадлежат popup; source scopes не копируются |

Source-local `Localizations`, `Directionality` и `MediaQuery` не становятся окружением popup. Это явная граница этого прототипа. Продуктовая поддержка локального locale/RTL ещё не выбрана. Автоматическое копирование всей MediaQuery перенесло бы размеры и уже потреблённые отступы страницы и могло бы заморозить последующие изменения окна/клавиатуры. `Localizations.override` создаёт собственный загрузочный scope; это отдельный контракт, а не часть theme capture.

Для page-specific данных приложение передаёт значение или controller. Контекст builder остаётся контекстом popup:

```dart
final selection = SelectionScope.of(context).selection;
return ProbeMenuSource(
  menuBuilder: (popupContext) => SelectionScope(
    selection: selection,
    child: const EditorMenu(),
  ),
);
```

Такой closure не обещает автоматического обновления захваченной переменной. Контроллер может обеспечивать собственные обновления. Явные `Localizations.override` и `Directionality` внутри builder также допустимы; source context после удаления не нужен.

## Владение и обновления

Источник выбирает root Navigator один раз при создании route и вызывает `InheritedTheme.capture(from: context, to: navigator.context)`. Начальный снимок синхронный, поэтому не зависит от будущего frame callback. Невидимая pointer preparation получает данные, но не запускает menuBuilder раньше reveal.

SDK capture не регистрирует зависимостей. Источник подписывается на ближайшие ancestor `InheritedTheme` через публичный `dependOnInheritedElement`. `didChangeDependencies` приобретает новый снимок и передаёт его живым route своей session на том же Navigator. Два обхода предков выполняются при acquisition/изменении зависимостей, а не на кадрах движения.

У каждого route свой принятый снимок и один pending slot. Публикация через ValueNotifier откладывается до post-frame, чтобы source build не вызывал setState в соседнем popup. Несколько принятых обновлений заменяют pending последним; возврат к уже опубликованному значению тоже заменяет старый pending. Начальная тема готова сразу, живое обновление может потребовать следующего кадра.

Callback хранит route и приобретённые данные, а не source State/BuildContext. Уже приобретённое обновление может дойти после удаления источника. После удаления source остаётся последний снимок, а shared root environment продолжает обновляться. Disposal route очищает pending и notifier; старый callback ничего не публикует в удалённое или новое меню. Closing route может обновлять свою тему до disposal, не получая заново право на ввод или движение.

CapturedThemes оборачивает стабильный child `_MountedMenuPolicy`. При обычном изменении значений тем редактор сохраняет State, controller, FocusNode и регистрацию PopScope. Движение само по себе не пересобирает содержимое темы.

## Ограничение структуры

Для открытого route порядок runtime types захваченных ближайших тем фиксирован. Обновление с добавленным, удалённым или переставленным типом не принимается: остаётся последний совместимый снимок. Следующий новый route принимает новую структуру. Это сохраняет прежнее ограничение carrier без переноса самого legacy-класса.

Совпадения типов недостаточно для произвольного пользовательского `wrap`, который меняет widget types, keys или положение child при смене значения. Проверки сохраняют State для стандартных SDK wrappers и стабильного пользовательского wrapper. SDK capture не клонирует mutable payload и не разрешает все destination-sensitive значения в контексте source.

## Выбор и доказательства

`architect` сравнил source subscriptions с публикацией снимка на каждом route и неизменяемый снимок при открытии. Первый выбран с оценкой 14/15 против 11/15: второй нарушает уже записанное требование live-local обновления, в том числе между hidden preparation и reveal. Из второго сохранено независимое владение данными после detach. Убраны отдельный initial-kind snapshot и queued-флаг; принятый снимок и pending slot уже кодируют эти состояния. Кандидаты и judge являются разными запусками одной модели.

Новые WidgetsApp-only проверки покрывают plain/nested root popup, text/icon/custom themes, живой редактор/focus/PopScope, root system environment, source detach, явные page scopes, hidden refresh/cancel, latest value, отложенный refresh после route removal, отсутствие content rebuild на motion и смену topology до следующего открытия. Latest-value проверка не вынуждает несколько отдельных route snapshots; точные A→B→A, pending после source disposal и callback после фактического route disposal проверены по коду, а не отдельным runtime расписанием. Результаты и исходные провалы находятся в `tool/audit/foundation-p2-2026-10-16/source-environment/report.md`.

Этот проход не доказывает общее клонирование context, произвольный custom wrap, native accessibility semantics, поведение настоящей IME, cross-root/multi-View перенос, геометрию и device/perf. Продуктовый presenter, цена раннего push, pre-handback held reopen, оставшийся menu API, полный бар/оптика и граница SDK success остаются открытыми.
