# Аудит lib/ и правки, ночь на 2026-10-12 - handoff

Обновление 2026-10-14: готовые изменения этой ветки уже входят в
`wip/measured-liquid-glass`; ниже исторический отчёт на момент передачи.
Текущее состояние и оставшиеся задачи: [уборка веток 2026-10-14](2026-10-14-branch-cleanup.md).

Ветка `audit/2026-10-12` (от `wip/measured-liquid-glass` @ cbfac78), 101 коммит
поверх неё и этот файл. НЕ влита в wip, НЕ запушена. Устройства ночью не
подключались: ни одна правка не мерилась на Pixel/iPhone.

## Что было сделано

1. Аудит всего `lib/` (63 тыс. строк): 13 областей, ревьюер + скептик на каждую.
   140 подтверждённых находок (7 high, 35 medium, 98 low).
2. Правки: 13 агентов в отдельных worktree, по одному на область; коммиты
   перенесены в эту ветку. Правило: чинить баги и pixel-identical
   перф/упрощения; всё, что меняет пиксели, ощущение, публичный API,
   измеренные константы или требует переписывания подсистемы, - отложить.
   Итог: ~103 исправлено, ~42 отложено (список решений ниже).
3. Ревью слитого диффа на регрессии (4 среза + проверка): найдено и исправлено
   4 регрессии, внесённые самими правками:
   - 1c43a41 vessel не обновлял semanticLabel при ретаргете;
   - 952dc8f RetainedGlassClip держал устаревший путь после Clip.none;
   - b6a6d07 settle() одного меню сбрасывал префетчи fusion всех меню;
   - 0f79fa4 гейт перерисовки skin смотрел на прямоугольники прошлого кадра
     (тест на этот случай не написан: сценарий с движущимся источником
     сложно собрать на хосте; закрыт консервативным условием).

## Проверено на Mac

- `dart format` 0 изменений, `flutter analyze` 0, `dart doc --dry-run` 0.
- `flutter test`: 1549 пройдено (2 skip), example: 47 пройдено.
- `flutter build macos --release` и `flutter build web --wasm` собираются.
- Почти каждый баг-фикс имеет хост-тест, падающий до правки.
- test/fixtures/perf/counts.json: потолки только понижены (меньше builds /
  paints / pictures / offscreen в сценах меню, fake/liquid, tab bar и др.).

## НЕ проверено (утром)

- Autodemo на macOS (GUI, ночью не запускал).
- Pixel 6a: кадры и энергия. По CLAUDE.md перф-правка принимается только по
  замерам на устройстве - сейчас это кандидаты, не допущенные изменения.
  Минимум: nav_quick (push/pop), меню, шит, tab bar, home-scroll, controls,
  liquid и flat, ABBA против cbfac78.
- Шейдеры (glyph_blur.frag, glass_shadow.frag, material_gradient_fragment.glsl,
  analytic_geometry.glsl): проверены offline-гейтом malioc и побайтовым
  сравнением рендеров на хосте, но нужен device parity
  (`tool/audit/shader/run_pixel.sh`) и iPhone.
- iPhone: визуальная сверка (меню вверх, бар-кнопки, слайдер, шит, date picker).

## Что исправлено и меняет пиксели (только там, где был баг)

- Меню, открывающееся вверх, со второго открытия шло в обратном порядке.
- Нажатие на кнопку бара начиналось не в той системе координат (капсула
  уезжала вбок на первом движении); второй палец перехватывал нажатие;
  disabled-кнопка бара оставляла semantics onTap.
- Отложенные ретаргеты элементов бара не проверяли поколение.
- Слайд навигации шёл по ширине MediaQuery, а свайп мерил ширину страницы.
- Слайдер: post-frame reconcile сбивал жест у квантующего родителя;
  переход continuous -> stepped рисовал ползунок в старой позиции.
- Шит: dimming Positioned без ключа пересоздавал поддерево шита посреди
  драга (драг замирал).
- Push zoom под PopScope(canPop:false) замирал в кадре драга навсегда.
- Endless frame loop у glass layer в покое (raster-phase watch) - приложение
  не уходило в idle. Важно для энергии: проверить на Pixel.
- Меню: непрерывно меняющийся MorphMenuWidget никогда не менял размер.
- MorphTheme.lerp: незаданная сторона бралась как 0, а не как builtin.
- glyph_blur.frag: NaN при sigma < ~0.15 texel (теперь пол 0.2 texel).
- MorphGlassContainer после смены светлая/тёмная тема выкидывал участников
  навсегда; glass hosts не следовали за morphLiquidGlassCapability.

Полный список исправленного по областям - в конце файла.

## Решения за тобой (отложено)

Меняют пиксели (одобрить глазом на iPhone, затем замер на Pixel):
- Снап масштаба глифов (MorphGlyphSnap) у подписи glass button, у строк меню
  под масштабом карточки, в date picker overlay (0.2 -> 1); search tab bar
  анимирует fontSize каждый кадр.
- Тени fake-тира через saveLayer + dstOut вместо even-odd клипа (web).
- Шейдеры: sdfEllipse для круга, rseSuperellipse без тригонометрии,
  forward difference градиента fused body, tint fused по arg-min box,
  sdRoundedSuperellipse с cos с CPU - все NEAR, не точные.
- Отдельный набор analytic-вариантов на 1 фигуру (occupancy 50% -> 100%,
  +4 ассета, ALU растёт) - решить и мерить.
- Тень fused body (per-box вместо blur по контуру), glow без промахов кэша.
- Disabled-дни date picker без Opacity на каждый день (альфа в цвет - NEAR).
- Типографика при Dynamic Type (opsz/трекинг от масштабированного размера) -
  уже открытый gap в spec/typography.md, нужен замер на iPhone.
- Двойной клип lens content copy (на fake/Skia меняет край).

Требуют устройства, pixel-identical в теории:
- RepaintBoundary: контент полёта и replica, шит под per-frame Transform,
  inline-титулы навбара, подписи segmented, glass и его foreground в одном
  boundary. Добавляют слой; на Impeller выигрыш только в записи картинок.
- Zoom-страница в покое остаётся non-opaque: всё под ней растеризуется и
  тикает. Высокий приоритет для замера, но меняет пиксели у прозрачных
  zoom-страниц и ломает capture источника - нужен дизайн-решение.
- syncCoordinateMapping/localPaintClipAbove каждый кадр у frosted-слоёв
  (нужен дешёвый сигнал инвалидации).
- Матте-пассы с 64-px бакетами размера.
- Удержанный палец: часы тикают после успокоения пружин (lens, switch,
  slider, glass button) и задержки date picker/search (doze ломает
  pumpAndSettle у пользователей в тестах - решить).

Большие переписывания (не делались):
- Шаттл полёта как render object (сейчас ~45 элементов пересобираются на
  каждый тик; vessel-половина уже убрана).
- Бар: позиции элементов без пересборки всего бара на тик.
- Push zoom на live render object.
- Титул навбара получает края капсул post-frame (один устаревший кадр).

Поведение / API:
- Закрывающийся модальный non-vessel полёт глотает тапы до latch - как в
  UIKit или нет? Снять на iPhone.
- MorphSheetMotion.relayout при смене порядка детентов указывает не на тот
  детент (latent bug) - нужен публичный API для индексов.
- 13 публичных полей MorphMenuMorphSpec никто не читает - breaking.
- Жёсткий rect-клип внутри Material шаттла избыточен (кроме кастомных
  ShapeBorder / web) - убрать?

## Хозяйство

- Worktree агентов: `.claude/worktrees/wf_b1e7c59f-269-1..13` (ветки
  `worktree-wf_b1e7c59f-269-*`) и старый `agent-a3a195e07da3bb1e9`
  (с незакоммиченной шейдерной работой - не трогал). Удалить 13 новых:
  `for n in $(seq 1 13); do git worktree remove .claude/worktrees/wf_b1e7c59f-269-$n; git branch -D worktree-wf_b1e7c59f-269-$n; done`
- `git stash` "audit-pubspec-lock": локальное изменение example/pubspec.lock,
  бывшее в дереве до аудита.
- CHANGELOG не трогал: запись сделать при влитии.
- Отчёты агентов (полные, с заметками по каждой находке):
  ~/.claude/projects/-Users-tembeon-IdeaProjects-morph/0f69fe98-1a12-44a6-b18f-44fa6e214ae9/subagents/workflows/
  (wf_1993fd64-e6a - аудит, wf_b1e7c59f-269 - правки, wf_828982c9-d7f - ревью).

## Исправлено, по областям

`[pixels changed]` - пиксели меняются только там, где был баг;
`[device]` - подтверждается только на устройстве.

### engine-flight
- lib/src/anchor.dart:209 - any MorphAnchor rebuild while its flight is live marks the whole shuttle OverlayEntry dirty (LayoutBuilder relayout, transform walks, full frame
- lib/src/flight.dart:1688 - vessel flights (MorphMenuButton, context menu) rebuild the vessel Stack/scrim/GestureDetector/Semantics chain on every tick
- lib/src/theme.dart:121 - MorphTheme.lerp treats an unset maxScrimOpacity/scrimColor/shadowColor as 0/transparent, so a flight launched mid theme animation freezes a near- [pixels changed]
### engine-route-skin
- lib/src/skin.dart:948 - the skin repaints on every flight geometry tick even when no blob can form, and on every launch anywhere in the scope
- lib/src/liquid_field.dart:1010 - every cluster miss allocates a fresh grid, plus records, Offsets, closures, saddle lists and a record-keyed stitch map
- lib/src/liquid_field.dart:867 - LiquidTracer.trace rebuilds the whole Path point by point, cached clusters included
- lib/src/skin.dart:1409 - one clipPath per tinted piece plus one for the stroke [device]
- lib/src/skin.dart:1102 - reading flight.overlayBox inside paint can abort and throw when the flight's overlay is removed
- lib/src/route.dart:496 - the settled route page rebuilds the target content inside its MediaQuery-dependent LayoutBuilder
- lib/src/skin.dart:701 - the extraMasses setter repaints unconditionally
- lib/src/skin.dart:1330 - contentFilterQuality dartdoc promises a once-rasterized, resampled layer that Impeller does not provide
### glass-layer
- lib/src/glass/renderer/rendering/liquid_glass_layer.dart:2394 - endless frame loop: onCompositorTranslated runs _watchRasterPhase on every composited frame, and a layer t [pixels changed, device]
- lib/src/glass/renderer/rendering/liquid_glass_layer.dart:1524 - one active paint computes shaderCoordinateTransform 3-4 times; the raster-grid check evaluates it even on 
- lib/src/glass/renderer/rendering/liquid_glass_render_object.dart:404 - each paint walks every shape's ancestry three times; refreshRetainedGeometry builds geometryStructu
- lib/src/glass/renderer/internal/retained_glass_clip.dart:172 - a RenderClipPath with a clipper is rebuilt and re-pushed every frame (new Path, two Matrix4, an inversion, 
- lib/src/glass/renderer/rendering/liquid_glass_layer.dart:1888 - the liquid layer's shadow path can never draw (liquid shapes register const [] layer shadows)
- lib/src/glass/renderer/rendering/liquid_glass_render_object.dart:743 - unused APIs: effectBounds chain, hasLiquidGlassLayerAncestor, TransformTrackingRepaintBoundaryMixin
### glass-renderer-rest
- lib/src/glass/renderer/internal/ancestor_clip.dart:57 - localPaintClipAbove/screenClipAbove allocate two Matrix4 per ancestor every frame, and screenClipAbove does one ge
- lib/src/glass/renderer/liquid_glass.dart:183 - every glass shape wraps const SizedBox.expand() in a live shape clip plus an always-compositing RenderOpacity (an OpacityLa
- lib/src/glass/renderer/fake_glass.dart:196 - the standalone FakeGlass path, RawFakeGlass, useFake and the dead LiquidGlass branches are unreachable; RawFakeGlass.live is 
- lib/src/glass/renderer/rendering/liquid_glass_render_object.dart:404 - geometryStructure list built twice per retained refresh
- lib/src/glass/renderer/liquid_shape.dart:5 - Equatable == on LiquidShape, LiquidGlassSettings, LiquidGlassAppearance, the color models (and ShapeGeometry) allocates props
- lib/src/glass/renderer/rendering/consolidated_fake_glass_layer.dart:219 - _cachedFilter not invalidated on devicePixelRatio change
- lib/src/glass/renderer/rendering/liquid_glass_render_object.dart:742 - effectBounds, gatherGlassGeometryBounds, effectSamplingReach (+overrides) and hasLiquidGlassLayerAn
- lib/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart:392 - field matte without materials still packs and uploads the full GeometryUniforms block [device]
### shaders
- lib/src/widgets/shaders/glyph_blur.frag:49 - pairs() builds all 7 tap pairs per axis even for the 3 and 5 tap kernels
- lib/src/widgets/shaders/glyph_blur.frag:50 - the pair weights multiply an underflowing Gaussian by an overflowing exp; NaN reaches fragColor for sigma < ~0.15 texel [pixels changed]
- lib/src/glass/renderer/shaders/glass_shadow.frag:134 - the shadow solves sdfSquircle on every pixel, including the interior (coverage 0) and far outside (coverage 1); tan
- lib/src/glass/renderer/shaders/gpu/material_gradient_fragment.glsl:39 - materialShapeTint is a 32-way if-chain
- lib/src/glass/renderer/shaders/analytic_geometry.glsl:56 - dead `out int index` / `nearest`, and the debug-only uAnalyticFlatFace uniform
- tool/audit/shader/offline.py:51 - the gate silently skips glass_shadow.frag and the three lib/src/widgets/shaders shaders
### glass-seam
- lib/src/widgets/glass_container.dart:467 MorphGlassContainerLink keeps its reference appearance across a brightness flip, so resting members drop out and never rejoin
- lib/src/widgets/glass_channel.dart:496 glass hosts do not follow morphLiquidGlassCapability, so a resting host pinned to liquid keeps its fake tree after the capability r
- lib/src/widgets/glass_channel.dart:555 a host both dirty from frames and rebuilt by its parent evaluates and pushes the frame twice per frame
- lib/src/widgets/glass_liquid_draw.dart:788 _ContentCopyPainter allocates about 3 Matrix4 per strip and 3 per slot every paint
- lib/src/widgets/glass_liquid_draw.dart:211 a layer's defaultAppearance is computed once and brightness is not in the structure, so after a theme flip the fake tier keeps 
- lib/src/widgets/glass_liquid_draw.dart:588 _Platter's GlassLiveOpacity always yields 1
- lib/src/widgets/glass_inspector.dart:406 inspector _resting re-implements the container join test without the appearance check and suggests containers that would reject m
### outline-fusion
- lib/src/widgets/menu_fusion.dart:163 - the fusion worker always fuses with the full field, even for a flat frame that reads only the edge [device]
- lib/src/widgets/menu_fusion_worker_io.dart:103 - MorphFusionWorker.reset() has no caller; queued requests keep running and up to 9 fusions stay retained after a motion
- lib/src/widgets/menu_fusion_worker_io.dart:131 - _fail never kills the worker isolates it already spawned
- lib/src/widgets/glass_outline.dart:1014 - the five global outline caches are 4-entry FIFOs; a hit never refreshes its entry
- lib/src/widgets/glyph_scale.dart:846 - RenderMorphGlyphSnap.pushTransform passes no oldLayer, so each paint makes a new TransformLayer
- lib/src/widgets/glass_outline.dart:1516 - MorphGlassOutlineClip unused; MorphGlyphRaster.sampleLogicalBounds set only by tests
### menu
- lib/src/widgets/menu_motion.dart:1131 relayout builds the root unreversed while _reversed stays set, so from the second opening an upward menu lists its rows in the wrong [pixels changed]
- lib/src/widgets/menu.dart:540 a pending timeline event (finger resting on a submenu row, 0.525 s hover open) keeps the menu ticker drawing identical frames
- lib/src/widgets/menu_host.dart:226 updateEntries relays out and wakes a closed menu on every parent rebuild, reloads build-made deferred groups and grows the cache
- lib/src/widgets/menu.dart:614 MorphMenuButton bypasses MorphControlHost: new glyph per build defeats the resting-face cache; post-frame flight.markNeedsBuild on every bui
- lib/src/widgets/menu.dart:934 the keyboard handler and the semantic select each compute their own 'top card', which disagrees with the motion's _topCard
- lib/src/widgets/menu_motion.dart:1747 the cards getter rebuilds the whole card list several times per frame, including inside rootBlob
- lib/src/widgets/menu_host.dart:297 the prebuild count grows without bound and the prebuild overlay entry rebuilds every tick after all rows are built
- lib/src/widgets/menu_motion.dart:1177 every content change re-arms the resize delay, so a continuously changing MorphMenuWidget never resizes the menu until it stops [pixels changed, device]
- lib/src/widgets/menu.dart:2399 the fallback submenu card clipper and platter painter always invalidate, so Path.combine and the blurred platter run on every layer rebuild
### context-sheet-alert
- lib/src/widgets/sheet.dart:759 - the unkeyed dimming Positioned re-inflates the sheet subtree when dim crosses 0 mid-drag, which disposes the drag recognizer and freezes 
- lib/src/widgets/sheet.dart:518 (+ alert.dart _move/_up) - every pointer move stamps, which wakes the clock, so a resting sheet or popover ticks a motion frame per move
- lib/src/widgets/alert.dart:596 - _AlertView.build depends on the whole MediaQuery and runs _fitsInRow TextPainters on every build, so keyboard frames rebuild the whole ca
- lib/src/widgets/sheet.dart:636 - _SheetViewState.build creates a new Builder(_route.builder) on every build, so keyboard frames rerun the app's whole content builder
- lib/src/widgets/morph_context_menu.dart:570 - the hold clock ticker runs until pointer up even after the hold recognizer lost the arena to a scroll
- lib/src/widgets/alert.dart:610 - button GlobalKeys are assigned by display position, so the focus state follows the slot, not the action, when the row flips to a column
- lib/src/widgets/alert.dart:1089 - nested ternary for the button block top padding has identical first two branches
### bars-navigation
- lib/src/widgets/bar_items.dart:1107 - a bar button press starts from an item-local point minus the capsule's bar offset, so the first move leans the capsule sideways [pixels changed]
- lib/src/widgets/bar_items.dart:1103 - no pointer ownership: a second finger steals the press, fires the wrong button and leaves the first capsule unsettled, so the ticker
- lib/src/widgets/bar_items.dart:1476 - the Semantics onTap of a disabled bar button still calls onPressed
- lib/src/widgets/bar_motion.dart:825/843 - the delayed retargets for existing and newborn items do not check generation [pixels changed]
- lib/src/widgets/scroll_edge_effect.dart:588 - cascade `Paint()..color = separator` plus a second Paint allocation on every hard-edge repaint
- lib/src/widgets/navigation_stack.dart:600 - buildTransitions creates a new Listenable.merge every tick, so GlassLiveTransform rebinds its listeners every frame
- lib/src/widgets/navigation_stack.dart:598 - the slide translates by the MediaQuery width while the edge swipe measures in the page width, so a narrow stack does not track [pixels changed]
- lib/src/widgets/bar_motion.dart:562 - setDrift re-pairs the capsules on every progress frame of an interactive pop
- lib/src/widgets/toolbar.dart:95 - MorphBarItems has no build gate; every parent rebuild, including every keyboard-inset frame, re-runs _relayout and rebuilds every item a
### lens-controls
- lib/src/widgets/stepper.dart:183 - a held stepper ticks every vsync while it waits for the next 500 ms repeat
- lib/src/widgets/slider.dart:318 - every echoed value during a drag or glide rebuilds the whole slider body
- lib/src/widgets/tab_bar.dart:435 - MorphTabBar has no buildsLike/buildInputs and re-measures every label on every build
- lib/src/widgets/tab_bar.dart:735 - both lens clippers reclip on every tick even when the lens does not move
- lib/src/widgets/glass_button.dart:510 - per-frame ListenableBuilder + Transform rebuild and Matrix4 allocations
- lib/src/widgets/slider.dart:153 - the post-frame reconcile calls setValue during a drag and glide, so a quantizing parent kills the flex, stretch and glide [pixels changed]
- lib/src/widgets/slider_motion.dart:138 - switching a slider from continuous to stepped draws the thumb at a stale settle position [pixels changed]
- lib/src/widgets/segmented_control.dart:181 - label widths re-measured with fresh TextPainters on every LayoutBuilder pass
- lib/src/widgets/lens_driver.dart:61 - post-frame reconcile duplicated three times (lens driver, switch, slider)
- lib/src/widgets/slider_motion.dart:266 - _Press.samples grows without bound during a drag
### picker-search
- lib/src/widgets/date_picker.dart:1474 month grid rebuilt inside the per-frame ListenableBuilder on frames
- lib/src/widgets/date_picker.dart:1058 no RepaintBoundary under the per-frame Transform/ClipRRect of the overlay [device]
- lib/src/widgets/search_field.dart:734 toolbar/tab bar rebuild field, label measures and bar on every keyboard-inset frame
- lib/src/widgets/search_tab_bar.dart:391 invisible field relaid out at the moving searchRect during the morph
- lib/src/widgets/search_field.dart:387 MorphTouchListener enabled flag goes stale on focus change in a standalone field
- lib/src/widgets/search_tab_bar.dart:191 searching:false clears without onQueryChanged('') and clears during build
- lib/src/widgets/search_field.dart:823 toolbar _GlassItems and MorphGlassStage created inside the per-frame builder
- lib/src/widgets/date_picker.dart:2330 _WheelGeometry.shade builds a ~90-110 stop gradient on every paint
- lib/src/widgets/date_picker.dart:374 every picker rebuild makes the open overlay setState
- lib/src/widgets/search_field.dart:222 disabled field cancels the press and wakes the ticker on every didUpdateWidget
- lib/src/widgets/date_picker.dart:1271 _canTurn duplicates _turn's month-boundary rule
### misc-widgets
- lib/src/widgets/push_zoom.dart:177 - a dismissing drag on a page under PopScope(canPop:false) leaves the page frozen in its drag frame with the clock ticking forever
- lib/src/widgets/push_zoom.dart:101 - advanceMotion captures the source rect on every opening tick and discards it
- lib/src/widgets/push_zoom.dart:153 - every pointer down on an open zoomed page stamps and wakes the clock for a full shell rebuild and a source capture
- lib/src/widgets/page_control.dart:195 - the page control ticks and repaints every frame while a finger rests on it; prominent/minimal still run the unused platter timelin
- lib/src/widgets/page_control.dart:600 - the painter computes dot centers with center(i), O(n^2) spring evaluations per paint
- lib/src/widgets/widgets_theme.dart:210 - morphResolveStyle walks the ancestor chain twice (extension and brightness)
- lib/src/widgets/activity_indicator.dart:241 - _SpinnerPainter allocates a 16 x 8 Paint table on every build
- lib/src/widgets/widgets_theme.dart:1 - imports package:flutter/material.dart against the documented rule
