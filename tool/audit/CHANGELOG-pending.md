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
