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
- **Сделать.**
  - [ ] P1. `MorphMotionRoute`, `MorphRouteAnimation`, `MorphSettleSignal` и `MorphPopupRoute` на копии sheet. Сравнить с вариантом на SDK controller по времени события, сетке кадров, дрёме, прерываниям и объёму собственных обработчиков route. `AnimationController.unbounded` и `animateWith` доступны; перелёт сам по себе не обосновывает отказ от controller.
  - [x] Первый host-проход P1: `example/lib/proto/route_probe.dart`, 32 проверки в `example/test/proto/route_probe_test.dart`, результат в `tool/audit/foundation-p1-2026-10-15/report.md`. Оба драйвера проходят проверенные lifecycle-сценарии. Это сокращённый sheet; полные часы и продуктовый perf-гейт ещё не проверены, P1 не закрыт.
  - [x] Сокращённый P1 на iPhone 16 Pro, iOS 27.0.1, profile, 120 Гц: редактор с нативной клавиатурой, фокус и ввод, 16 циклов открытия/закрытия. Артефакты в `tool/audit/foundation-p1-2026-10-15/iphone/`. Измеренные интервалы укладываются в 8,33 мс, но продуктовая сцена, сравнение с UIKit, Pixel и энергия ещё не проверены.
  - [x] Первый проход времени P1: 55 host-проверок суммарно, включая 16 сравнений извлечённых часов с текущим `MorphClock` и семь проверок SDK controller. Сетка кадров и дрёма с сохранением push future достижимы на SDK; прямой `stop()` и несогласованное присваивание `muted` воспроизведены как неверные варианты. Отчёт `tool/audit/foundation-p1-2026-10-15/timing/report.md`. Единый адаптер времени route и передача владения ещё не проверены.
  - [ ] P2. Меню как route на root navigator: передача хвоста кнопке при первом пересечении нуля, повторное открытие во время закрытия, непрерывный перенос времени всей модели между часами route и кнопки. Отдельный `rebase` каждой пружины не добавляется без подтверждённого потребителя.
  - [x] Первый проход передачи P2: 33 проверки всей `MorphMenuMotion`, единственного владельца, повторного открытия до и после передачи, первого кадра спящих и дремлющих часов при 1× и 5×. Отчёт `tool/audit/foundation-p2-2026-10-16/report.md`. Полный menu route, replay через него, контур группы бара и устройство ещё не проверены.
  - [x] Первый root-route P2: настоящий `PopupRoute`, 15 сценариев Navigator и три дополнительные проверки часов; 106 проверок прототипов суммарно. Передача до конца хвоста, reopen с route и источника, SDK barrier/PopScope/Escape/focus, живой редактор, удаление источника и 20 циклов без оставшихся кадров проходят. Отчёт `tool/audit/foundation-p2-2026-10-16/route/report.md`. Это сокращённая отрисовка с фиксированной геометрией; replay жестов, контур бара и perf ещё нужны.
  - [x] Записанный ввод P2: 20 replay на 60/120 Гц через binding и root route, исходные touches и доступные метки доставки, смещение часов 37 с. Ещё шесть проверок раннего route и три проверки контура; суммарно 135 проверки прототипов, включая контрпримеры. Отчёт `tool/audit/foundation-p2-2026-10-16/input/report.md`. Ранний route сохраняет hold/drag, содержимое и фокус появляются при открытии; поздний push отменяет указатель. Контрпримеры показывают обход `PopScope` при закрытии из модели и скачок при немедленной смене закона слияния.
  - [x] Синхронный допуск и flat-сцена P2: `PopScope` запрещает closing до изменения каналов для outside/row/early outside/Back/Escape; разрешённая реакция сохраняет исходное время. Шесть проверок модели, две проверки очистки callback и два сценария `LocalHistoryEntry`: внутренний pop оставляет меню открытым. Настоящий widget сравнивается с непрерывной моделью на каждом кадре закрытия и хвоста: шесть сцен, 459 кадров на 60/120 Гц, 3×, ноль отличающихся пикселей. Всего 149 проверок прототипов. Отчёт `tool/audit/foundation-p2-2026-10-16/admission/report.md`.
  - [x] Асинхронный допуск смонтированной policy P2: один ожидающий запрос и одноразовый допуск к pop, отказ/ошибка/retry, повторный вход и одновременные SDK обращения, cover/uncover, замена/удаление route, источник и Navigator. 25 новых async-проверок и контрпример backdating; 175 проверок прототипов суммарно. Траектория после принятия решения сравнивается с текущим состоянием модели на 60/120 Гц и 1×/5×. Исходное время сохраняется как provenance, синхронный путь сохраняет измеренный deadline. Протокол `docs/architecture/menu-dismissal-protocol.md`, отчёт `tool/audit/foundation-p2-2026-10-16/async/report.md`.
  - [x] Первый mount и ранний lifecycle P2: готовность реального поддерева policy, отменяемое ожидание, Back до невидимого открытия, synchronous teardown часов/фокуса и защита отменённой подготовки от нового down. 15 lifecycle-сценариев и четыре проверки disposal часов; всего 194 проверки прототипов. Настоящий nested hold сохраняет down/move/up и выбирает root. Root observers/currentness меняются уже на невидимой подготовке — это подтверждённая цена прототипа, не выбор продуктового presenter. Протокол `docs/architecture/menu-route-lifecycle.md`, отчёт `tool/audit/foundation-p2-2026-10-16/lifecycle/report.md`.
  - [x] Владение вводом P2: настоящий source hit и currentness всей modal/Navigator цепочки, отзыв held sequence при cover, reentrant disposal без устаревших наблюдений и синхронный hit gate закрывающихся page/barrier. 23 новых проверки; всего 217 проверок прототипов и 307 example. Escape/Back проверены на plain/nested WidgetsApp и Router с root/приоритетным child dispatcher; глобальный приоритет клавиш не меняется. Подтверждённый release сохраняет отложенный action, поздний up отозванного удержания его не создаёт. Протокол `docs/architecture/menu-input-ownership.md`, отчёт `tool/audit/foundation-p2-2026-10-16/input-ownership/report.md`.
  - [x] Окружение source/root popup P2: SDK `InheritedTheme.capture` до выбранного Navigator, подписки source и отложенная публикация route-local снимка. Text/icon/custom themes обновляются без remount редактора/focus/PopScope; shared root themes и MediaQuery/locale/direction остаются живыми. Последняя тема переживает source detach. 13 новых проверок; всего 230 проверок прототипов и 320 example, анализатор без замечаний. Открытый route сохраняет исходные theme kinds; новая структура применяется при следующем открытии. Не-тематические page scopes передаются явно. Протокол `docs/architecture/menu-source-environment.md`, отчёт `tool/audit/foundation-p2-2026-10-16/source-environment/report.md`.
  - [x] Host Semantics P2, 2026-10-17: именованная source-кнопка и domain activation, scoped/named popup с одним SDK dismiss, hidden/closing exclusion и актуальные Flow bounds. 21 новая проверка, всего 251 прототипов и 341 example, анализатор без замечаний. Stale actions и reentrant cover/removal не получают права на ввод; отмена скрытой preparation под прозрачным cover сохраняет целую модель до передачи/покоя и удаляет точный route. SDK wrappers сохраняют content/policy State при semantic transitions. VoiceOver/TalkBack и полные item roles этим не доказаны. Протокол `docs/architecture/menu-accessibility-lifecycle.md`, отчёт `tool/audit/foundation-p2-2026-10-16/accessibility/report.md`.
  - [x] Held reopen до hand-back P2, 2026-10-17: раннее резервирование SDK route без переноса модели до измеренного открытия. Прежний route сохраняет content/clock/Flow и обычную передачу хвоста; новая policy/editor tree строится заново. 24 новые проверки, всего 275 прототипов и 365 example. Настоящие down/move/up на 60/120 Гц при 1×/5×, outgoing/первый видимый новый content, focus, отмена, Back, cover, source loss и reentrant removal проходят. Первый mount под cover откладывается до uncover; подтверждённая модель продолжает движение. Прежние 40 hand-back и flat-сцены неизменны. Протокол `docs/architecture/menu-held-reopening.md`, отчёт `tool/audit/foundation-p2-2026-10-17/held-reopen/report.md`.
  - [x] Source affinity P2, 2026-10-17: сохранённый GlobalKey State получает новую private session при смене root Navigator/View; старый popup сохраняет собственные model/clock/content/policy и ввод исходного View, без чужого hand-back. Same-root nested relocation сохраняет lifetime. Скрытая preparation/reservation завершается адресно вне tree lock; потерянный source-owned хвост остановлен и может остаться не settled, без скрытого ticker. 17 новых проверок, всего 292 прототипа и 382 example, анализатор чистый; прежние replay/async/flat записи совпали. Реальные framework View trees проверены на host, native multiwindow и живая геометрия ещё нужны. Контракт `docs/architecture/menu-source-affinity.md`, отчёт `tool/audit/foundation-p2-2026-10-17/source-affinity/report.md`.
  - [ ] До закрытия P2 принять или отклонить ранний реальный push с его observer/currentness/traversal-семантикой и определить продуктовый контракт hidden Escape/Router; определить поддержку source-local locale/RTL, проверить native accessibility и held-reopen/focus на устройстве, native multiwindow, живую source geometry и оставшийся menu API. После передачи успешного ответа SDK остаётся его обычная проверка current entry/policy; более сильная атомарность выдачи ответа и SDK commit не доказана. Flat-сцена фиксированного бара сохраняет Gaussian-контур меню вместе с контейнерным контуром соседей; полный продуктовый бар и перенос оптического поля liquid/fake, геометрия source link и device/perf-гейты ещё нужны. Контрпримеры и сокращённый стенд не закрывают весь P2.
  - [ ] P3. Согласованность кадра в двух вариантах: часы на host с одной упорядоченной фазой после всех ticker, и Stage на `FlutterView` с фазами advance, publish и commit на `TickerMode.getValuesNotifier`. Результаты записываются в приложение A.
- **Видно.** Ничего, прототипы живут вне продукта.
- **Проверка, unit.**
  - [ ] P1 проходит, если закрывающийся sheet пропускает нажатия и освобождает фокус с первого кадра закрытия, завершается в видимом покое, `pushReplacement` держит заменённый route до покоя, veto через `PopScope` оставляет sheet, редактор во вложенном Navigator сохраняет State, а число сборок на кадр движения укладывается в потолки `perf_counts.json`.
  - [ ] P1 отдельно проверяет начальные `Pages`, `Navigator.replace` и restoration: значение и статус проекции, непрозрачность overlay и завершение route согласованы. В SDK 3.47.2 `didAdd` и `didReplace` меняют только внутренний controller, независимая проекция обрабатывает эти пути явно. `pushReplacement` эту проверку не заменяет.
  - [ ] P1 записывает поведение Hero между двумя `MorphNavigationRoute` с установленным `HeroController`. Первый релиз Hero не обещает, результат решает, войдёт ли он позже.
  - [ ] P2 проходит, если replay открытия, протяжки, закрытия, хвоста посадки и повторного открытия посреди закрытия совпадает с fixtures, контур группы бара непрерывен через посадку (host golden на кадр), а перенос времени всей модели точен при задремавших часах в кадре передачи.
  - [ ] P3 проходит, если кадров в покое ноль, все чтения чужого движения идут после всех advance, а у Stage нет утечки состояния между `testWidgets`.
- [ ] **Проверка, устройство.** Pixel 6a, открытие и закрытие sheet (P1), первый кадр меню (P2), tab bar, segmented и меню (P3).
- [ ] **Проверка, perf.** Время кадра и энергия каждого варианта рядом с текущей реализацией.
- **Гейт кода.** Для прототипов не требуется, они не попадают в `main`. Внутренний допуск P2 отдельно не переносится в `main`: его замена типизированными событиями проходит гейт единицы 2.4.
- **Удалить в этом же юните.** Ничего.

P1 фиксирует выбранный вариант route и причины выбора. Если побеждает SDK controller, сигнатуры и единицы 5.1–5.3 уточняются по результату до переноса в продукт. Если вариант с отдельной проекцией P1 не проходит по цене кадра, единица 5 проецирует только статус, а значение анимации меняется лишь на сменах фазы. Потребители SDK теряют плавный прогресс, это объявляется в dartdoc. Если P1 не проходит по поведению фокуса, нажатий или завершения, решение возвращается владельцу до единицы 5. Если P2 не проходит, меню остаются на урезанном внутреннем presenter на `OverlayEntry`, и решение о двух системах представлений возвращается владельцу. Если P3 не проходит ни в одном варианте, единица 3 не трогает `MorphFrameSync` и microtask.

## Единица 1. Новый main и вырезание legacy-движка

- **Зависит от.** Ничего, вычитание идёт раньше добавления.
- **Файлы.** Строки единицы 1 в таблице "Legacy-движок" `foundation-sketch.md`. Целиком уходят `route.dart`, `anchor.dart`, `shared.dart`, `measure.dart`, `frame.dart` и `skin.dart`. Из `show.dart`, `target.dart`, `gesture.dart` и `flight.dart` уходят только пресеты, фабрики кроме vessel, функции drag и shuttle без vessel, а `showMorph`, vessel и `morphRubberband` живут до своих единиц. Также `engine_page.dart`, 54 legacy-теста, мёртвый код рендеринга, `navigation_snapshot.dart`, `pubspec.yaml`, новые `test/architecture_test.dart` и `test/api/public_api.txt`.
- **Сделать.**
  - [ ] Создать новую `main` от выбранного SHA `wip/measured-liquid-glass`. Старое содержимое `main` остаётся на `v0.4.0`.
  - [ ] Удалить legacy-движок по строкам единицы 1. Убрать из экспорта `MorphController`, `closeAll`, `MorphFlightScope` и другие имена движка без потребителя в слое виджетов, сами классы умирают в 5.3.
  - [ ] Удалить мёртвый код рендеринга, флаги отклонённых экспериментов и `equatable`. `GlassCostProbe` перенести в тестовый helper.
  - [ ] Добавить `test/architecture_test.dart` с таблицей направлений зависимостей и allow-list SDK. Проверять import и export во всём `lib/`, включая точки входа, все условные ветви и достижимые сторонние runtime-зависимости с оговорённой границей SDK. Для чистых `*_motion.dart` отдельно запретить импорт widget/host своего и других семейств. Текущие нарушения (`material_ui`, `package:flutter/material.dart`, `motor`) записаны в тесте списком, который может только сокращаться.
  - [ ] Добавить golden публичного API, построенный из модели элементов анализатора, вместе с внешними реэкспортами. Генератор заменяет `tool/ios_reference/coverage/export_api.dart`.
- **Видно.** В галерее нет страницы движка. Меню, контекстное меню и sheets работают как раньше.
- **Проверка, unit.**
  - [ ] Тесты меню и контекстного меню не изменены и зелёные.
  - [ ] `architecture_test` и golden API зелёные.
  - [ ] Отрицательные fixtures подтверждают обнаружение запрещённого export, транзитивной runtime-зависимости и импорта host из motion. Golden API не заменяет эти проверки.
- **Проверка, устройство.** Не требуется, потому что путь по умолчанию и пиксели не меняются.
- [ ] **Проверка, perf.** `perf_counts.json` без изменений.
- [ ] **Гейт кода.** `/deslop`, `/no-comments`, comment-sicko по удалениям и двум новым тестам. Ревизия и итог записаны.
- **Удалить в этом же юните.** Строки единицы 1 таблицы "Legacy-движок" и перечисленный мёртвый код. Старый `main` не сливается с новым.

## Единица 2. Время

Выполняется последовательными изменениями 2.1–2.5, каждое с отдельным commit и проверкой затронутых replay до следующего шага. Решатель, критерий покоя, временной API, доставка событий и удаление motor не объединяются в один commit. Номера 2.1–2.5 уточняют эту единицу; зависимости от единицы 2 означают завершение всех пяти шагов. Это внутренний порядок миграции без публичного слоя совместимости.

- **Зависит от.** 1.
- **Файлы.** `spring_state.dart`, `channel.dart`, `timeline.dart`, `flex_integrator.dart`, `flex_interaction.dart`, все `*_motion.dart`, `lib/src/spring.dart`, `lib/src/motion.dart`, `controller.dart`, `flight.dart`, `gesture.dart`, `morph_context_menu.dart`, `pubspec.yaml`, паспорта затронутых контролов. Цель `lib/src/motion/`.
- **Сделать.**
  - [ ] 2.1. Перевести расчёт `MorphSpringState` на SDK `SpringSimulation`, сохранив существующие правила покоя и временной API. Подтвердить значение и скорость на fixtures в пределах 1e-9 и прерывания отдельно от смены критерия покоя. Форма переноса времени определяется P2; не добавлять `rebase` в пружину только ради первоначального эскиза.
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
  - [ ] `MorphTheme` как `InheritedTheme`, `MorphThemeData.appearances` по типу, `morphAppearanceOf`, `static const tables`, `lerp` у каждого appearance.
  - [ ] Sealed `MorphGlassRenderer` в `lib/src/theme/`: `adaptive`, `tier`, `painted`. До единицы 6 `painted` принимает текущий painter. В том же commit старый `class MorphGlassRenderer extends MorphGlassPainter` (glass_renderer.dart:113) становится внутренним `GlassBuiltInPainter`.
  - [ ] В flight.dart и show.dart заменить `Theme.of(context).colorScheme` (flight.dart:1699) и чтения `MorphTheme.default*` (flight.dart:579-582) на `MorphThemeData`, затем удалить все импорты Material.
  - [ ] `MorphLocalizations` с английскими строками по умолчанию.
  - [ ] Перенести `setFloatUniforms` из `flutter_shaders` в `scene/shaders.dart`.
  - [ ] Перевести галерею на `WidgetsApp` и собственную тему.
- **Видно.** Галерея работает без Material-предков. Цвета light, dark, high contrast и tint не меняются.
- **Проверка, unit.**
  - [ ] Список Material в `architecture_test` пуст.
  - [ ] `flutter pub deps` без `material_ui`, `cupertino_ui`, `flutter_shaders`.
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
  - [ ] Перенести из P1 `MorphMotionRoute`, `MorphRouteAnimation`, `MorphSettleSignal` и `MorphPopupRoute`.
  - [ ] `MorphSourceLink` и `MorphSource`, параметр `source:` у контролов, которые показывают sheet.
  - [ ] `morphPresentationNavigatorOf(context, level)` с уровнем как свойством семейства.
  - [ ] Перевести sheet.
- **Видно.** Zoom sheet не меняется. Страница под sheet видна во время zoom.
- **Проверка, unit.**
  - [ ] Предикат P1 на продуктовом sheet.
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
  - [ ] Один observer predictive back на binding для всех morph routes.
- **Видно.** Android back с предпросмотром на routes morph. Zoom из ячейки списка не меняется.
- **Проверка, unit.**
  - [ ] Replay navigation release (2bdb3e47, 5e163f5f).
  - [ ] Predictive back commit и cancel.
  - [ ] Alert и date picker на root navigator из вложенного navigator.
  - [ ] Veto и возврат фокуса.
- **Проверка, устройство.**
  - [ ] iPhone, push zoom, navigation, alert.
  - [ ] Pixel 6a, predictive back.
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

- **Зависит от.** 6.
- **Файлы.** `lib/morph.dart`, `lib/glass_painter.dart`, `lib/widgets.dart`, `lib/foundation.dart`, `lib/motion.dart`, example, тесты, `docs/`, `CLAUDE.md`, паспорта, `tem_tools/plugins/morph`, `README.md`, `CHANGELOG.md`.
- **Сделать.**
  - [ ] `morph.dart` около 100 имён и `glass_painter.dart` 5 имён. Example импортирует только их, тесты replay импортируют `src/`.
  - [ ] Перегенерировать golden API.
  - [ ] Переписать документы из приложения D, таблицу документов в `CLAUDE.md`, ссылки на код в паспортах и skill use-morph.
  - [ ] Рецепт подключения в README: зависимость по тегу, `MorphTheme`, GPU-флаги, прогрев, поведение без liquid. `CHANGELOG.md` прочитать перед записью.
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
- [ ] Асинхронные представления: исключение deferred loader, отклонённый Future, пустой результат, ответ после закрытия, быстрый reopen (`menu_content.dart`, `menu_entries.dart`).
- [ ] При длительном повторении основных сценариев overlay entries, активные tickers, подписки и память не растут от цикла к циклу. Число циклов и границы записаны до прогона.
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
| P1, проекция против SDK controller | Единица 0 | `78a22418` + локальные файлы и хеши в отчётах P1 | 55 проверок; паритет часов и SDK-дрёма/сетка; 4,4 / 8,0 перестроения на кадр базового стенда | Не проверено | Сокращённый profile-прогон: 16 циклов, редактор/клавиатура/фокус, 120 Гц; паритет UIKit не проверен | Не выбран; P1 открыт, отчёты `tool/audit/foundation-p1-2026-10-15/report.md` и `timing/report.md` |
| P2, меню как route | Единица 0 | `d9973893` + файлы и хеши в отчёте source-affinity | 292 проверки прототипов, 382 example; sync/async policy, lifetime/input/host Semantics, local themes, held reopen/content/focus и изоляция root/View; прежние 40 hand-back и 459 flat-кадров без разницы | Не проверено | Не проверено | Цена раннего push, keyboard policy и локальный locale/RTL не приняты; native accessibility/held-focus/multiwindow, живая source geometry, полный бар, оптика и граница ответа SDK открыты. P2 открыт; `tool/audit/foundation-p2-2026-10-17/source-affinity/report.md` |
| P3, согласованность кадра | Единица 0 | | | | | |

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
