# Candidate B: граница операций, один плоский snapshot

## Problem

Сейчас `_readGeometry` одновременно снимает source endpoint и решает, допустимо ли placement. Выделять отдельный endpoint-контроллер пока нечего: snapshot имеет одного владельца, один lifetime и один консервативный критерий согласия. Нужна граница знаний, сохраняющая все наблюдения, включая null при insufficient fit, покрытой кнопке и invalid viewport. Native selection/reopen не разрешает менять landing.

## Usage (caller's view)

```dart
ProbeMenuSource.measured(button: localButton, menuBuilder: buildMenu)

// Programmatic, semantic и raw-source пути по-прежнему сходятся здесь.
if (!session.admitGeometry()) return;

// Source sampling и land используют строгий active fence.
if (!session.checkGeometry()) return;

// Source painter проверяет ДО owner и получает только допустимый snapshot.
final geometry = session.sourcePaintGeometry;
```

Публичный API не меняется. Указатель использует сохранённый `geometry.position(global)`; глобальная карта overlay читается заново. Route sampling по-прежнему вызывает `checkGeometry()` ради наблюдаемой инвалидации, затем продолжает sampling своего старого transfer независимо от результата.

## Shape

Один файл, одна `_MenuGeometry`, те же восемь final полей. Разделение — по операциям, а не по дополнительным value bags.

1. State `_readGeometry(session)` владеет attachment/Offstage, RenderBox identity, layout, точным uniform source→overlay transform и конечностью source shape. Читает оба transform один раз. Это shell Flutter-наблюдения, не новый framework.
2. Чистая `_admitMenuPlacement(view, bounds, overlayToView, button, minimum)` полностью владеет viewport validity, max(safe,IME)/DPR, inverse projection, intersection, minimum-fit и полной containment source. Она заменяет `_availableMenuRect`, а не образует второй путь. Возвращает Rect либо null; ничто не допускается частично. Это `boundary-discipline`: null снаружи означает невозможность полного admission независимо от причины.
3. `_MenuGeometry` хранит только уже допущенный immutable результат. `_sameEndpoint(other)` сравнивает identity/map/button/bounds/shape. Единственный `agrees(other)` требует одновременно `_sameEndpoint` и equality available. Производные padding и input projection остаются рядом со snapshot (`single source of truth`). Никто не хранит отдельно placement, endpoint либо epoch.
4. Session остаётся единственным владельцем admission/retirement. `admitGeometry` и `checkGeometry` сохраняют алгоритмы и nullable полный reader. `sourcePaintGeometry` поглощает существующий двойной paint fence: сохранить snapshot, вызвать check, затем при idle сделать свежий read/full agreement. Это не pass-through: getter возвращает право нарисовать переносимый contour, включая same-frame land→layout защиту. Painter вызывает его до owner и рисует resting outline при null.

Такое разделение скрывает конкретную политику viewport в одной операции, не заставляя callers координировать endpoint и placement. Сравнение явно показывает две причины stale admission. Interface depth: одна более содержательная paint-операция заменяет знание session internals в painter; дополнительных consumer methods нет.

`_canRelayout`, persistent-phase отказ, snapshot-before-readiness и post-callback model/attachment/read проверка не меняются. Invalid active read немедленно вызывает прежний `loseGeometry`; восстановление метрик не возрождает endpoint. Старый shown popup сохраняет input/model/clock; hidden reservation и tail завершаются прежним путём. Fixed replay ветка не меняется.

## Synthesis decision

Заполняет parent judge. Независимая попытка того же inherited model; это не multi-model agreement.

## Tradeoffs accepted

- Сохраняем плоский snapshot вместо вложенного endpoint value ради меньшего количества типов и единственной формы принятого состояния.
- Сохраняем полный nullable read и консервативное согласие ради неизменного поведения; разделение не означает разрешения optical landing.
- Сохраняем повторное чтение paint fence ради same-frame layout защиты; оптимизация частоты чтения здесь не исследуется.

## Alternatives considered

Вложенные `_SourceEndpoint` + `_MenuAdmission`: endpoint скрывает capture/identity/position, admission — fit/padding. Это жизнеспособная композиция, к которой я пришёл сначала. Но при нынешнем единственном full-admission policy все callers всё равно зависят от aggregate, а wrapper добавляет навигацию по полям. Она выиграет, если появится доказанный отдельный endpoint consumer; сейчас операция placement изолируется без дополнительного типа.

Раздельные mutable placement/source snapshots отклонены: требуют синхронного обновления и допускают несогласованные версии при readiness reentry.

## Open questions and risks

Достаточно ли операции admission для следующего доказанного policy шага? Если понадобится endpoint при invalid placement, потребуется пересмотреть тип результата: current null contract намеренно сохранён. Это условие будущего дизайна, не вопрос, блокирующий данный refactor.

## Next implementation step

Перенести projection/fit/containment в одну placement-функцию и paint fence в session, сохранив 62 geometry cases, полный example и оба независимых 64-frame contour oracle без изменения ожиданий.
