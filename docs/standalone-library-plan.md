# План: morph как самостоятельная библиотека

Дата согласования направления: 2026-10-15. Направление архитектуры выбрано, обоснование находится в `docs/architecture/foundation-review.md`, типы и список удаления в `docs/architecture/foundation-sketch.md`. Продуктовая реализация не начата; первый host-проход P1 находится в `example/lib/proto/`, отчёт в `tool/audit/foundation-p1-2026-10-15/report.md`. После разбора уточнены обязанности route и момент доставки событий; обязательность базы `MorphHost` и ограничения painter остаются решениями, которые нужно подтвердить до соответствующего массового переноса.

## Цель

morph даёт приложению полный набор Liquid Glass-компонентов iOS 27 с измеренным нативным поведением через Flutter API. Приложение использует библиотеку без Material и Cupertino и не настраивает физику и производительность само.

- Публичный API чистый, без остатков старого движка. Новая версия развивается в `main` без слоя совместимости. Старый API остаётся на прежних Git-тегах. `dream_echo` и Sonatide переходят позже и не задают требований совместимости.
- `motor` удалён. Оба рендерера сохраняются, стеклянный и плоский. Tier flat, fake или liquid выбирает приложение или пользователь.
- Измеренное поведение iOS является спецификацией. На Pixel 6a приложение держит 60 fps (16,67 мс на кадр) с запасом в сторону 120 fps.
- Долгосрочная цель включает полное покрытие Liquid Glass, в том числе морфы стекла приложения (аналоги `glassEffectID`, `glassEffectUnion`, `GlassEffectContainer`), и публичный движок анимаций в духе SwiftUI. В эту работу они не входят, но фундамент их не закрывает. Модель движения остаётся чистой, с явным временем и типизированными событиями, и может стать публичной без переписывания. Поверхность с одним писателем на поле и переносом между slot сцены служит основой будущих публичных морфов стекла. Каталог покрытия включает SwiftUI-API стекла наравне с UIKit.

## Границы самостоятельности

- Все компоненты работают в обычном `WidgetsApp` под `MorphTheme`. Публичный API не требует `ThemeData`, `ColorScheme`, `ThemeExtension` и других типов Material или Cupertino.
- Код morph и его сторонние runtime-зависимости не импортируют и не экспортируют `material_ui`, `cupertino_ui`, `package:flutter/material.dart`, `package:flutter/cupertino.dart` и `motor`. Правило проверяет `test/architecture_test.dart`.
- Темы, цвета, типографика, подписи доступности и настройки представлений принадлежат morph. Приложение может параллельно использовать другие UI-библиотеки и само даёт им нужных предков.
- Каждая внешняя зависимость имеет записанное назначение, транзитивную стоимость и причину не заменять её средствами SDK. Сборочные зависимости допустимы, если без них не поставляется рабочий рендерер.
- Системная возможность, которой нет в публичном Flutter API, получает узкий platform channel или FFI с записанной поддержкой платформ.

Граница Flutter SDK. В Flutter 3.47.2 цепочка `widgets.dart`, `src/widgets/basic.dart`, `animation.dart`, `src/animation/curves.dart` доходит до импорта `package:flutter/cupertino.dart` в curves.dart:11. Это файл SDK без локальных изменений, поэтому полный запрет Cupertino во всём графе недостижим даже для пустого `WidgetsApp`. Очистка внутренностей SDK не входит в цель. Проверка показывает нарушения morph и сторонних пакетов отдельно от связей внутри SDK. `@docImport` не считается рабочим импортом.

## Правила публичного API

- Префикс `Morph` у всех публичных типов. `Glass` только в именах, которые описывают стеклянную поверхность, эффект или рендерер.
- Короткие имена основных контролов: `MorphSwitch`, `MorphSlider`, `MorphNavigationBar`. Переименование `MorphGlassButton` в `MorphButton` проверяется на сценариях.
- Две библиотеки: `package:morph/morph.dart` (около 100 имён) и `package:morph/glass_painter.dart` (5 имён). Список фиксирует golden `test/api/public_api.txt`, изменение API является проверенным diff этого файла.
- Управляемые контролы берут `value` и `onChanged`. Родитель остаётся источником значения, отказ выражается отсутствием перестройки. Порядок, число и значения callback-вызовов определены и проверены.
- Владение контроллерами и focus nodes определено. Библиотека освобождает свои ресурсы и корректно принимает замену внешних объектов.
- Модальное представление вызывается одной функцией, меню является виджетом. `MorphNavigationStack` является единственным контейнером навигации и владеет Navigator и барами. `MorphNavigationRoute` является единственным типом страницы внутри стека, `MorphNavigationPage` является его формой `Page` для декларативного API Navigator. Выбор между императивным и декларативным API делает SDK, второго пути morph здесь нет. Источник представления называет `MorphSourceLink`.
- Движения, tunings, metrics, модальные классы route, уровни размещения и GPU-типы не публичны. Параметр, который молча игнорируется, не публикуется. Внутренние приватные классы называются по роли, префикс для них необязателен.

## Как читать

Работа разбита на единицы, которые попадают в `main` по одной. Один флажок означает один кусок работы. Флажок ставится, только когда есть доказательство: файл, строка лога, снимок экрана, прогон тестов или SHA. Зелёные тесты сами по себе не закрывают единицу. У каждой единицы есть проверки unit, устройство и perf там, где они применимы, и запись "не требуется" с причиной там, где нет.

Прогоны на устройствах собирает координатор и выполняет пакетом в конце единицы. iPhone берётся под `/tmp/morph-native/device.lock`, Pixel 6a (26221JEGR12737) под `/tmp/morph-native/pixel.lock`, каталогом через `mkdir` с файлом `owner`. Агенты заканчивают работу на host-проверках и не ждут устройство. Обмен пикселей на производительность одобряет владелец глазами на iPhone. Невидимые NEAR-обмены делаются без вопроса и объявляются в dartdoc и паспорте.

Каждая единица описана блоками в одном порядке: **Зависит от**, **Файлы**, **Сделать**, **Видно**, **Проверка, unit**, **Проверка, устройство**, **Проверка, perf**, **Гейт кода**, **Удалить в этом же юните**. Проверка устройства идёт пакетом у координатора. Гейт кода означает `/deslop`, затем `/no-comments` с отдельным проходом comment-sicko по области единицы, ревизия и итог обоих разборов записываются в описание commit. Прерванный или недоступный reviewer и лимит использования означают, что гейт не пройден. В блоке удаления старый путь умирает в той же единице для всех переведённых потребителей. Слоя совместимости нет. Если у старого пути остались потребители, они и единица полного удаления названы явно.

Правило perf для каждой единицы, которая трогает движение или стекло. Pixel 6a держит 60 fps. Сравниваются время кадра и энергия на одном сценарии до и после. Кадров в покое ноль. Потолки `perf_counts.json` и допуски replay-тестов не ослабляются. Backdrop не отстаёт на кадр. Базовая проверка каждой единицы включает `dart format lib test example/lib example/test && flutter analyze` с нулём замечаний, `flutter test` и `(cd example && flutter test)`.

## Единица 0. Прототипы P1, P2, P3

- **Зависит от.** Ничего.
- **Файлы.** Ветка `proto/foundation` или `example/lib/proto/` с тестами в `example/test/proto/`. Прототипы host/route/scene в `lib/` не переносятся. Узкое исключение P2: внутренний `morphMenuSetCloseAdmission` в `menu_motion.dart` проверяет допуск перед автономным переходом в closing; без установленной проверки поведение прежнее. Он нужен для опыта на целой модели без её копирования, не экспортируется из библиотек пакета и удаляется при переходе к типизированным событиям в 2.4.
- **Решения.** Единица 0 закрыта на host 2026-10-19. Подробности и доказательства лежат в отчётах, здесь только итог.
  - [x] P1, route. Выбрана собственная проекция движения (`MorphRouteAnimation`) с одними часами route как владельцем времени. Вариант на SDK controller проходит те же lifecycle-сценарии, но перестраивает barrier и `ListenableBuilder` на каждом тике (8,0 сборки на кадр против 4,4) и требует отдельного адаптера дрёмы. P2 построил весь menu route на проекции с переносом времени модели между часами, чего у controller нет. Отчёты `tool/audit/foundation-p1-2026-10-15/report.md` и `timing/report.md`.
  - [x] P2, меню как route на root navigator. Предикат выполнен на host. Replay записанного ввода идёт через настоящий route и совпадает с продуктовой моделью до 1e-9, а модель сверена с записями устройства в продуктовых тестах. Контур flat-бара непрерывен через посадку, ноль отличающихся пикселей на каждом кадре. Перенос времени проверен по часам кадров через hand-back, с дрёмой и вводом между кадрами. Ранний реальный push на pointer-down принят вместе с его ценой (root observers и currentness меняются на невидимой подготовке), иначе удержание теряет указатель. Отчёты `tool/audit/foundation-p2-2026-10-16/`, `-17/`, `-18/`, сводка проверок в `route-doze/report.md`.
  - [x] P3, согласованность кадра. Упорядоченная фаза остаётся mid-frame microtask, которую уже используют `MorphFrameSync` и glass host. Stage не строится. Ввод от чужих ticker штампуется по метке кадра. Отчёт `tool/audit/foundation-p3-2026-10-19/report.md`.
- **Перенесено в продуктовые единицы.**
  - В 5.1 сборки на кадр продуктового sheet в потолках `perf_counts.json`; сокращённый стенд P1 их не заменяет.
  - В 5.2 запись поведения Hero между двумя `MorphNavigationRoute`; первый релиз Hero не обещает.
  - В 5.3 продуктовый бар и перенос оптического поля liquid/fake через посадку, контракт hidden Escape/Router, source-local locale/RTL, native accessibility, held-reopen и фокус на устройстве, native multiwindow, active safe area/IME и право source принять модель при изменившемся placement (нужен native-контроль с перемещённым source), оставшийся menu API.
  - В 3 штамп ввода по метке кадра для минимизирующегося tab bar и объединение `MorphFrameSync` с путём glass host.
- **Видно.** Ничего, прототипы живут вне продукта.
- [ ] **Проверка, устройство.** Pixel 6a, открытие и закрытие sheet (P1), первый кадр меню (P2), tab bar, segmented и меню (P3).
- [ ] **Проверка, perf.** Время кадра и энергия P1 рядом с текущей реализацией.
- **Гейт кода.** Для прототипов не требуется, они не попадают в `main`. Внутренний допуск P2 отдельно не переносится в `main`: его замена типизированными событиями проходит гейт единицы 2.4.
- **Удалить в этом же юните.** Ничего.

## Единица 1. Новый main и вырезание legacy-движка

- **Зависит от.** Ничего, вычитание идёт раньше добавления.
- **Файлы.** Строки единицы 1 в таблице "Legacy-движок" `foundation-sketch.md`. Целиком уходят `route.dart`, `anchor.dart`, `shared.dart`, `measure.dart`, `frame.dart` и `skin.dart`. Из `show.dart`, `target.dart`, `gesture.dart` и `flight.dart` уходят только пресеты, фабрики кроме vessel, функции drag и shuttle без vessel, а `showMorph`, vessel и `morphRubberband` живут до своих единиц. Также `engine_page.dart`, 54 legacy-теста, мёртвый код рендеринга, `navigation_snapshot.dart`, `pubspec.yaml`, новые `test/architecture_test.dart` и `test/api/public_api.txt`.
- **Сделать.**
  - [x] Создать новую `main` от выбранного SHA `wip/measured-liquid-glass`. Старое содержимое `main` остаётся на `v0.4.0`. Сделано 2026-10-19 fast-forward до `101bdf9d`; прежний `main` на теге `main-before-foundation`, прототипы на теге `foundation-prototypes`.
  - [x] Удалить legacy-движок по строкам единицы 1. Убрать из экспорта `MorphController`, `closeAll`, `MorphFlightScope` и другие имена движка без потребителя в слое виджетов, сами классы умирают в 5.3. Коммит `98237e58`, 68 файлов, 19 166 строк.
  - [x] Удалить мёртвый код рендеринга, флаги отклонённых экспериментов и `equatable`. `GlassCostProbe` перенести в тестовый helper. Удалены navigation snapshot, `MorphLiveBackdropFilter`, `existsIn` и `equatable`. Kill switches рендерера, `LiquidGlassVisibility` и `GlassCostProbe` уходят в единице 6 вместе с путём, который они обслуживают.
  - [x] Добавить `test/architecture_test.dart` с таблицей направлений зависимостей и allow-list SDK. Проверять import и export во всём `lib/`, включая точки входа, все условные ветви и достижимые сторонние runtime-зависимости с оговорённой границей SDK. Для чистых `*_motion.dart` отдельно запретить импорт widget/host своего и других семейств. Текущие нарушения (`material_ui`, `package:flutter/material.dart`, `motor`) записаны в тесте списком, который может только сокращаться. Коммит `617d2a9f`; правило для motion транзитивное, добавлены правила web-пути и покрытия модулей.
  - [x] Добавить golden публичного API, построенный из модели элементов анализатора, вместе с внешними реэкспортами. Генератор заменяет `tool/ios_reference/coverage/export_api.dart`. `tool/api/public_api.dart`, golden `test/api/public_api.txt`.
- **Видно.** В галерее нет страницы движка. Меню, контекстное меню и sheets работают как раньше.
- **Проверка, unit.**
  - [x] Тесты меню и контекстного меню не изменены и зелёные.
  - [x] `architecture_test` и golden API зелёные.
  - [x] Отрицательные fixtures подтверждают обнаружение запрещённого export, транзитивной runtime-зависимости и импорта host из motion. Golden API не заменяет эти проверки.
- **Проверка, устройство.** Не требуется, потому что путь по умолчанию и пиксели не меняются.
- [x] **Проверка, perf.** `perf_counts.json` без изменений. `test/perf_counts_test.dart` проходит без изменения потолков.
- [x] **Гейт кода.** `/deslop`, `/no-comments`, comment-sicko по удалениям и двум новым тестам. Ревизия и итог записаны. Итог в `725b5f4b`: находки ревью про мёртвый код удалены, устаревшие описания переписаны.
- **Удалить в этом же юните.** Строки единицы 1 таблицы "Legacy-движок" и перечисленный мёртвый код. Старый `main` не сливается с новым.

## Единица 2. Время

Выполняется последовательными изменениями 2.1–2.5, каждое с отдельным commit и проверкой затронутых replay до следующего шага. Решатель, критерий покоя, временной API, доставка событий и удаление motor не объединяются в один commit. Номера 2.1–2.5 уточняют эту единицу; зависимости от единицы 2 означают завершение всех пяти шагов. Это внутренний порядок миграции без публичного слоя совместимости.

- **Зависит от.** 1.
- **Файлы.** `spring_state.dart`, `channel.dart`, `timeline.dart`, `flex_integrator.dart`, `flex_interaction.dart`, все `*_motion.dart`, `lib/src/spring.dart`, `lib/src/motion.dart`, `controller.dart`, `flight.dart`, `gesture.dart`, `morph_context_menu.dart`, `pubspec.yaml`, паспорта затронутых контролов. Цель `lib/src/motion/`.
- **Сделать.**
  - [x] 2.1. Перевести расчёт `MorphSpringState` на SDK `SpringSimulation`, сохранив существующие правила покоя и временной API. Подтвердить значение и скорость на fixtures в пределах 1e-9 и прерывания отдельно от смены критерия покоя. Форма переноса времени определяется P2; не добавлять `rebase` в пружину только ради первоначального эскиза. `acea2782`: 95 пружин из `lib/` с прерываниями, худшее расхождение значения 9,1e-13, скорости 1,8e-11. Коэффициент затухания в пределах 1e-9 от 1 описывается как ровно критический. Попутно `151d9fdd`: `morphLerpRect` сохраняет общие стороны точными, кадр поиска не пересчитывает layout от шума округления.
  - [ ] 2.2. Перевести 70+ мест `isAtRest(tolerance)` на `reach` и `MorphRest`, сохранив временной API и способ доставки событий. Сдвиги кадра покоя записать по контролам.
  - [ ] 2.3. Перевести диалект с явным `t` на advance-then-read без изменения доставки callbacks.
  - [ ] 2.4. Заменить callback-поля движений типизированными событиями и `drainEvents`, завершить контракт `MorphMotion<E>`. В том же commit, где появляется новый `MorphMotion<E>`, движение движка `MorphMotion` (src/motion.dart:24) получает внутреннее имя `FlightSprings`. После команды ввода host доставляет события до возврата из обработчика, после кадрового `advance` доставляет события времени и затем публикует кадр. Сохранить порядок, число и синхронность текущих callbacks и haptics.
  - [ ] Контракт запроса закрытия из P2 перенести в 2.4: outside/back/Escape проходят veto до изменения фазы движения. Отказ `PopScope` оставляет меню открытым; синхронное разрешение сохраняет измеренный deadline. После async-ожидания исходное время остаётся provenance, движение закрывается из текущего состояния владельца, без backdating. Сохранить отмену при смене владельца и одноразовый допуск; программный `Navigator.pop` сохраняет свою SDK-семантику. Для согласуемых событий до финального сэмпла нужен возобновляемый шаг движения: одна очередь после полного `advance` не сохраняет прежний deadline и порядок интеграции. Форму этого шага подтвердить до массовой замены callback-полей.
  - [ ] 2.5. Перевести на `MorphSpringState` нажатие контекстного меню, `MorphController`, `FlightSprings` и оставшиеся симуляции flight.dart. Классы движка умирают в 5.3. Удалить `MorphSpring.toMotion`, реэкспорты и зависимость `motor`. `morphRubberband` переезжает в `lib/src/motion/`.
- **Видно.** Ничего, кроме объявленного сдвига кадра покоя в пределах NEAR.
- **Проверка, unit.**
  - [ ] Каждый replay проходит с записанными допусками. Сдвиг кадра покоя на контрол записан в паспорт.
  - [ ] После каждого шага 2.1–2.5 проходят затронутые replay с прежними допусками; численная замена решателя проверена отдельно от смены кадра покоя.
  - [ ] Проверены список, порядок и однократность событий. `onChanged` и haptics от ввода наблюдаемы до следующего `pump`; события времени доставляются после `advance`. Повторный вход из callback, закрытие и размонтирование не дают повторной доставки или обращения к освобождённому host.
  - [ ] Список `motor` в `architecture_test` пуст.
- [ ] **Проверка, устройство.** iPhone, покой alert, sheet и меню, одобрение владельца глазами.
- [ ] **Проверка, perf.** Pixel 6a, switch, slider, меню. Кадров в покое ноль.
- [ ] **Гейт кода.** `/deslop`, `/no-comments`, comment-sicko по `lib/src/motion/` и движениям. Ревизия и итог записаны.
- **Удалить в этом же юните.** `motor`, `isAtRest`, диалект с явным `t`, callback-поля, собственный решатель пружины. `AnimationController` в navigation_stack.dart остаётся механизмом route до единицы 5.2.

## Единица 3. Host и часы

- **Зависит от.** 2, P1, P2, P3.
- **Файлы.** `control_host.dart`, `clock.dart`, около 23 State с часами, `lib/src/live.dart` (`MorphFrameSync`, live.dart:75), `glass_channel.dart:326`, `scroll_indicator.dart`. Цель `lib/src/host/`.
- **Сделать.**
  - [ ] `MorphMotionClock` как объект: метка времени, сетка кадров, дрёма, сон в покое.
  - [ ] До массового перевода проверить общие механизмы host на switch, меню и sheet, используя результаты P1/P2. Зафиксировать, оправдана ли единая база State `MorphHost` или нужны композиция объектов и узкие mixin. Route пользуется часами напрямую. Не требовать от каждого виджета возможностей, которые он не использует.
  - [ ] Перевести 7 контролов на `MorphControlHost` и около 16 собственных State на подтверждённую форму общих механизмов host.
  - [ ] Согласованность кадра по варианту, который выиграл P3.
  - [ ] Перевести fade в `scroll_indicator.dart` на движение host.
- **Видно.** Ничего. Отказ родителя возвращает thumb со скоростью жеста.
- **Проверка, unit.**
  - [ ] Replay.
  - [ ] Тест отказа без перестройки родителя.
  - [ ] Тесты метки времени.
  - [ ] Общая доставка событий сохраняет синхронность callbacks и haptics ввода, порядок и защиту от повторного входа из единицы 2.4.
  - [ ] `perf_counts` показывает ноль кадров в покое и не больше сборок на кадр, чем сейчас.
  - [ ] Для Stage проверка изоляции между `testWidgets`.
- **Проверка, устройство.** Не требуется для пикселей, они не меняются.
- [ ] **Проверка, perf.** Pixel 6a, tab bar, segmented, меню.
- [ ] **Гейт кода.** `/deslop`, `/no-comments`, comment-sicko по `lib/src/host/` и переведённым State. Ревизия и итог записаны.
- **Удалить в этом же юните.** `MorphClock` mixin, `MorphControlHost`, собственный код ticker в State, `MorphFrameSync` и microtask `_sync`, если их заменил вариант P3.

## Единица 4. Тема

- **Зависит от.** 1.
- **Файлы.** `widgets_theme.dart`, `lib/src/theme.dart`, `show.dart`, `flight.dart`, `glass_tier.dart`, `glass_renderer.dart`, `glass.dart` (`MorphGlassScope`), 17 классов appearance, `typography.dart`, `example/lib/main.dart`, `pubspec.yaml`. Цель `lib/src/theme/`.
- **Сделать.**
  - [x] `MorphTheme` как `InheritedTheme`, `MorphThemeData.appearances` по типу, `morphAppearanceOf`, `static const tables`, `lerp` у каждого appearance. Сделано в `b474652e`: `MorphThemeData.appearances` по типу, `MorphAppearance`, `morphResolveAppearance`. `lerp` у appearance не делается: в `WidgetsApp` нет анимированной темы.
  - [x] Sealed `MorphGlassRenderer` в `lib/src/theme/`: `adaptive`, `tier`. Сделано в `408a7267`: `MorphThemeData.glass`, null наследует стекло темы выше; `MorphTheme` стал виджетом слоя widgets над внутренним `MorphThemeScope`, потому что модуль theme не импортирует widgets. Старый класс стал `GlassBuiltInPainter`, `MorphAdaptiveGlass` стал внутренним `GlassAdaptiveScope`. `painted` придёт в единице 6 вместе с типами painter в theme; до тех пор свой painter ставит `MorphGlassScope` из `glass_painter.dart`.
  - [x] В flight.dart и show.dart заменить `Theme.of(context).colorScheme` (flight.dart:1699) и чтения `MorphTheme.default*` (flight.dart:579-582) на `MorphThemeData`, затем удалить все импорты Material. Сделано в `725b5f4b` и `b474652e`; в `lib/` нет импортов Material.
  - [x] `MorphLocalizations` с английскими строками по умолчанию. `b474652e`, `f1a1b2bc`.
  - [x] Перенести `setFloatUniforms` из `flutter_shaders` в `scene/shaders.dart`. `46218a27`, `3d8c575c`: `lib/src/glass/renderer/internal/shader_uniforms.dart`, квантование как у `flutter_shaders`.
  - [ ] Перевести галерею на `WidgetsApp` и собственную тему. Отложено: затрагивает только example; галерея пока на `MaterialApp` с `MorphTheme` в chrome.
- **Видно.** Галерея работает без Material-предков. Цвета light, dark, high contrast и tint не меняются.
- **Проверка, unit.**
  - [x] Список Material в `architecture_test` пуст.
  - [x] `flutter pub deps` без `material_ui`, `cupertino_ui`, `flutter_shaders`. `material_ui` остался только в dev_dependencies для тестов.
  - [ ] Тесты appearance на контрол.
  - [ ] Тест `lerp`, вложенная тема, смена темы при открытом sheet, RTL.
- [ ] **Проверка, устройство.** iPhone, снимки страниц галереи в light и dark совпадают с текущими.
- **Проверка, perf.** Не требуется, путь кадра не меняется.
- [ ] **Гейт кода.** `/deslop`, `/no-comments`, comment-sicko по `lib/src/theme/` и местам разрешения appearance. Ревизия и итог записаны.
- **Удалить в этом же юните.** `MorphWidgetsTheme`, `MorphWidgetsThemeScope`, `MorphTheme` движка, `MorphGlassScope`, `MorphAdaptiveGlass`, `MorphGlassMaterial`, три ручных разрешения appearance, `flutter_shaders`.

## Единица 5.1. Sheet на `MorphMotionRoute`

- **Зависит от.** 2, 3, P1.
- **Файлы.** `lib/src/presentation/`, `sheet.dart`, `sheet_motion.dart`, `zoom_source.dart`, `presentation.dart`.
- **Сделать.**
  - [ ] Перенести из P1 `MorphMotionRoute`, `MorphRouteAnimation`, `MorphSettleSignal` и `MorphPopupRoute`. Сделано внутри `MorphMotionRouteMixin` (`a46da818`): route проецирует фазы движения, значение держится 1 от push до ухода, потому что движущееся значение поднимало счётчики сборок выше потолков (запасной вариант P1).
  - [x] `MorphSourceLink` и `MorphSource`, параметр `source:` у контролов, которые показывают sheet. `2e03a8cf`; `from:` у sheet, `MorphNavigationRoute`, `MorphNavigationPage`, `pushMorphZoom`. Параметр `source:` у контролов не добавлен: `MorphSource` оборачивает любой контрол.
  - [ ] `morphPresentationNavigatorOf(context, level)` с уровнем как свойством семейства.
  - [x] Перевести sheet. Жизненный цикл route у sheet, alert и zoom-страницы.
- **Видно.** Zoom sheet не меняется. Страница под sheet видна во время zoom.
- **Проверка, unit.**
  - [x] Предикат P1 на продуктовом sheet. `test/motion_route_lifecycle_test.dart`: фазы, удержание при `pushReplacement`, replace. Сборки на кадр в потолках `perf_counts.json`.
  - [ ] Редактор во вложенном Navigator сохраняет State и IME при открытии, закрытии, изменении insets и покрытии другим route.
  - [ ] Источник исчезает раньше редактора.
  - [ ] Replay zoom.
- [ ] **Проверка, устройство.** iPhone, паритет zoom sheet глазами.
- [ ] **Проверка, perf.** Pixel 6a, открытие и закрытие sheet.
- [ ] **Гейт кода.** `/deslop`, `/no-comments`, comment-sicko по `lib/src/presentation/` и sheet. Ревизия и итог записаны.
- **Удалить в этом же юните.** Поиск `MorphTag` для sheet. `MorphZoomSource` остаётся у navigation_stack.dart и push_zoom.dart, `MorphMotionRouteMixin` у alert, date picker и navigation, оба до 5.2.

## Единица 5.2. Alert, date picker, navigation, push zoom

- **Зависит от.** 5.1.
- **Файлы.** `alert.dart`, `date_picker.dart`, `navigation_stack.dart`, `push_zoom.dart`, `motion_route.dart`, `zoom_source.dart`, `themes.dart`.
- **Сделать.**
  - [ ] Перевести alert, action sheet и popover date picker на `MorphPopupRoute` с уровнем окна.
  - [ ] Перевести push и pop navigation и push zoom на `MorphNavigationRoute(from:)`. Edge swipe через `navigator.didStartUserGesture()`.
  - [x] Один observer predictive back на binding для всех morph routes. `a8255041`: страница со slide и zoom-страница берут жест, только когда все routes вокруг них current; sheet, alert и открытое меню оставляют обычный back. Прогресс жеста заменяет долю ширины под пальцем (приближение, у iOS нет эталона).
- **Видно.** Android back с предпросмотром на routes morph. Zoom из ячейки списка не меняется.
- **Проверка, unit.**
  - [ ] Replay navigation release (2bdb3e47, 5e163f5f).
  - [x] Predictive back commit и cancel. `test/predictive_back_test.dart`: commit, cancel, back под sheet закрывает sheet, zoom-страница.
  - [ ] Alert и date picker на root navigator из вложенного navigator.
  - [ ] Veto и возврат фокуса.
- **Проверка, устройство.**
  - [ ] iPhone, push zoom, navigation, alert.
  - [x] Pixel 6a, predictive back. `4f83019f`, снимки в `tool/audit/foundation-5.2-2026-10-19/`: предпросмотр, отмена и commit.
- [ ] **Проверка, perf.** Pixel 6a, navigation push и pop.
- [ ] **Гейт кода.** `/deslop`, `/no-comments`, comment-sicko по переведённым routes. Ревизия и итог записаны.
- **Удалить в этом же юните.** `MorphMotionRouteMixin`, `MorphZoomSource`, `MorphThemeCarrier` у routes, `pushMorphZoom`, `AnimationController` и `SpringSimulation` в navigation_stack.dart.

## Единица 5.3. Меню и контекстное меню

- **Зависит от.** 5.2, P2.
- **Файлы.** `menu.dart`, `menu_host.dart`, `menu_motion.dart`, `bar_items.dart`, `morph_context_menu.dart`, `toolbar.dart`, `navigation_bar.dart`, весь оставшийся движок в `lib/src/`.
- **Сделать.**
  - [ ] `MorphMenuRoute` с движением меню как движением route, передача хвоста кнопке, повторное открытие во время закрытия.
  - [ ] В контекстном меню scrim становится степенью свободы движения barrier, нажатие считается на `MorphSpringState`.
  - [ ] Перевести `morphTargetPaddingOf` в layout меню.
- **Видно.** Меню и контекстное меню выглядят как раньше. Push при открытом меню накрывает меню.
- **Проверка, unit.**
  - [ ] Предикат P2 на продуктовых меню.
  - [ ] Нажатие снаружи, Esc, back, подпись dismiss в VoiceOver.
  - [ ] Меню из sheet во вложенном navigator идёт на root.
- [ ] **Проверка, устройство.** iPhone, меню и контекстное меню глазами.
- [ ] **Проверка, perf.** Pixel 6a, первый кадр меню, открытие и закрытие.
- [ ] **Гейт кода.** `/deslop`, `/no-comments`, comment-sicko по меню и `lib/src/presentation/`. Ревизия и итог записаны.
- **Удалить в этом же юните.** Flight-движок целиком по разделу "Legacy-движок" (единица 5.3), `MorphPresentationBoundary`, `morphPresentationOverlayOf`, двойная пружина меню, `_advanceDetached`, `flight.markNeedsBuild()` в menu.dart:1061.

## Единица 6. Сцена

- **Зависит от.** 3, 4, 5.3.
- **Файлы.** `glass*.dart`, `glass_channel.dart`, `glass_liquid_draw.dart`, `glass_outline.dart`, `liquid_field.dart`, `menu_fusion*.dart`, `lib/src/glass/renderer/`, shaders, glass-привязки в `live.dart`. Цель `lib/src/scene/`.
- **Сделать.**
  - [ ] `MorphSurface` как единственное внутреннее описание. `RenderLiquidGlassLayer` читает его через `GeometryRenderLink` (liquid_glass_render_object.dart:869).
  - [ ] До замены painter-шва проверить пример с regular и clear рядом, движущимся фоном, слитой шейкой и внешним свечением. Решить, нужен ли `style` во view и отдельный проход вне контура, либо явно принять ограничение painter. Выбрать допустимые модификаторы views: `abstract final` из эскиза не позволяет сцене реализовать их из другой Dart-библиотеки; `abstract interface` допускает внешнюю реализацию, альтернативное размещение должно сохранять направление зависимостей.
  - [ ] `MorphSurfaceHandle` для контрола и `MorphSurfaceCarry` для представления.
  - [ ] Один конвейер поля и один tracer с `MorphFusionLaw.container` и `MorphFusionLaw.morph`.
  - [ ] `MorphShaderRegistry` с precache и прогревом.
  - [ ] Flat как tier. Canvas painter-шов на `RenderMorphScene`. В том же commit публичные классы `MorphGlassSurface` и `MorphGlassOutline` из старого шва заменяются новыми views с теми же именами, до этой единицы новые views не вводятся.
- **Видно.** Пиксели каждого tier не меняются. Пользовательский painter в галерее больше не пересобирается на кадре.
- **Проверка, unit.**
  - [ ] `glass_frames_test` без сборки на кадр, с пользовательским painter.
  - [ ] Паритет сохранённых slots при слиянии, разделении и появлении.
  - [ ] Покой raster-фазы.
  - [ ] Число backdrop filters на экран не больше текущего.
- **Проверка, устройство.**
  - [ ] iPhone, паритет пикселей каждого семейства на flat, fake и liquid глазами.
  - [ ] Паритет закона слияния до удаления `_OutlineTracer` и blend `angularBlendRadius` в `gpu/sdf.glsl`, `gpu/material_sdf.glsl` и `analytic_geometry.glsl`.
- **Проверка, perf.**
  - [ ] Pixel 6a, полный набор benches.
  - [ ] 10 минут прокрутки и меню подряд.
- [ ] **Гейт кода.** `/deslop`, `/no-comments`, comment-sicko по `lib/src/scene/`. Ревизия и итог записаны.
- **Удалить в этом же юните.** Раздел "Дубли рендеринга и мёртвый код" в `foundation-sketch.md` (единица 6), widget-шов painter, путь `_painted`, 18 проверок `glass == null` в 12 файлах, шесть кешей shader.

## Единица 7. Публичный срез

- **Зависит от.** 6. Выполнена раньше 5.3 и 6 (2026-10-19): после среза 5.3 и 6 меняют только `src/`. Painter-шов `glass_painter.dart` остаётся прежним до единицы 6.
- **Файлы.** `lib/morph.dart`, `lib/glass_painter.dart`, `lib/widgets.dart`, `lib/foundation.dart`, `lib/motion.dart`, example, тесты, `docs/`, `CLAUDE.md`, паспорта, `tem_tools/plugins/morph`, `README.md`, `CHANGELOG.md`.
- **Сделать.**
  - [x] `morph.dart` около 100 имён и `glass_painter.dart` 5 имён. Example импортирует только их, тесты replay импортируют `src/`. `morph.dart` 105 имён: к эскизу добавлены `MorphSheet`, `MorphSheetRoute`, `MorphDatePickerLocalizations`, `MorphContentScroll`, `MorphTabAccessoryEnvironment`, `DefaultMorphLocalizations`, без них галерея и параметры контролов теряют функции; `MorphGlassShape` не введён, `MorphGlassEffect` берёт `ShapeBorder`. `glass_painter.dart` 7 имён, с `MorphGlassScope`. Tunings, metrics и хуки flight у публичных виджетов стали `@internal` параметрами. Галерея импортирует `src/` только в инструментах разработчика (инспектор, лаборатория рендерера, spec inspector).
  - [x] Перегенерировать golden API. Тест API также запрещает внутренние типы в публичных сигнатурах.
  - [ ] Переписать документы из приложения D, таблицу документов в `CLAUDE.md`, ссылки на код в паспортах и skill use-morph. Сделано частично: точки входа в `CLAUDE.md`, `engine-rules.md`, `widgets.md`, `testing.md`, имена в паспортах стекла. Полная переписка `engine.md` ждёт 5.3; skill use-morph живёт в другом репозитории.
  - [x] Рецепт подключения в README: зависимость по тегу, `MorphTheme`, GPU-флаги, прогрев, поведение без liquid. `CHANGELOG.md` прочитать перед записью. Код README проверен анализатором.
- **Видно.** Новый импорт `package:morph/morph.dart`.
- [ ] **Проверка, unit.** Diff golden просмотрен.
- [ ] **Проверка, устройство.** macOS release build, web build, autodemo.
- **Проверка, perf.** Не требуется, код кадра не меняется.
- [ ] **Гейт кода.** `/deslop`, `/no-comments`, comment-sicko по точкам входа, example и документам. Ревизия и итог записаны.
- **Удалить в этом же юните.** `widgets.dart`, `foundation.dart`, `motion.dart`, публичные tunings, metrics и модальные классы route.

## Единица 8. Покрытие и выпуск

- **Зависит от.** 7.
- **Файлы.** `tool/ios_reference/coverage/catalog.json`, паспорта, example, `pubspec.yaml`.
- **Сделать.**
  - [ ] Определить семейства первого релиза. Разложить на обязательства только их, остальные из 58 семейств каталога отметить незавершёнными.
  - [ ] Связать каталог с API, паспортами, примерами и тестами проверкой целостности.
  - [ ] Выполнить критерии Git-релиза ниже.
- **Видно.** Поддерживаемый набор записан в README и каталоге.
- [ ] **Проверка, unit.** Проверка целостности каталога в обычном прогоне тестов.
- **Проверка, устройство.**
  - [ ] Чистый checkout candidate SHA, example с `path: ../`, native release. Настоящий liquid tier загружен, тихий переход на fake критерий не выполняет.
  - [ ] Диагностика fallback при ошибке bundle и неподдерживаемом GPU.
- [ ] **Проверка, perf.** Pixel 6a, полный набор benches на candidate SHA.
- [ ] **Гейт кода.** `/deslop`, `/no-comments`, comment-sicko по изменениям единицы. Ревизия и итог записаны.
- **Удалить в этом же юните.** Ничего.

## Main и выпуск

После единицы 1 новая версия развивается в `main`. `main` может содержать ограниченный набор компонентов и известные ошибки, они записаны в каталоге. Пакет собирается после каждой единицы. Неудачная единица откатывается отдельным revert. Исследования остаются в `tool/audit/` и `docs/research/` и не попадают в рабочие пути и экспорты. `wip/measured-liquid-glass` сохраняет эксперименты.

Первый выпуск предназначен для приложений владельца и распространяется по Git-тегу, pub.dev не входит в этот рубеж. Критерии Git-релиза:

- [ ] Выбран candidate SHA. Исходники, manifests, hooks, shaders, документы, `LICENSE`, renderer `NOTICE` и `VENDORED` находятся в этом commit.
- [ ] Проверки единицы 8 связаны с candidate SHA, версиями SDK, платформами и конфигурацией.
- [ ] Минимальная заявленная и основная stable-версии Flutter проверены. Результаты на beta записаны отдельно.
- [x] Асинхронные представления: исключение deferred loader, отклонённый Future, пустой результат, ответ после закрытия, быстрый reopen (`menu_content.dart`, `menu_entries.dart`). `test/menu_deferred_async_test.dart` (`413521e7`); найденные дефекты синхронного throw и reopen во время закрытия исправлены в `566842a9`. Открыто: bar-меню создаёт новый контроллер на каждое открытие, поэтому `cache: true` между открытиями bar-меню, вероятно, не держится; отклонённый `load` кешируется как пустой и не повторяется.
- [x] При длительном повторении основных сценариев overlay entries, активные tickers, подписки и память не растут от цикла к циклу. Число циклов и границы записаны до прогона. `test/presentation_cycles_test.dart` (`72ce8c88`): sheet, alert, меню, контекстное меню, zoom, по 25 циклов, flat tier; утечка `ValueNotifier` в меню исправлена в `566842a9`. Liquid tier в цикле не проверен.
- [ ] Версия в `pubspec.yaml`, `CHANGELOG.md` и тег согласованы, breaking changes описаны.
- [ ] Получение Git-зависимости проверено один раз: доступ к приватному репозиторию, разрешённый SHA в lockfile, краткий запуск.
- [ ] Пара commit приложения и commit morph записана. Выпущенные теги не перемещаются, исправления выходят новым тегом.
- [ ] Короткий отчёт выпуска с проверенными сценариями и ограничениями.

## Направления проверки

Обязательства проверяются по 13 направлениям каталога: API, геометрия, состояния, переходы, границы, конфигурации, события, ввод, жизненный цикл, доступность, оптика, платформы, производительность. Артефакт проверки связан с ревизией, конфигурацией, версией SDK, платформой и сценарием. Неприменимость требует причины.

Собственную физику проверяют replay и сценарии прерывания на 60 и 120 Hz. Темы и представления проверяются в `WidgetsApp` с вложенными темами, сменой brightness, локализованными подписями и живым текстовым вводом во время переходов. Рендерер проверяется по нативным пикселям на устройстве, потому что host-тесты не запускают shaders. Поставку проверяет example из чистого checkout без прежних build-артефактов в native release и web wasm.

## Приложение A. Результаты прототипов

| Прототип | Предикат | Ревизия | Host | Pixel 6a, кадр и энергия | iPhone | Решение |
| --- | --- | --- | --- | --- | --- | --- |
| P1, проекция против SDK controller | Единица 0 | `78a22418` + локальные файлы и хеши в отчётах P1 | 55 проверок; паритет часов и SDK-дрёма/сетка; 4,4 / 8,0 перестроения на кадр базового стенда | Не проверено | Сокращённый profile-прогон: 16 циклов, редактор/клавиатура/фокус, 120 Гц; паритет UIKit не проверен | Выбрана проекция; Pixel ещё нужен |
| P2, меню как route | Единица 0 | `daa49e98` + хеши viewport/native-ime/native-ime-reopen/placement-boundary | 464 example, включая 374 прототипа; дрёма route и непрерывность по часам кадров через hand-back; measured source + system viewport admission, 62 geometry cases; inset и zero-inset tail по 64 кадра без разницы, прежние replay/async/459 flat-кадров сохранены | Не проверено | UIKit button-menu IME: 9 endpoint-сцен + 6 selection/reopen-сцен, 12 callbacks; Flutter parity не проверен | Принято на host; продуктовые пункты перенесены в 5.3 |
| P3, согласованность кадра | Единица 0 | `c9fdbf6f` + `frame_phase_probe_test.dart` | 8 сценариев: microtask-фаза и `frameTime` не зависят от порядка ticker, `clock.time` отстаёт на кадр | Не проверено | Не требуется для времени | Принята microtask-фаза и штамп по метке кадра; Stage отклонён |

## Приложение B. Рассмотренные варианты

- Общие helpers без объединения routes. Остаются две системы представлений с повторёнными частями.
- Ядро Stage и таблицы узлов как основа. Основа зависит от непроверенной переделки рендерера и нерешённого контракта route.
- Меню на `OverlayEntry` с `LocalHistoryEntry`. Focus trap, Esc, barrier и veto пишутся заново, правил navigator два.
- Routes на `AnimationController` возвращены на сравнение в P1: SDK поддерживает `unbounded` и произвольные симуляции. Выбор определяется сохранением метки времени касания, сетки кадров, дрёмы, прерываний и передачи хвоста, а также объёмом адаптера route.
- Painter-шов на Widget. Пользовательский painter пересобирается каждый кадр.

## Приложение C. Риски

| Риск | Единица | Что делать при срабатывании |
| --- | --- | --- |
| Цена кадра проецируемой анимации выше потолка | 0, 5.1 | Проекция только статуса (единица 0). |
| Меню как route теряет повторное открытие или первый кадр | 0, 5.3 | Решение владельца до 5.3. |
| Перенос времени неточен при задремавших часах | 0, 5.3 | Первый host-проход P2 воспроизводит потерю первого интервала и скачок от старого якоря дрёмы; полный route replay обязателен до переноса. |
| Push во время hold отменяет указатель | 0, 5.3 | Ранний route на source pointer-down до ancestor Navigator Listener проходит replay; отложить content/focus/barrier и проверить наблюдаемый lifecycle. Не игнорировать настоящие PointerCancel. |
| Движение начинает закрываться до veto SDK | 0, 2.4, 5.3 | Синхронный и async-допуск смонтированной policy проверены до closing в P2. Запрос до mount и более сильная атомарность после ответа SDK остаются открыты; временный внутренний допуск не заменяет typed E. |
| При передаче меняется закон слияния | 0, 5.3, 6 | Изолированный стенд: 981–1382 изменённых пикселя при 3×; сохранённый контур даёт 0. Переносить поле/контур и доказать полный бар на каждом кадре. |
| Проекция route расходится с внутренним `_controller` | 0, 5.1-5.3 | Уже существующие `didAdd`/`didReplace`, начальные `Pages`, `Navigator.replace` и restoration проверяются в P1; повторить тесты жизненного цикла на каждой версии SDK. |
| Canvas-шва не хватает фирменному стеклу | 6 | Открытый вопрос 5 в `foundation-review.md`. |
| Обязательный `MorphHost` требует лишних обязанностей от виджетов | 3 | До массового переноса проверить switch, меню и sheet, разрешить композицию общих механизмов. |
| Типизированная очередь задерживает callbacks ввода до кадра | 2.4, 3 | Доставка после команды ввода, проверка до `pump`, порядок и повторный вход из callback. |
| Правило уровня окна неверно в топологии приложения | 5.2, 5.3 | Открытый вопрос 7 в `foundation-review.md`. |
| Удаление `_OutlineTracer` или blend `angularBlendRadius` меняет пиксели | 6 | Паритет на iPhone до удаления. |
| Build hook тихо переходит на fake | 8 | Проверка фактического liquid tier на чистом checkout. |

## Приложение D. Что читать

- `CLAUDE.md` задаёт цель, правила и устройства. `docs/architecture/foundation-review.md` и `foundation-sketch.md` описывают решение и типы.
- `docs/engine.md` и `docs/engine-rules.md` устаревают после единицы 5.3, `docs/widgets.md` после единицы 3, `docs/glass.md` после единицы 6. Все четыре документа переписываются в единице 7.
- `docs/performance.md` и `docs/testing.md` описывают benches, ловушки тестов и отклонённые эксперименты. Паспорта лежат в `tool/ios_reference/spec/`, каталог в `tool/ios_reference/coverage/`, исследования в `tool/audit/`.
- Эти проверки расширяются, а не заменяются: `test/morph_route_lifecycle_test.dart`, `test/morph_teardown_test.dart`, `test/motion_route_ownership_test.dart`, `test/morph_focus_test.dart`, `test/lifecycle_counts_test.dart`, `test/perf_counts_test.dart`, `test/glass_frames_test.dart`, `example/test/control_matrix_test.dart`, `example/test/gallery_test.dart`.
