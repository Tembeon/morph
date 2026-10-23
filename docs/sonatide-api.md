# Sonatide consumer API

The public-only runnable example is `example/lib/consumer_api.dart`:
`cd example && flutter run -t lib/consumer_api.dart`. It illustrates the
migration seams without importing `lib/src`, copying a control or exposing
motion tunings. Add the application's font asset when using SourceCodePro;
the example deliberately does not bundle that font.

## Selection and preview

`MorphSegment.custom(semanticLabel:, child:, builder:)` retains a child and
builds at input edges. `MorphControlState` reports selected, active, pressed,
keyboard-highlighted focus, hover and enabled flags. Custom content receives
one semantic button; its descendants are excluded. A fixed `width` sizes
non-text content; proportional/natural sizing otherwise measures the semantic
label with both appearance styles.

`onChanged` still reports only changes. `onActivated` reports every committed
activation, including re-taps: a reaction panel can set `selectedIndex` to
null on the second activation. Either callback enables the control. Use
`onActivated` instead of `onChanged` when it owns selection.

`onPreviewChanged` reports the selectable index under the finger, then null
on release or cancellation. `onPreviewCancelled` distinguishes cancellation
from commit. Preview does not select; segments still select on release,
whereas tabs select on contact. Arrow keys skip disabled segments; activation
and semantics also reach `onActivated`.

A custom `track` replaces only the track fill. With glass it owns a backdrop
group so the lens samples the custom track after it is painted. `lensColorAt` receives a
fractional logical segment index, independent of RTL; interpolate color stops
there without rebuilding the track or labels for lens frames. The measured
lift still fades the tint into the lifted material. Neither changes physics.

## Tab glyph ownership

`MorphTabItem.custom(glyph:, replicaBuilder:, label:)` mounts the primary
glyph once, in the expanded ordinary row. It may own a GlobalKey, FocusNode,
controller or OverlayPortal. The selected mask and minimized representations
call `replicaBuilder(context, selected:, minimized:)` for independent visual
copies. Each copy owns its own local state and cannot receive pointer or focus input. Never return the primary widget
or share its keys, focus nodes, portals or mutable controllers between copies.
Share read-only animation listenables if all copies need the same animation.
Returned glyph widgets inherit `IconTheme`; read its tint in the glyph's
own build method rather than in the replica factory's source context.

The primary stays mounted while clipped under the lens. The bar does not
make a raster snapshot, so animations remain live. Builders run at structural
changes, not on lens frames. The existing short IconData constructor remains.
`semanticLabel` overrides the tab name and `semanticValue` carries localized
unread/new information; descendant and badge semantics do not duplicate them.
The minimized representation carries the same label/value.

## Arbitrary touch targets

`MorphTouchTarget` owns input. Place `MorphTouchFeedback(shape:, child:)`
inside it to decorate an arbitrary shape. The decorator is passive: no second
recognizer, focus stop or haptic. Omit it for app-owned visuals, or use the
read-only `builder` flags. Its child is visual content, not an independently
interactive button. Install one decorator per target.

`minSize` defaults to 48 × 48; set 40 × 40 for the app's compact density. It
changes only the hit box, keeping the painted content at its own size. Press
and flex use the measured glass-button profile and 70-point release slop.
Scroll ownership, primary-pointer tracking, drag exit/re-entry, platform
cancellation, disable and disposal go through the existing shared press host.
An optional hold uses Flutter's standard long-press timeout and suppresses
the release tap. Space, Enter and accessibility tap share one activation.
Caller-owned `focusNode` and `autofocus` work with the enclosing focus scope.
The target adds no haptic; the application owns its action feedback.

The decorator adds no glass or backdrop sampling. Its liquid appearance is
an explicitly documented approximation of the native color-matrix wash and
spot on arbitrary app paint; timing and flex use the native measured motion.
Flat uses a uniform highlight because built-in flat glass has no touch glow.
`highlightColor` supplies the application's palette. Existing glass controls
keep their own renderer's exact feedback and should be used directly.

## Shells, fonts and menus

`MorphMenuSource` without `color` returns to its original surface-less
content: the menu platter fades out with the existing look crossfade, so
a plain label does not briefly become a glass button while closing.
Sources that declare their own `color` retain the surface hand-off.
The carried look retains the measured source box, including its original
content alignment, rather than centering a shrink-wrapped copy of a label.
For arbitrary app content, the platter fade uses the existing measured
look timing as an approximation of the native preview return. The whole
source scales together; the extra horizontal glyph stretch stays on the
button path.

Wrap a custom chrome-over-navigator shell in `MorphPresentationBoundary`.
Presenters then use the overlay/navigator outside the outermost boundary.
An explicit `overlay` still wins, including on `MorphContextMenuRegion`.
The caller does not need to adopt `MorphNavigationStack`.

`MorphThemeData.fontFamily` explicitly styles built-in text. Sizes and weights
retain native roles. An appearance's explicit family wins. `textStyle` and
`selectedTextStyle` on the tab appearance apply to expanded and minimized
labels. Existing segment/menu appearance styles remain the role overrides.
Widths and their caches include the resolved font and clamped text scale;
`DefaultTextStyle` is not a font configuration mechanism for built-in text.
`MorphSearchField.clearLabel` defaults to `MorphLocalizations.clearTextLabel`;
existing localization subclasses retain an English fallback until overridden.

`MorphMenuPresentationController` works with a menu source, menu button or
context-menu region. It attaches to one live source and exposes `open`,
`close`, read-only `isOpen` and `closed`. `isOpen` includes the closing
animation; `closed` completes after the presentation leaves the overlay,
including when the source is archived. Read `closed` from the current session.
Action callbacks still run when selected, before completed dismissal; an
async action can await `closed` before navigating. Dispose the controller
with its owner. Replacing a controller transfers observation of a live menu.

`menuBuilder` resolves entries when an opening is prepared, then on rebuild
while presented. Use it for current permissions/actions/optimistic values;
use ordinary `menu` for state already represented by a rebuild. Existing
`updateEntries`/deferred behavior remains; no second deferred cache is added.

The actual ChoiceMenuTile needs standard title/subtitle, icon and check
state, which `MorphMenuItem` already provides. Reaction accessories can use
`MorphSatellite.builder`, and fully custom rows use `MorphMenuWidget`.
Additional rich-title/trailing slots and composite navigation titles are
not required by these consumer examples and are not added mechanically.
Renderer persistence remains in Sonatide. A reactive tier diagnostic and
stable tab/segment IDs remain optional follow-ups; owners still map their
stable app values to the index API when reordering/removing items.

## Verification

`test/sonatide_public_api_test.dart` uses only public Morph imports and covers
commit/preview/cancel, re-tap-to-deselect, primary glyph/portal identity,
minimization, no per-frame consumer-builder calls, touch bounds and scroll
arbitration, disable/unmount, holds, keyboard, menu refresh/completed close,
source archival, custom shell root/local overlay, RU/EN/RTL/text scale,
custom font and localized clear semantics. Existing replay tolerances and
native tuning constants are unchanged.

`example/integration_test/consumer_api_test.dart` captures flat/liquid states
and records actual shader availability in `tmp/sonatide-public-api/` on the
physical device. Host tests without Impeller exercise fallback only.
Pixel 6a frame-time/energy comparison and an owner's visual approval on
iPhone remain release gates for the new optional app-surface feedback.
