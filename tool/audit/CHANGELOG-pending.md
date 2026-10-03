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
