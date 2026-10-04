# Pending CHANGELOG 0.7.0 lines from the audit-fix agents

Agents do not edit CHANGELOG.md concurrently; the coordinator merges
these into the 0.7.0 entry (read CHANGELOG.md first) and deletes this
file.

## WP-C bars and navigation (da7e6db, 8422729, 68aa6c7, 03b8b15, e6c510d, 4e8df30)

- BREAKING: `MorphNavigationConfig.signature` is removed. Configs, `MorphBarButton` and `MorphBarButtonGroup` now compare by value, with callbacks by identity, so a screen rebuilt with new closures updates the shared bar.
- Fixed: a bar item or capsule whose id returns while it is still fading out turns around instead of producing duplicate keys.
- Fixed: bar layouts compare ids by value (`1` and `'1'` differ).
- Fixed: an edge swipe that commits removes its own page even if another page was pushed during the swipe.
- Fixed: a page disposed mid-swipe ends the navigator's user gesture and the bar drift.
- Fixed: back-menu rows for screens that are gone do nothing.
- Fixed: the open back menu follows entry changes.
- Fixed: a scaffold inside a nested navigator keeps its own bars instead of leaking its config into the stack.
- New: `backLabel` on `MorphNavigationStack` and `MorphNavigationScaffold`.
- New: `menuStyle` and `menuOverlay` on `MorphNavigationStack`, `MorphNavigationBar` and `MorphToolbar`.
- New: `MorphToolbarMetrics`, `MorphBarMetrics.maxTextScale`, `MorphBarMetrics.lineHeight`, `MorphBarMetrics.backChevronHeight`.
- New: `==` on `MorphBarStyle` and `MorphBarMetrics`.
- Changed: `MorphNavigationScaffold`'s default background comes from `MorphScrollEdgeEffectThemeData`.
- Changed: under reduced motion, navigation pages fade in place instead of sliding.
- Changed: flat bar capsules fuse by geometry regardless of colour, the same grouping as the glass tiers.
- Changed: a bar button's menu opens from the accessibility long press.
- Performance: bar animation ticks no longer rebuild button contents, the flat fused outline is traced once per change, and label and title widths are cached.

WP-C left open: PF9 (edge effect BackdropFilter not grouped - visual change, WP-I), MorphBarMenuTuning static-only (P5api), D5 menu host merge (wave 3).

## WP-B engine registry, targets, skin (45fd91d, 6e32d80, 78a8aee)

- BREAKING: misusing a lookup now throws a descriptive FlutterError in every build mode (MorphScope.of, MorphTag.specOf/idOf, morphAnchorRect, an unknown `from:` id) instead of an assert in debug and a bare null-check crash in release.
- A duplicate MorphTag id in one scope is reported (FlutterError.reportError); the first tag keeps the id and the second takes over when the first leaves. A duplicate shared-element id on one side of a flight is reported too.
- A MorphTag moved under another MorphScope re-registers there; a tag outside any scope no longer crashes (a scope-less skin degrades to plain fusion).
- morphAnchorRect, shared-element rects and the skin's flight neck follow the whole paint transform, not just its translation.
- New MorphTheme.defaultMaxScrimOpacity / defaultScrimColor / defaultShadowColor / defaultTargetElevation.
- New MorphTheme.scrimMotion; `modal` and `scrimMotion` on showMorphSheet, showMorphDialog and MorphAnchor; a MorphAnchor whose `motion` changes while open updates the live flight.
- BREAKING: removed MorphDirection, MorphController.direction and MorphMotion.values.
- A skin cluster too large for the tracing grid coarsens instead of vanishing; `cell` below 2 px asserts in debug.
- The shared-element flying layer's key is `ValueKey<Object>(id)`.
- A MorphTag without `snapshotGhost` adds no RepaintBoundary or GlobalKey; skin repaints reuse buffers and paints.
- Adding one AnimationStatusListener twice to `MorphController.animation` no longer leaks a proxy.

WP-B follow-ups for WP-A (route.dart/flight.dart): add `MorphFlight.geometryTicks` (frameTicks without the scrim) and point the skin at it (PF6 tail); flight/route defaults onto MorphTheme.default*; showMorphRoute resolves MorphTheme.scrimMotion and accepts `modal`; route.dart launches via MorphScope.of(nav.context) (K4 route side). For WP-D: sheet.dart:111 and navigation_stack.dart:564 should use tryTagOf and degrade.
OWNER DECISION (A8): engine flights clamp size/shape at the target past value 1 (only the centre overshoots), but the device context-menu fixture shows UIKit containers overshoot in size. Changing the pinned rule in morph_frame_test is the owner's call.

## Submenu calibration by film (42b53f7, 7c6f414, e5aa1ca, 0cc68ff)

- Menu submenu cards hand their header back to the row they came from, so the row no longer blinks out when a card closes; the source row hides behind the header while the card shows.
- Submenu cards are a translucent platter that blurs and brightens the list under it, with a top rim and an outside shadow. BREAKING: `MorphMenuStyle.submenuColor` is now a translucent tint, not an opaque fill; new `submenuRimColor` and `submenuShadowColor`.
- Closing the menu with a submenu open shrinks the open card with the drop, unblurred and centred, fading near the end; a card row closes the menu 0.015 s after the lift.
- New `MorphMenuTuning` fields: submenuCloseDelay, cardRowsFadeIn, cardRowsFadeOut, cardPlatterFade, cardHeaderBoldStart, cardHeaderBoldEnd, cardChevronTurn, cardChevronBack, cardCloseFadeEnd, cardCloseCenter, cardBlur, cardGone. New `MorphMenuCard` fields: contentTop, rowsOpacity, platterOpacity, headerBold, chevronTurn, closeOpacity, backing, source.

Left (passport): dark film unusable (recorder dropped frames; dark judged from stills), close drop starts from the whole menu instead of the list under the card, native shows no row tap highlight in these films (ours highlights), chevron turn/bold switch eyeballed, header chevron slightly large.

## Codex packages (5f4ab8e WP-A, ffc0c1e WP-I, fa0df3c WP-D, d84e125 WP-G)

WP-A engine routes and flights:
- Fix morph route teardown (a route removed without a pop reveals its source and retires its flight), declined dismissal history, and dead-overlay cleanup.
- Add themed route scrims (MorphTheme.scrimMotion), non-modal routes, explicit overlays, and source-page scope resolution.
- BREAKING: flight geometry is read-only and MorphFlight.launch is internal.
- The skin listens to MorphFlight.geometryTicks, so scrim-only ticks no longer repaint it; less shuttle subscription churn.

WP-I glass renderer:
- Detect liquid shader support at runtime and fall back to frosted glass with a cached diagnostic; a failed shader bundle load is remembered.
- Share backdrop captures across adaptive glass and frosted surfaces.
- The adaptive tier governor has a warm-up period.
- Lifted-lens content copies paint from one mounted subtree (GlobalKeys and focus preserved).
- GPU shaders ship as one optional data asset for clean consumer builds (toolchains without Dart data assets get frosted glass).
- Unused upstream renderer code removed; fewer field uploads and glow shader allocations.

WP-D sheets, zoom, alerts:
- Fixed: Escape dismisses dismissible sheets; Android back on an alert runs cancel once; routes pop themselves during overlapping presentations.
- BREAKING: sheet and navigation zoom routes take source ids; missing sources degrade, removed sources dissolve.
- Fixed RTL zoom radii, popover placement, alert text-field Return and sheet detent notifications; one motion-route mixin and one zoom source.

WP-G other controls:
- Fixed scrolling gestures (the date label no longer opens from a scroll), rejected control values (controlled semantics) and invalid page inputs.
- One style resolution and capsule painter; glass glow integration consolidated.
- Control localization callbacks; date picker wheels and bounds synchronized.
- No per-tick layout work.
Left: D2 style forwarders in lens-family files (WP-F).

Verified by the coordinator on the combined tree: format 0, analyze 0, 966 package + 11 example tests, dart doc 0, iOS release and web wasm build.
