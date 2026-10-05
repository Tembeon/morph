# Changelog

Versions are git tags; pin one. Pre-1.0, minor versions may break API.

## 0.7.0 - 2026-10-04

The widget layer becomes the measured one. morph always meant to move
like iOS Liquid Glass; the controls measured from UIKit on iOS 27 -
every spring read from the platform's tuning or fitted to
frame-by-frame recordings of the real controls, and replayed against
those recordings in the tests - now ARE `package:morph/widgets.dart`,
and every hand-tuned physics recipe they supersede is gone. The engine
moves on UIKit's measured liquid morph too. BREAKING throughout; the removed
implementations stay reachable at the v0.1.0 - v0.4.0 tags (0.5.0 and
0.6.0 were never tagged).

- Weak devices spend less of the UI thread on glass, with identical
  pixels (Pixel 6a): a menu's fused outline takes half the time (menu
  build p95 flat 14.0 -> 11.6 ms, liquid 19.0 -> 14.8 ms), a morphing
  body's field is copied by its own geometry pass into reused textures
  instead of a submission per frame, and resting glass layers are
  retained in the scene (16 resting buttons: compositing 2.5 -> 1.2 ms).
- The glass tiers are flat, fake and liquid; the frosted tier is gone
  (owner decision). Fake glass draws the liquid layers without
  refraction - the liquid face as a backdrop color filter over its frost,
  the rim, bevel and highlight drawn along each shape, a fused body
  clipped to its outline with one face per region - and needs no Flutter
  GPU, so liquid draws it before shaders are ready or when they fail, and
  the web draws it. It is the closest look to liquid (iPhone 16 Pro audit
  shots: median mean difference 0.64 against frosted's 1.73 and flat's
  1.39) but costs about what liquid costs, so `cheapTier` stays flat.
- The glass tier is chosen once and never switches while the app runs
  (owner decision): `MorphAdaptiveGlass` draws the tier given, else
  picks one at startup from the GPU class Flutter GPU reports
  (`MorphGlassDeviceClass`, `MorphAdaptiveGlass.deviceClass`): liquid on
  Vulkan or Metal, `MorphAdaptiveGlass.cheapTier` (flat) on Impeller's
  OpenGL ES fallback (no framebuffer mipmaps) and on Apple GPUs before
  the A13 (no HDR ASTC). On a Pixel 6a forced to GLES liquid put 3 - 9x
  as many frames over the 60 Hz budget as on Vulkan, frosted more
  still, so flat is the cheap tier. The frame-timing governor is gone:
  on the Pixel it flipped flat and liquid six times in one audit. Call
  `MorphGlassRenderer.precache` before `runApp` so the first frame
  already draws the chosen tier.
- `MorphGlassRenderer.precache` warms the pipelines, so the first glass
  frame compiles nothing: it draws each Flutter GPU geometry pipeline
  once and rasterizes an offscreen scene with every glass filter, clip
  and blur the liquid and frosted tiers use. On a Pixel 6a the first
  liquid frame drops from 102 - 131 ms of UI thread and 49 - 74 ms of
  raster to 5 and 11 ms, frosted's first raster from 64 - 73 to 19 -
  25 ms; precache now takes 0.3 - 0.45 s instead of 3 ms, so call it
  behind the splash, before `runApp`.
- Fixed: the app could hang at launch, Not Responding (seen on macOS).
  A frame with about 62 glass layers held that many geometry passes
  unsubmitted, and Metal's command queue holds 64: the next pass blocked
  the UI thread forever. Passes are now submitted every 16, a failed one
  no longer strands the rest, and `MorphGlassRenderer.precache` holds a
  launch at most 1 s, finishing the warm-up in the background past it.
- Fixed: on Impeller's OpenGL ES backend the launch crashed before the
  first frame (the warm-up's offscreen snapshot); pipelines are now
  warmed only on GPUs that draw liquid.
- Performance, pixels changed below what the eye sees (owner decision):
  an outline fused at spacing 0 - the menu's settle tail once its fusion
  radius is under 1 pt, every submenu card - is the exact union of its
  rounded boxes instead of a traced and uploaded field (menu build p95
  liquid 2.3 -> 1.9 ms, frosted 3.4 -> 1.9 ms on an iPhone 16 Pro); glass
  shadows clip to outside the glass instead of an offscreen layer per
  shadowed surface (liquid raster p95 0.2 - 0.5 ms lower; only the cut's
  antialiasing differs). Measured and not adopted: the scroll edge effect in the bars'
  backdrop group (the capsules would lose its fade).
- Touches land on the motion clock where the measured delays expect them
  (a fix): a pointer event is stamped at its own time stamp, moved onto
  the frame clock (on iOS and macOS the two clocks differ by the device's
  sleep, read from the system clocks). Every measured delay runs from
  the touch's time stamp, so stamping at delivery started each reaction
  10 - 25 ms late. While a control dozes between frames an event no
  longer takes the clock of the frame before the doze, and after a sleep
  the first frame counts from the touch.
- A context menu's lifted hero and its satellites, and a lifted lens,
  knob or thumb on the frosted tier, read what lies under them (a fix):
  with resting glass painted earlier on the page they showed a stale
  copy of the page (the hero without the dimmed content under it, the
  frosted lens without its track).
- Performance, same pixels and same motion: animating controls (tab bar,
  glass button, stepper, page control, progress view, spinner) paint
  inside their own repaint boundary; a liquid layer's content repaints
  only while a lifted lens copies it; the spinner's ticker dozes between
  its 20 Hz images (frames per second while one spins ~120 -> ~22); the
  search capsule no longer rebuilds its glass per press frame; springs
  answer a repeated time from memory; fused outlines moved by one offset
  are reused; the liquid renderer writes uniforms only to its bound
  shader and does not re-upload a field it holds; the menu's plain-union
  field no longer carries NaN at spacing 0 (a fix). New harnesses:
  test/perf_counts_test.dart pins per-frame work counts as ceilings,
  tool/ios_reference/perf/ runs and diffs the device audit.
- Performance, same pixels: a control rebuilt by its parent with an
  unchanged configuration rebuilds nothing below it (switch, slider,
  stepper, glass button, segmented control; device build p95 of a page
  of controls 2.4 -> 1.7 ms flat, 3.1 -> 2.3 ms liquid); a menu sleeps
  under a resting finger once its glow has faded in (within the rest
  tolerances every settled motion already uses); the menu button's
  hidden resting face is not rebuilt during its flight; the menu's
  plain-union silhouette takes its field from the box distances it
  already has and container fusion keeps its grids across calls (union
  0.73 -> 0.49 ms, old-generation GC during menu opens 10 -> 2).
- Performance, same pixels: a moving glass surface rebuilds no widget.
  Every control hands its surfaces to the painter through a glass host
  that builds its tree once per structure and pushes each later frame
  straight into the render objects (positions, clips, filters, paints,
  the liquid renderer's shapes and layers); a custom `MorphGlassPainter`
  is still asked every frame. Component builds per animated frame drop
  (liquid segmented control 11.6 -> 1.3, tab bar 23.7 -> 2.6, 16 glass
  buttons pressed in a wave 199 -> 31); on an iPhone 16 Pro the liquid
  build p50 of a moving control falls 0.05 - 0.1 ms, since the liquid
  tier's UI time is mostly the renderer's paint. New harnesses: the
  glass density audit (N glass buttons over a scrolling page), the
  per-phase UI timings on the device, and a frame-by-frame pixel
  comparison of the channel against a rebuild of every glass layer.
- Glass that floats over the page reads what lies under it (a fix): the
  navigation bar and toolbar share a backdrop group of their own per
  screen, the search tab bar and a sheet's content get their own, and bar
  and menu glass never shares the page's group on the liquid or frosted
  tier. Impeller reads a shared group's backdrop once, so the bars on a
  page with a resting glass button missed the scroll edge effect under
  them, and a floating sheet read a stale dark copy instead of the page.
- Presentations from a navigation stack's page cover the stack's bars, as
  on iOS: `MorphNavigationStack` installs a new `MorphPresentationBoundary`,
  and `showMorph*`, `MorphAnchor`, `MorphMenuButton`,
  `MorphContextMenuRegion`, bar menus and `presentMorphSheet` default to
  the overlay / navigator around the outermost boundary
  (`morphPresentationOverlayOf`, `morphPresentationNavigatorOf`);
  `morphAnchorRect` measures in the same overlay. An explicit `overlay:`
  or `useRootNavigator:` still wins. BREAKING: `presentMorphSheet`'s
  `useRootNavigator` is nullable (null = the presentation navigator,
  false = the nearest one).
- A `MorphBarButton` with a `menu` and no `onPressed` opens the menu on a
  tap, as a `UIBarButtonItem(menu:)` without a primary action, measured
  on the iPhone 16 Pro: release-to-open 0.013 s after the inline menu
  button (`MorphBarMenuTuning.measuredMenu`, the new default `menu`), a
  0.22 s hold opens under the finger, a slide chooses a row. BREAKING:
  `MorphBarButton.enabled` is a constructor parameter (UIKit's `isEnabled`); the
  computed tap acceptance is `interactive`.
- A finger that opened a menu by holding chooses nothing when released
  without having left the button; the menu stays open (UIKit, inline and
  bar, device holds).
- The navigation bar never draws an inline title that arrives hidden with
  its screen: a large-title screen faded its inline title out over a
  second at launch and after every pop back to it.
- The bars change side by side on a push or a pop, as UIKit does (a fix):
  a back button pushed onto a page without leading items no longer grows
  out of the trailing group and flies across the bar fused with it, nor
  flies back on the pop. Leading groups change only into leading ones,
  trailing into trailing; a side that had no group shows its groups in
  place (swollen, transparent, blurred, settling on the transition
  spring) and a side left empty lets them swell and fade where they
  stand, in a glass container of their own - measured on an iPhone 16
  Pro (spec/bars.md, scene navseg). Adds `MorphBarCapsuleLayout.segment`,
  `MorphBarCapsuleFrame.segment` / `opacity` / `apart`,
  `MorphBarTransitionSpec.segmentDelay` and
  `MorphBarTransitionSpec.navigation` (a push starts its frames 0.062 s
  after the call).
- One law places every bar capsule that comes or goes, as UIKit does (a
  fix): a group born beside a group of its side that stays grows out of
  that survivor - its own box fitted inside the survivor's, at a fifth -
  and a group that goes shrinks into the survivor and vanishes inside it,
  instead of growing from and dying onto the survivor's facing edge (the
  gallery's [plus more] no longer sticks to [1x] as a fused nub after a
  pop). A toolbar shows a group larger than its survivor in place. Groups
  without an id continue the nearest group of their side. Measured on an
  iPhone 16 Pro (spec/bars.md, scene navseg set b). Adds
  `MorphBarCapsuleLayout.anonymous` and
  `MorphBarTransitionSpec.oversizedInPlace`.
- The scroll edge effect fades its blur with it (a fix): a fade under an
  Opacity read an empty backdrop, so the page showed sharp under the
  navigation bar while the effect faded - after a pop to a scrolled page
  most visibly. Adds `MorphScrollEdgeEffect.opacity`; a fade rebuilds
  nothing.
- Adds inset grouped lists: `MorphListSection` (header, card, footer)
  and `MorphListRow` (title, subtitle, value detail, leading symbol,
  trailing control, disclosure chevron, custom content, tap highlight,
  keyboard activation, RTL), with `MorphListStyle` light/dark tables and
  `MorphListMetrics`, all read from iOS 27's inset grouped UITableView
  (spec/lists.md).
- Adds `MorphWidgetsTheme.list`, the ambient `MorphListStyle`.
- Adds `MorphTypography.body`, `listSubtitle`, `listHeader` and
  `listFooter`, the measured list cell and section label roles.
- `MorphNavigationScaffold` gives its content UIKit's body text style in
  the bar style's label color, so plain text on a page needs no Material.
- Adds `MorphSheetStyle.textColor`: sheet content reads in the body text
  style, label colored.
- The example gallery runs entirely on `MorphNavigationStack`,
  `MorphNavigationScaffold` and the list widgets: no Scaffold, AppBar,
  ListTile or MaterialPageRoute remain in it.
- Adds a shared native/Flutter measurement laboratory with real XCUITest
  input, timestamped films from one buffer stream, layer/render-tree
  telemetry, regional glass metrics, gesture replay, spring fitting and
  interactive reports with provenance and capture-validity checks. Menu
  audits retain global drift alongside received-touch inspection windows,
  verify platform footer content and measure face, rim and shadow separately.
- Submenu headers keep their source-row columns through hand-back; stacked
  cards retain full platters, rims and shadows, with the measured 0.97
  parent glass scale. Regression frames cap the horizontal hand-off step
  at 0.5 pt; the root platter replays native device bounds at 0.014 pt RMS.
  Closing stacks use UIKit's independent 0.35/0.85 container spring,
  with the deeper-card anchor scaled by 0.97 and no submenu tap flash;
  visible closing bounds replay at 0.055 pt RMS after clock alignment.
  The button and menu share one distance field and exterior shadow,
  removing the separate circular button rim during open and close.
  Submenus now use the installed liquid renderer, fresh backdrop groups
  and measured 10 pt frost; neutral tint and calibrated transmission keep
  nested edges and face levels consistent with native glass. Closing card
  material hands off at the native 12 ms SDF match, removing the inner
  rectangular platter and blurred parent-row ghosts.
  Scrolled parent menus retain their offset when a submenu opens or
  returns; parent drag, wheel and ballistic scrolling stay locked until
  the last submenu has returned.
  Taps on the exposed parent return one level without unlocking scrolling;
  outside taps dismiss the whole stack, including after a blocked drag.
- Menus draw with the glass painter of their button even when the
  `MorphGlass` sits below the Navigator whose overlay carries the menu;
  before, such menus fell back to flat platters without the Liquid Glass
  contour. Closing submenu cards keep UIKit's copied card material on its
  carrier, and cards cast the measured light shadow through the new
  `MorphGlassSurface.shadows`. The menu glass now starts its close together
  with the card container, as on the device (outside 0.059 s, card row
  0.031 s after the release), so a closing submenu folds into one body;
  a tap opens the menu 0.089 s after its release, the recorded mean.
- Alerts, action sheets, sheets (and their content), the date picker
  overlay, context menu flights and the source replica of a sheet or push
  zoom draw with the glass painter above the control that presented them,
  as menus do; before, a `MorphGlass` below the Navigator left them on the
  flat fallback.
- Engine flights (`showMorph*`, `showMorphDialog` / `Sheet`,
  `showMorphRoute`, `MorphAnchor`) carry the inherited themes of their
  source tag, as Flutter's popup routes carry those of the context that
  showed them: the source ghost, the surface and the target content draw
  under the source's `Theme`, `DefaultTextStyle`, `IconTheme` and glass
  painter (`MorphGlass` is now an `InheritedTheme`), on the shuttle and
  on the settled route page, and follow a change at the source such as a
  `MorphAdaptiveGlass` tier switch. Before, a `MorphGlass` or a `Theme`
  inside a page was invisible to the flight, so a `MorphGlassButton`
  used as a `MorphTag` source flew on the flat fallback. Alerts, sheets
  and the date picker now carry all of the presenter's inherited themes
  too, not only its glass painter.
- Liquid glass initialization failures report once per isolate through
  `FlutterError.reportError` in every build mode (library `morph glass`);
  `MorphGlassRenderer.liquidUnavailableReason` exposes the cached cause.
- Bar menus accept an instance `MorphBarMenuTuning` through `menuTuning` on
  `MorphNavigationStack`, `MorphNavigationBar` and `MorphToolbar`, including
  recognition, opening delay and `MorphMenuTuning`; measured defaults stay
  unchanged. BREAKING: `recognition` and `open` are instance fields.
- The measured controls: `MorphSegmentedControl` (+
  `MorphSegmentedStyle`) and `MorphTabBar` (+ `MorphTabItem`,
  `MorphTabBarStyle`) - one liquid selection lens on
  `MorphLensMotion`/`MorphLensTuning`, the segmented control selecting
  on release, the tab bar on contact with the whole bar swelling while
  pressed; `MorphSwitch` and `MorphSlider` on the small lens
  (`MorphSmallLens`, `MorphSwitchMotion`, `MorphSliderMotion`);
  `MorphStepper`; `MorphGlassButton` (+ `MorphGlassButtonMotion`) - a
  uniform lift of `1 + lift / width` whose lift and springs come from
  `MorphFlexSpec.forSize`, a lean after a finger that drags off, the
  touch glow; `MorphMenuButton` (+ `MorphMenuItem`, `MorphMenuStyle`,
  `MorphMenuMotion`, `MorphMenuTuning`, `MorphMenuBlob`) - a round
  glass button that becomes its own menu on UIKit's `liquidMorph`
  tuning (`MorphMenuMorphSpec`), opening on a tap's release or under a
  hold that slides onto a row. `MorphSpring` is UIKit's spring
  vocabulary (response, damping ratio), convertible to a motor
  `Motion`. The motion objects are pure functions of explicit time and
  work without their widgets.
- BREAKING: `package:morph/native.dart` is gone - the layer it held is
  `package:morph/widgets.dart` now, and every `MorphNative*` name lost
  its infix (`MorphNativeTabBar` -> `MorphTabBar`, `MorphNativeSpring`
  -> `MorphSpring`, ...); `MorphNativeMorphSpec` is
  `MorphMenuMorphSpec`.
- BREAKING: removed `Tug`, `MorphPillHost`, `MorphSquash`,
  `SpringButton`, `ChaseSpring`, `morphPressGrowth`, and the popover
  menu `showMorphMenu` with its `MorphMenuItem` - the name now belongs
  to `MorphMenuButton`'s rows (`title`, `icon`, `destructive`,
  `onSelected`). Their replacements are the measured controls above:
  `MorphGlassButton` for presses, `MorphTabBar` and
  `MorphSegmentedControl` for selection pills, `MorphMenuButton` for a
  button that becomes its menu.
- BREAKING: `MorphContextMenuRegion.pressGrow` is replaced by `lifts`.
  The held hero lifts the way a glass button does - a uniform scale by
  `MorphFlexSpec.forSize` for its size, the press on the tracking
  spring, the release on the scale spring - instead of on the Tug
  spring's fixed pixel growth. Everything else about the region is
  unchanged.
- Example: the gallery is the example app. The tour of phone-mockup
  chapters, the playground sandbox and its lab chrome are removed (they
  stay at the v0.4.0 tag); `example/lib/main.dart` runs the measured
  gallery (`example/lib/gallery/`), one page per control, so a plain
  `flutter run` opens it. `--dart-define=MORPH_AUTODEMO=true` walks
  every gallery page with synthetic gestures and exits;
  `--dart-define=MORPH_BENCH=true` still runs the release bench, now on
  a card of its own. The web build draws frosted glass: the liquid tier
  sits behind a conditional import and its shaders compile to stubs
  there, so the web example builds as is.
- The glass seam: `MorphGlass(painter:)` installs a `MorphGlassPainter`
  whose `buildSurface` renders every glass surface of the controls below
  it - track, lens, knob, thumb, button, bar, menu (`MorphGlassKind`) -
  as a widget placed at the surface's bounds each frame, so a painter can
  sample the backdrop or run a shader; `buildLayer` receives all the
  surfaces of one control together with the content drawn over them
  (segment labels, tabs), so a painter can share one backdrop sample,
  fuse neighbors (a menu and its button) or show the content through a
  lens. `MorphGlassSurface` carries the
  deformed shape, the flat color as a tint, the brightness, the lift and
  the lens's `MorphGlassOptics` (UIKit's refraction values, `small` and
  `large`). Without a painter the controls draw their flat fills as
  before.
- Example: the gallery draws every control with the package's
  `MorphGlassRenderer` (see the renderer bullet below; it started as an
  example-only painter over a vendored copy of whynotmake-it's
  renderer), installed at the gallery root through
  `MorphAdaptiveGlass`. The Glass renderer page edits one session-wide
  settings model - tier (auto, liquid, frosted, flat), material preset,
  blur, refraction, rim light, tint, frost on controls, appearance,
  right to left, disabled - and every page follows at once. Resting
  lenses, knobs and thumbs stay opaque platters and turn into glass as
  they lift; a lifted lens magnifies what it covers by
  `1 + 0.16 * lift`. The iOS and macOS runners enable Impeller and
  Flutter GPU; the Pages workflow builds on Flutter 3.47.2.
- Theming: every control takes a `style` (`MorphSwitchStyle`,
  `MorphSliderStyle`, `MorphStepperStyle`, `MorphGlassButtonStyle`
  join `MorphSegmentedStyle` and `MorphTabBarStyle`), each with `light`
  and `dark` tables from the iOS system colors. Resolution is the
  explicit style, then the `MorphWidgetsTheme` ThemeExtension, then the
  table for the ambient brightness (the Theme's, else the platform's).
  BREAKING: the `style` parameters and the switch, slider and stepper
  color parameters are nullable now; an explicit color still wins over
  the style.
- Accessibility and keyboard: each segment is a selectable button in a
  mutually exclusive group; the tab bar carries the tab bar and tab
  roles; the switch and slider take a `semanticLabel`; the slider's
  adjust actions and arrow keys move it by `MorphSlider.keyboardStep`;
  the stepper reads as two buttons (`decrementLabel`,
  `incrementLabel`) carrying the value. Every control is focusable and
  draws a systemBlue focus ring; Space and Enter toggle the switch,
  press the glass button and increment the stepper, the arrow keys move
  the segmented and tab bar selections.
- Disabled: BREAKING: `onChanged` is nullable on `MorphSegmentedControl`
  and `MorphTabBar`. A disabled control ignores input and draws the
  disabled look measured on an iPhone 16 Pro (iOS 27.0.1, light and
  dark), switching in one frame both ways. The segmented control, switch
  and slider fade to `disabledOpacity` 0.5 as one layer (the segmented
  control was 0.35). BREAKING: `disabledOpacity` is gone from
  `MorphStepperStyle`, `MorphPageControlStyle` and `MorphTabBarStyle` -
  UIKit draws a disabled stepper, page control or tab item unchanged; a
  touch on a disabled tab (new `MorphTabItem.enabled`; a null
  `onChanged` disables every tab) still swells the bar but neither
  selects nor moves the lens. BREAKING: it is gone from
  `MorphGlassButtonStyle` (new `disabledForegroundColor`, tertiaryLabel,
  and `disabledTintColor`, systemGray4 for a prominent button), from
  `MorphBarStyle` (new `disabledIconColor` and `disabledLabelColor`, the
  rendered colors of a disabled bar item's icon and text, and
  `disabledProminentColor`; a prominent glyph stays white), from
  `MorphSearchFieldStyle` (new `disabledFillColor`: a disabled field is a
  flat 0x767680 fill without glass, lift or focus), from
  `MorphAlertStyle` (new `disabledLabelColor`: a disabled action keeps its
  fill and dims its title, destructive too; a disabled preferred action
  shows the plain fill and keeps its semibold title) and from
  `MorphDatePickerStyle` (disabled labels drop their capsule and keep
  their text; the out-of-range day opacity is `unavailableDayOpacity`).
  `MorphMenuButton.enabled` disables a menu button: its glyph turns
  `MorphMenuStyle.disabledIconColor` and its glass stays. The stepper
  takes the device colors (half fill 0x163C3C43 light / 0x14EBEBF5 dark,
  a 1 x 24 tertiaryLabel divider, a pressed half that replaces its fill
  by black 8 percent in dark and darkens it in light) and draws the glyph
  of a half at its limit in `limitForegroundColor`, tertiaryLabel. The
  light menu and date picker overlay share the material 0xF2F9F9FF (249,
  249, 255 over the grouped background, as UIKit's).
- The menu API, measured on the iPhone 16 Pro (iOS 27.0.1): BREAKING
  `MorphMenuButton.items` (and `MorphBarButton.menu`) take sealed
  `MorphMenuEntry` values - `MorphMenuItem` (new `subtitle`,
  `selectedIcon`, `iconColor`, `iconVisibility`, `enabled`, `hidden`,
  `keepsMenuOpen`, `state` on / off / mixed, `onHighlightChanged`),
  `MorphMenuSection` (header, `singleSelection`, `palette`, small and
  medium `elementSize` cells, `maxTitleLines`), `MorphSubmenu`,
  `MorphMenuDivider`, `MorphMenuDeferred` (a "Loading..." row with a
  spinner until it answers, cached or not) and `MorphMenuWidget`, morph's
  own free-form row with no UIKit twin. `MorphMenuItem` moved to
  menu_entries.dart (same name and fields, still exported). The layout is
  the device's view tree (`MorphMenuMetrics`, `MorphMenuLayout`): 250
  wide, rows 42 / 60 with a subtitle, glyph and selection columns, 40.33
  headers, 21 pt group gaps with an inset hairline, palette, small and
  medium cells; content past 520 pt or the safe area scrolls inside the
  menu, and a finger that scrolls chooses nothing. Colors per appearance
  (titles 0.96, secondary 0.6, disabled 0.298, destructive 0xFF4245 /
  0xFF383C); BREAKING `MorphMenuStyle.rowPadding` is gone (new
  `secondaryColor`, `disabledColor`, `separatorColor`, `submenuColor`,
  `paletteSelectionColor`). Submenus open as cards stacked over the menu:
  a card grows out of its row on 0.395 / 0.86 (0.076 s after the
  release; deeper cards 0.405 / 0.84 after 0.04 s), the cards below
  shrink to 0.97 and dim their rows to half, the menu grows to cover the
  card; its bold header with a chevron goes back on a critically damped
  0.4 s spring, and a held finger opens a submenu after resting 0.525 s
  on its row. Choosing a row of a card closes the whole menu on the
  ordinary menu close (the device's container close is the same frame by
  frame as a plain menu's). The open menu follows its widget like a
  SwiftUI menu: a rebuild with other entries updates it in place and
  resizes it on 0.565 / 0.84 (grow) or 0.4 / 1.0 (shrink).
  `MorphMenuButton.order` (`MorphMenuOrder`; fixed keeps the order in a
  menu that opens upward) and `dismissOnSelect`. Keyboard: arrows,
  Enter / Space, the forward arrow into a submenu, Esc back out and then
  closed; rows are buttons with checked, mixed and expanded states. An
  `overlay:` that is not an ancestor of the button now throws instead of
  measuring garbage. Replayed by menu_api_test (layout from the dumps,
  card springs, dwell, resize) and pinned by menu_entries_test.
- Right to left: the segmented control, tab bar, switch and slider
  mirror in an RTL context; the stepper keeps minus on the left.
- Text scale: segment labels follow the text scale up to 1.4 and size
  by the wider of their two styles; tab labels follow it up to 1.25 and
  the tabs widen to fit the widest label.
- Reduced motion: `reducedMotion` on `MorphLensMotion`,
  `MorphSmallLens` and `MorphGlassButtonMotion`, set by the widgets
  from `MediaQuery.disableAnimations`: the lens and the knob travel, the
  button glows, but nothing lifts, deforms, leans or swells. An
  approximation until Reduce Motion is recorded on a device; off by
  default, so the fixture replays are unchanged.
- BREAKING: the engine's motion is measured. `MorphMotion.liquid` -
  UIKit's liquid morph progress spring, open `MorphSpring(0.35, 0.75)`,
  close `MorphSpring(0.49, 0.80)` - is the default everywhere a motion
  resolves (`MorphController`, `showMorph*`, `MorphTheme` unset). The
  open now overshoots slightly (about 3 percent), as UIKit's does; the
  close still dips below zero for the handoff latch. Removed the
  hand-tuned presets `MorphMotion.slow`, `normal`, `glass` and `fast`;
  `glacial` is now `liquid` with every response times five (a magnifier
  for the eye) and `instant` keeps its reduced-motion contract.
  Removed `MorphMotion.values`, `MorphDirection` and
  `MorphController.direction`.
  `MorphMotion.springs(open:, close:)` builds a profile from
  `MorphSpring`s and exposes them as `openSpring`/`closeSpring`;
  `openMotion`/`closeMotion` are getters now. The public constructor
  for custom profiles stays.
- BREAKING: `MorphSpring` lives in the engine
  (`package:morph/foundation.dart`; `widgets.dart` still re-exports it).
- BREAKING: the landing bump is gone - UIKit's landing is the close
  spring's own undershoot, nothing added on top. Removed
  `MorphTag.bumpScale`/`bumpRecoil` and the squash-and-recoil transform
  the tag played after the handoff latch, `MorphTheme.bumpScale`/
  `bumpRecoil`, `morphLandingBump`, `morphBumpedRect`,
  `MorphFlight.impactAxis`, `MorphMotion.closeVelocityHint` and
  `morphCloseHintScale` (a close from rest now starts still). The
  handoff latch itself is unchanged: the shuttle still hands the surface
  back on the close spring's first zero crossing, and
  `MorphFlight.isLanding` still marks the span between the latch and
  the final rest.
- `MorphTargetSpec.vessel(rectFor:, repaint:)`: a target whose content
  draws the whole morph itself - laid out over the entire overlay in
  overlay coordinates, at full opacity, no surface, shadow, source ghost
  or crossfade, taking pointers while the flight is open or opening -
  with everything else a flight provides (overlay choice, modal barrier,
  pop layering, focus trap, events, source-lost dissolve). The scrim's
  dismiss label no longer requires `MaterialLocalizations`.
- BREAKING: `MorphMenuButton` flies on the engine: its menu is a
  `MorphFlight` on a vessel target with the measured progress spring,
  the scrim at zero opacity, so the overlay choice, Esc and back, focus,
  `MorphFlight.events` (`onOpen:` hands out each flight) and the
  dissolve of a removed button come from the engine; its own overlay
  entry, history entry and clock are gone. It uses an ambient
  `MorphScope` or brings its own. The menu is hit-testable from its
  first frame and places itself clear of the keyboard.
  `MorphMenuMotion` reads its progress from a `MorphMenuProgress`
  (`MorphMenuProgress.spring` for a pure function of time). The kicks
  are no longer replayed from recorded tables: the menu shape's kick is
  a spring driven by the progress spring's velocity while opening and
  struck by the close (`openKickSpring`/`openKickGain`,
  `closeKickSpring`/`closeKickImpulse`/`closeKickDelay`/
  `closeKickReach` on `MorphMenuTuning`), the button shape's kick a
  spring driven by the closing velocity (`sourceKickSpring`/
  `sourceKickGain`), with per-height amplitudes; removed
  `MorphMenuTuning.kickHandoff`.
- The tab bar's scrub is measured (recaptured on an iPhone 16 Pro, iOS
  27.0.1). A press on the selected tab lifts it `pressDelay` after the
  touch (50 ms; the segmented control's 40 ms). The lens then follows
  the finger's travel since the touch times `MorphLensTuning.dragGain`
  (1.013 for the tab bar, 1 for the segmented control) on the follow
  spring `MorphSpring(0.271, 0.803)` (was 0.196/0.903), and past the
  first and last tabs it meets a tight rubber band (4.55 px, stiffness
  0.95) instead of a clamp. The 1.055 - 1.064 gain the recording shows
  on screen is that gain times the bar's own press swell, which scales
  the lens around the bar's center. The release picks the tab nearest
  the finger; the travel there and the landing start `releaseDelay`
  (30 ms) after the touch-up, the travel on the tab travel spring
  carrying the scrub's velocity, which also accounts for the short
  return from a rubber band. BREAKING: `MorphLensTuning.rubberBand` is
  a required (limit, stiffness) record and `pressDelay` is required;
  `dragGain`, `pressHang` and `releaseDelay` are new.
- A tap on the already selected segment or tab lifts it in place after
  `pressDelay` and lands no earlier than `pressHang` (0.25 s) after the
  touch, or `releaseDelay` after the release of a longer hold. The tab
  bar lens that seems to drift outward while held is the bar's swell;
  the lens itself does not move.
- BREAKING: `MorphSwitch` decides a drag the way UIKit does: the drag
  commits when the knob's target reaches the far end and uncommits only
  when it returns to the starting end, the track color following each
  change after `MorphSwitchMotion.colorDelay` (90 ms); the release keeps
  the committed state if the drag ever committed and toggles like a tap
  otherwise. Crossing the middle no longer decides anything. The 5 px
  dead zone now applies only to a drag that starts moving within
  `deadZoneWindow` (0.1 s) of the touch; a finger held still that long
  drags the knob directly.
- BREAKING: `MorphSlider` glides on after a moving release as the
  device does: the value keeps the release speed for
  `MorphSliderMotion.glideCoast` (0.04 s), then the speed decays
  exponentially with `glideDecay` (0.083 s), stopping at the ends - a
  release at speed v travels 0.123 s times v further. Removed
  `glideSpring`, `glideDelay`, `flingTime` and `flingThreshold`. The
  widget still measures the release speed with Flutter's
  `VelocityTracker`.
- A tap on a `MorphMenuButton` while its menu closes re-opens the same
  morph on the touch-up, the progress reversing onto the open spring
  with its velocity. For that the scrim of a `MorphTargetSpec.vessel`
  takes pointers only while the flight is open or opening, like its
  content: a closing vessel lets touches through to the page.
- BREAKING: skin pieces land without a bump too: removed
  `MorphPiece.bumpScale`/`bumpRecoil` and the skin's landing squash of
  a piece's mass and content; a piece's content transform is its
  `MorphPieceChannel` alone. The debug assert that a manual `MorphTag`
  inside a piece zero its own bump went with it.
- BREAKING: removed `MorphReveal`, the staggered unfolding of content
  blocks on sub-ranges of the flight's spring. Flight content arrives
  with the surface, as UIKit's does; `MorphContextMenuRegion`'s
  satellites no longer unfold separately.
- BREAKING: removed the surface adapters `MorphSurface` (Material plus
  InkWell rendered from `MorphTag.specOf`) and `MorphTapTarget`. Use
  `MorphGlassButton` for a button that is a morph source, or render the
  surface from `MorphTag.specOf` with your own design system and a
  `GestureDetector`; the `MorphTag.specOf` contract is unchanged.
- BREAKING: `MorphSlider` begins a drag after
  `MorphSliderMotion.panSlop` = 11 pt (was 10), fitted to the slow
  drags recorded on an iPhone 16 Pro and in the simulator; the drag still maps the finger onto the
  value by the full track width, which the recordings confirm (fitted
  divisor 298 - 302 pt for a 300 pt track, 199 - 200 for 200). The
  extra thumb lag the device showed was the later start, not a smaller
  gain.
- Example: the opening scene keeps its Motion and Interrupt layers (the
  Landing layer is gone) and its compose button is a `MorphGlassButton`;
  the playground lost its landing and close-kick knobs; dialog, sheet,
  player and lesson-page content arrive without a cascade; chapter
  cards, album cards and the mini bar render their surfaces from their
  spec with a plain `GestureDetector`, the filter chips tap through one.
- BREAKING: the skin merges by the law iOS 27 Liquid Glass draws,
  measured on an iPhone 16 Pro (UIKit `UIGlassContainerEffect` and
  SwiftUI `GlassEffectContainer` agree). The smooth minimum's width at
  each point is `blend * (1 - dot(na, nb)) / 2`, where `na` and `nb` are
  the unit normals of the two surfaces: facing surfaces blend over the
  full width, edges running side by side not at all, so aligned tops
  and bottoms of fused pieces stay straight instead of lifting by a
  quarter of the blend. `blend` is the glass container's spacing, 1:1 in
  logical px: two facing surfaces lean toward each other below a gap of
  `blend` and touch at `blend / 2`. Replayed against the device's
  silhouettes (pairs of capsules and circles, spacing 10 - 80, gaps 40
  to -5 pt) the traced skin stays within 0.17 - 0.32 pt rms, the
  screenshots' own noise floor. Removed the presets
  `MorphSkinStyle.geometric` and `goo`: they were taste values with no
  measurement behind them. `MorphSkinStyle.subtle` (8) is SwiftUI's
  default spacing and is now the builtin a skin without a style or a
  theme falls back to (was blend 24). `MorphPieceChannel.birthScale`
  (0.2) and `birthSpring` (`MorphSpring(0.492, 0.711)`) are how a Liquid
  Glass shape is born and leaves, fitted to SwiftUI's `glassEffectID`;
  the living-layout chapter's chips are born and removed on them.
- The controls share a scroll view the way UIKit's do
  (`delaysContentTouches` with `touchesShouldCancel` false for a
  control). Every touch enters the gesture arena on contact and the
  control owns it once held for 150 ms, or, for the switch, slider,
  segmented control and tab bar, once it drags past the touch slop
  along the control's own horizontal axis - unless an enclosing
  scrollable runs along that axis too, where the delay alone decides.
  An owned touch stays the control's however it moves: a held glass
  button leans and can be dragged off without the list scrolling, a
  menu button's hold slides onto its rows, a stepper repeats. A quick
  swipe that the list wins first cancels the control's touch, and a
  slider drag taken over this way returns to the value it started from.
  The press feedback still starts on contact. `MorphContextMenuRegion`
  keeps its tap and long press and adds one claim: a press that stayed
  still for 150 ms and then wanders is no longer taken by the list.
  Disabled controls leave their touches to the gestures around them.
- BEHAVIOR: `MorphTabBar` inside a scrollable hears a touch only once
  the touch is its own - held for 150 ms, dragged along the bar past
  the touch slop where the list scrolls the other way, or lifted - as
  UIKit holds back every touch from a scroll view's content
  (`delaysContentTouches`). Nothing moves before that, the press
  feedback included, so a quick swipe that starts on another tab
  scrolls the list without switching tabs (it used to select on the
  touch-down and switch before the list took the touch). A floating bar
  outside any scrollable still selects on contact.
- `MorphMenuButton`: a touch that lands while a tap's menu is still on
  its way (between the release and the opening) belongs to the menu, as
  on the device: a release outside the menu closes it again right after
  it starts to open (UIKit's menu reaches about p 0.17), a release on
  the spot of a row selects that row - a quick second tap on the button
  picks the first row of a menu that opens down - and a finger still
  down when the menu appears is the menu's. Before, nothing was on
  screen to hear that touch and the menu opened anyway. Measured on the
  iPhone 16 Pro with outside taps of 10 - 100 ms from the release: the
  close starts `MorphMenuTuning.earlyCloseDelay` (16 ms) after the
  opening whatever the release time, so the menu always peaks at about
  0.17; a row's action runs `actionDelay` after the opening (replayed
  from the touches of six device captures within 0.008 rms of
  progress). `MorphMenuMotion.isOpenPending`.
- The tab bar's "slow lift" (Codename One saw a slower lens growth on
  some 5-tab taps) is documented, not modelled: on the iPhone 16 Pro
  the lens SIZE lags its lift progress on every selection change from
  or to the third slot of a 4-tab bar, whatever the item, the tap's
  length or the history, and never on 2, 3 or 5 tabs; the slot depends
  on the bar's geometry in a way two screen widths do not determine.
- `MorphSlider` at its ends, measured on an iPhone 16 Pro (iOS 27.0.1)
  with 200 and 260 pt sliders dragged slowly, fast and from a thumb
  resting near or at an end, 40 - 80 pt past either end and back: the
  native thumb does not catch up with the finger. The value maps the
  finger by the full track width all the way, so it reaches an end with
  the finger leading the thumb by the slop plus 37 pt times the travel
  that was left (30 pt from the middle, 49 pt from the far end); only
  past that point does the track stretch, on the rubber band fitted in
  the simulator (13 pt, 0.74, within 0.35 pt on the device), and on the
  way back the value moves again where it reached the end, with no
  re-basing. The model already followed that law; the 13.5 pt slop it
  started from left its thumb 2.5 - 3 pt behind the device's through a
  slow drag, which the 11 pt slop closes (thumb within 0.4 - 1.9 pt rms
  of the recordings on slow drags, 3.4 on fast ones).
- `MorphMenuButton` traced on the iPhone 16 Pro (profile build, every
  frame's painted shapes and FrameTimings, against the recorded UIKit
  menu): the menu now draws from its own measured progress spring on the
  clock its kicks run on (it read the flight's controller, which starts a
  frame late at elapsed 0: the first menu frame was held at the button
  and the kick ran 8 - 17 ms ahead of the shape - open kick error vs
  UIKit 1.14 pt rms / 3.7 max, now 0.27 / 1.0), and the end of a close
  plays out on the button: the engine latch used to drop the menu at the
  close's zero crossing while the button shape was still kicked 4 pt
  off, a snap at the end of every close, where UIKit keeps its morph
  until the kicks ring out ~0.85 s later; the button now draws both
  shapes until the motion rests (its close ends when the progress and
  both kicks rest). The button's look blurs out as it fades (4 x
  progress, as UIKit's), the rows are built once per menu instead of
  every frame, the union is one path instead of a `Path.combine` per
  frame, and each crossfade draws through one layer; the resting button
  draws its glyph without a layer, so the glass of resting buttons stays
  in one backdrop group (an extra alpha-255 opacity layer per button
  cost a glass painter ~10 ms of raster per frame on the device).
- `MorphMenuButton` filmed against the native menu (screen recordings of
  the iPhone 16 Pro at 60 fps, both sides on the same light screen, the
  native side paired frame by frame with the probe's layer data): the
  ellipsis no longer rides the whole crossfade. It stays on the button
  shape, widens to 1 + 2.5 x progress while it blurs, and is gone by
  progress 0.42 - two to three frames into an open - and returns only
  as the close nears the button (`lookFadeStart`/`lookFadeEnd`,
  `lookStretch`); before, it faded over the whole progress and its blur
  sampled with a clamp tile mode, so a grey square of smeared glyph
  hung over the menu's top edge for most of every open and close (the
  blurs now use a decal tile mode). The menu content is no longer a
  miniature of the menu: it stays near its final size (`contentScale` =
  1 - 0.5 x (1 - progress) + 1.3 x kick / menu height), centered on the
  menu shape that reveals it, blurs on screen by 8 x (1 - progress) +
  6 x kick / menu height and fades in over progress 0.53 - 1
  (`contentFadeStart`/`contentFadeEnd`, `contentShrink`,
  `contentKickScale`, `contentBlur`, `contentKickBlur`); both fades read
  the progress spring 15 ms ahead (`fadeLead`), as the film shows the
  native fades leading the shapes in both directions. New
  `MorphMenuMotion.contentScale`, `contentRect`, `buttonLookStretch`.
- `MorphMenuButton`'s menu unfolds out of the drop (filmed again on the
  iPhone 16 Pro: a bottom-centre button with ten rows, both bottom and
  top corners, the centre menu; the native side without the probe's
  layer log so the recording keeps its frames). The content no longer
  waits near its final size for the shape to reveal it: it rides the
  menu shape at the shape's scale plus a swell with the kick
  (`contentScale` = shape scale + 1.45 x kick / menu height,
  `contentKickScale` 1.3 -> 1.45; `contentShrink` is gone), and its
  opacity follows the progress on the way in (`contentFadeStart` 0.53
  -> 0) - a ten-row menu showed nothing until half grown and then
  appeared at full size, not out of the drop. A menu taller than it is
  wide keeps its first row on the shape's top edge, like a list at its
  start (an upward ten-row menu unfolds from the far edge, as the film
  shows); a shorter one stays centered. The close still fades the
  content first: it falls linearly from where it was to nothing at
  `contentCloseFadeEnd` (0.53), and a re-open fades it back from there,
  so every reversal stays continuous. The shapes, kicks and placement
  already matched the native layers (path from the button center,
  clamped final rect, kick sign for upward menus); this changes only
  how the content rides them.
- `MorphSlider` filmed against the native UISlider (screen recordings of
  the iPhone 16 Pro, light and dark, the native side paired with the
  probe's layer rows): the colors are iOS 27's - fill systemBlue
  0xFF0088FF light / 0xFF0091FF dark (was 0xFF007AFF / 0xFF0A84FF), the
  track black or white at 10 percent (was a tinted 16 / 32 percent
  gray). The fill is its own rounded bar ending under the thumb center
  (a square clip before, visible through the lifted clear thumb) and
  within `MorphSliderMotion.fillRamp` (0.0198) of either end it runs
  out to the track end: a full slider is filled to its rounded end, an
  empty one shows no fill (before, 18.5 pt of track stayed unfilled at
  1 and 18.5 pt filled at 0; replayed on 300 and 200 pt sliders within
  0.15 pt). NEW: stepped sliders, `MorphSlider.ticks` (UIKit's
  `numberOfTicks`): 3 pt dots 8.5 below the track at the thumb's stops
  (`MorphSliderStyle.tickColor`), the reported value snaps to the
  nearest stop, the thumb rests near a stop and crosses to the next on
  an S-curve (`tickCurve` 4.5, held within `tickHold` 0.72 of the half
  step, followed on `tickFollowSpring` 0.03 / 1), settles on its stop
  0.035 s after the release on `tickReleaseSpring` 0.115 / 1 and never
  glides; arrows and adjust actions move one stop. New
  `MorphSliderMotion.position`, `fillEnd`, `tickCenters`.
- NEW: iOS 27 bars, measured on the iPhone 16 Pro (iOS 27.0.1) and the
  iOS 27.0 simulator with the probe's new `nav` scene (tuning read live:
  `GlassContainerToolbarPTSettings`, `PocketSettings`,
  `_UIFluidNavigationTransitionsSpec`, `_UINavigationBarTitleTransitionSpec`).
  `MorphToolbar` (floating capsules 48 tall, 28 from the sides and the
  bottom) and `MorphNavigationBar` (54 below the status bar, capsules 44
  tall, 16 from the sides, centered title kept 12 from the buttons) are
  rows of `MorphBarButtonGroup`s - adjacent `MorphBarButton`s share one
  glass capsule, groups float 12 apart, a press lifts the whole capsule
  on the glass-button model (recorded: 1 + 16/width, as `MorphGlassButton`).
  Every change of the items animates with `MorphBarMotion`, the toolbar
  item transition UIKit runs for `setToolbarItems(_:animated:)` and for
  the bar buttons of a push: capsules move and resize on 0.416 / 0.75,
  swell by up to 16 pt (20 percent) and settle height first, new capsules
  bud out of their neighbour's edge at a fifth of their size, items grow
  in from 0.2 with a 10 pt blur and leave the same way (replayed: device
  capsules 1.0 pt rms center, 1.6 width, 0.8 height).
- NEW: `MorphScrollEdgeEffect` (soft / hard) - the scroll edge effect
  that replaced bar backgrounds, as UIKit's own layers draw it: no
  progressive blur stack, one light blur (1.5 soft, 2 hard) over the band,
  the content faded 50 percent (60 dark) toward what lies behind it, the
  hard style adding saturation 1.25 + 3 percent brightness and a 1 px
  hairline at 10 percent; the soft band reaches 40 pt past the bar and its
  fade dissolves from 34 percent of the band. One backdrop blur per edge.
- NEW: `MorphLargeTitle`, `MorphLargeTitleScrollPhysics`,
  `MorphNavigationTitleMotion`: the large title scrolls with the content;
  once it is under the bar the inline title rises 15 pt, sharpens from a
  4 pt blur and fades in on a critically damped 0.45 s spring (leaves on
  0.7 s) with the edge effect on 0.35 s; a scroll set without a finger
  switches at once; a drag released with the title halfway snaps it out
  or under (replayed against simulator drags: title opacity <= 0.06 rms).
- NEW: `MorphNavigationStack` / `MorphNavigationRoute` /
  `MorphNavigationScaffold`: one shared bar and toolbar whose glass
  morphs from screen to screen, a back button labelled with the previous
  title, pages on `_UIFluidNavigationTransitionsSpec` (push 0.3 critically
  damped from full speed, the page below at 30 percent parallax; edge
  swipe 1:1 and release on the interactive 0.3 / 0.85 spring).
- Sheets: `presentMorphSheet` pushes a `MorphSheetRoute` that moves
  like iOS 27's UISheetPresentationController (`MorphSheetMotion`,
  `MorphSheetDetent` `.medium` / `.large` / `.height` / `.fraction`,
  `MorphSheetTuning`, `MorphSheetStyle`, `MorphSheet.of` /
  `MorphSheet.scrollControllerOf`). Measured on the iOS 27 simulator
  (iPhone 16 Pro, XCUITest touches and programmatic transitions): every
  transition is UIKit's CASpringAnimation of stiffness 333.3 / damping
  36.5 (response 0.344 s, critically damped; 0.06 pt rms); the medium
  detent is 0.56 of the maximum UIKit hands a detent resolver; below the
  large detent the sheet floats as the full-width sheet scaled to keep 8
  pt off the sides and the bottom (unscaled corners 38 top, display
  radius minus 8 bottom), and docks through one transform interpolated
  by the height's progress toward the large detent, its systemBackground
  fading in by the same fraction; dimming is black at 0.2 (scaled by
  the progress past an undimmed detent). Touch: a floating sheet swells
  by 0.85 percent on a 0.2835 / 0.70 spring 28 ms after contact; a drag
  moves the height point for point (nothing above the largest detent,
  a slide below the smallest), the release settles 25 ms later on the
  detent nearest to the height projected by 0.143 s of the finger's
  velocity, carrying twice that velocity into the spring; below the
  smallest detent a projected slide past half the visible height or a
  flick faster than 1000 pt/s dismisses (a flicked sheet leaves on
  0.352 / 0.79); a tap on the grabber band cycles the detents 50 ms
  after the lift; a scrollable handed `MorphSheet.scrollControllerOf`
  expands the sheet before it scrolls and moves it down from its top,
  as UIKit's do. Replayed in `sheet_test` and `sheet_drag_test`.
- `MorphPageControl` (+ `MorphPageControlMotion`,
  `MorphPageControlTuning`, `MorphPageControlStyle`,
  `MorphPageControlBackground`): UIPageControl's dots (9.67 pt
  indicators on a 17.67 pt pitch, 25.67 pt tall), a tap on either half
  stepping on the lift, the platter fading in 0.2 s into a resting touch
  (0.106 / 0.97 in, 0.10 / 1.0 out 20 ms after the lift), a scrub
  following the nearest dot, and UIPageControlProgress's capsule (27.33
  pt, its old fill fading on 0.381 / 0.963, widths changing on 0.398 /
  0.927).
- `MorphProgressView` (+ `MorphProgressMotion`, `MorphProgressStyle`):
  UIProgressView's animated change runs linearly for as many seconds as
  the progress changes, at least 0.2 s when the fill appears or
  disappears (an empty bar shows no fill; the fill is never under 8 pt),
  additive like UIKit's. `MorphActivityIndicator` (+
  `MorphActivityIndicatorFrames`): eight spokes, sixteen images per 0.8 s
  turn (`_UIActivityIndicatorSettings.fullLoopDuration`), the head and a
  four-spoke tail read from the rendered pixels.
- `MorphContextMenuRegion` calibrated against UIContextMenuInteraction:
  BREAKING (behavior) the default `holdDuration` is UIKit's measured
  0.78 s (was 0.5 s), and the held hero lifts to UIKit's preview size -
  the smaller of 15 percent and 26 points (1.15 at 120 pt, 1.087 at 300
  pt) - instead of the glass button's lift.
- `MorphContextMenuRegion` grows the held hero as UIKit grows its
  preview before the menu (iPhone 16 Pro, 60 x 40 to 300 x 200
  previews, 28 holds): BREAKING (behavior) instead of lifting on
  contact, the hero scales by `1 + growth / longest side`, where the
  growth (`measuredHoldGrowth`, the same points for every size) is 0
  until 0.184 s, 32 pt/s to 8 pt at 0.434 s, then 20 pt/s to 15 pt;
  the flight takes off from the grown hero, and a release before the
  commit point drops it at once. NEW: a release past
  `measuredCommitDuration` (0.42 s; 0.400 s cancelled, 0.433 s opened)
  opens the menu, and the child's tap no longer fires; the default
  `gap` is UIKit's 16 pt (`measuredMenuGap`, was 8); the satellites
  unfold out of a blob of 0.4 times the hero at its center and retract
  into it on the way home (`measuredRetractScale`). The open preview's
  lift (`measuredLiftScale` / `measuredLiftPoints`) is read along the
  longest side (80 x 160 opens at 92 x 184). The probe gained
  `testW2CtxGrowth` / `testW2CtxCommit`; fixture
  `ios27-device/context_menu/growth.json`.
- `MorphContextMenuRegion` keeps the open menu's hero at UIKit's
  lifted preview size (iPhone 16 Pro, 20 presentations of 60 x 40 to
  300 x 200 previews): BREAKING (behavior, geometry) the hero no longer
  shrinks back to its natural size on takeoff. NEW
  `measuredPreviewScale(size)` - 1.15, at most 26 points along the
  longest side (60 x 40 opens at 69 x 46, 300 x 200 at 326 x 217.3).
  The flight carries the hero from its grown size to the lifted one (a
  small hero shrinks a little, a large one keeps growing, as UIKit's
  preview does) about its natural center, the open copy is laid out at
  its natural size and painted lifted, the satellites stand `gap` off
  the lifted hero, the safe-area shift accounts for it, and the close
  lands it at its natural size. Menu columns are taller by the lift
  (a 160 x 48 hero adds 7.2 points), and a start-aligned column starts
  half the lift's width before the hero. `lifts: false` keeps the
  natural size. Fixture `ios27-device/context_menu/preview.json`
  (UIKit resizes the preview on one spring each way, response 0.284 s,
  damping 0.81, from the held size; the region rides its flight).
- `MorphContextMenuRegion` flies on UIKit's context-menu spring
  (iPhone 16 Pro, iOS 27): BREAKING (behavior, timing) the region's
  default motion is NEW `measuredMotion` - `measuredSpring`, response
  0.284 s and damping ratio 0.81, both ways - instead of the generic
  flight profile (`MorphMotion.liquid`, 0.35 / 0.75 open and 0.49 /
  0.80 close): the open reaches 90 percent in 0.137 s instead of
  0.156 s, and the close is no longer half again as slow. An explicit
  `motion` or a `MorphTheme` motion still wins. One recording per case
  shows UIKit's preview resize and its menu growing out of and
  retracting into the blob on that one spring each way, starting
  together (within 0.6 percent of the travel); the satellites now ride
  the open's 1.3 percent overshoot past their slots as UIKit's menu
  does, and the close's undershoot past the latch plays on the source
  hero, which dips below its natural size by the same 1.3 percent of
  the lift (300 x 200: 0.4 points) before it rests. The dimming is not
  on that spring - UIKit fades its black 0.2 dim on its own springs
  (0.32 / 0.80 open, 0.35 / 0.85 close) a frame later; the region's
  scrim still follows the flight. The probe gained `testW2CtxDim`
  (backdrop filter inputs, `PROBE_W2FILTERS`); fixture
  `ios27-device/context_menu/morph.json`.
- Shared elements measure their target rect below the shuttle's reveal
  scale (0.95 - 1), in layout space: a flying element follows the lerp
  of its endpoint rects exactly instead of drifting toward the
  content's center by up to a few points mid-flight.
- NEW: alerts and action sheets (iOS 27 simulator and iPhone 16 Pro,
  2026-10-03):
  `showMorphAlert`, `showMorphActionSheet`, `MorphAlertRoute`,
  `MorphAlertAction` (+ `MorphAlertActionStyle`), `MorphAlertTextField`,
  `MorphAlertStyle`, on `MorphAlertMotion`. The alert fades in with its
  0.2 dimming while it shrinks from 1.199, and fades out at its size, on
  UIAlertController's CASpringAnimation (522.35 / 45.71: 0.275 s,
  critically damped; scale 0.0005 rms, dimming 0.008 rms); 320 pt wide,
  radius 34, 48 pt capsule buttons 8 apart, two in a row with cancel
  first, more in a column with cancel last; a touch lifts the whole
  platter like a glass button of its size (0.09 - 0.25 pt rms) and the
  pressed button's fill drops to 40 percent; a chosen action's handler
  runs once the alert is gone. An action sheet with a source is a glass
  popover (`MorphPopoverMotion`: scale from 0.01 about the arrow tip and
  fade on 0.345 / 0.80 in, 0.373 / 0.85 out, 0.005 rms) placed by
  `morphPlacePopover` (15 of 15 UIKit placements), without its cancel
  action, which a tap outside runs at once; without a source it is an
  alert, as on iOS 27 iPhones.
- NEW: the search field (iOS 27 simulator and iPhone 16 Pro):
  `MorphSearchField` (+
  `MorphSearchFieldStyle`), `MorphSearchToolbar` and
  `MorphSearchTabBar` on `MorphSearchMotion` / `MorphSearchTuning`. The
  bottom search bar widens to 8 pt from the sides and rises 10 pt above
  the keyboard as the toolbar's buttons swell to 1.2 and fade where they
  stand and a close button arrives, all on SwiftUI's search transition
  spring 0.25 / 0.9 starting 0.067 s after the change (0.7 - 2 pt rms
  over 300 pt of travel); a touch lifts the field like a glass
  button 0.05 s after contact. A tab bar's search tab turns into the
  field: the bar shrinks into a circle with the selected tab's glyph
  while the search circle stretches into the field, on 0.276 / 0.80
  fitted to video (1.7 pt rms on the glass edges).
- NEW: the compact date picker (iOS 27 simulator): `MorphDatePicker` (+
  `MorphDatePickerMode`, `MorphDatePickerStyle`) on
  `MorphDatePickerMotion` / `MorphDatePickerTuning`. The label opens its
  calendar (or the hour and minute wheels) in an overlay that grows out
  of the label's center from 0.2 while its box grows from 50 pt and it
  fades in, on 0.32 / 0.80, and closes on 0.348 / 0.86 (fitted, 0.002
  rms); `morphPlaceDatePicker` hangs it 6 pt below the label's center
  toward the leading side (5 of 5 placements). The calendar turns months
  on a 0.3 s sine ease; the label dims under the finger on a 0.47 s
  CABasicAnimation and takes the accent color while open.
- DEVICE RECAPTURE (2026-10-03 morning, UI automation back on the iPhone
  16 Pro): every finger-driven measurement the night could only take on
  the simulator was retaken on the device; replays of the device
  recordings sit next to the simulator ones. Where the device differed
  beyond noise, the device won:
  - navigation edge swipe: a page released without a flick pops from
    `MorphNavigationTransition.popDistance` 0.3 of the width out (0.27
    returns, 0.32 pops; was 0.5, unmeasured), a flick decides past
    `popVelocity` 1.06 widths/s either way (was 1), a returning page
    leaves carrying 2.9x the release speed (`cancelVelocityScale`,
    fitted 2.7 - 3.1) and a popping one starts from rest. The settle
    spring 0.3 / 0.85, the large-title snap (25 pt back, 30 pt under),
    the inline title and edge effect springs and the bar item lift
    replay the device unchanged.
  - search: `MorphSearchToolbar` holds a focus until the keyboard starts
    to rise (UIKit's field starts 0.015 s after the keyboard's first
    frame, 0.17 - 0.19 s after the tap; `MorphSearchTuning.keyboardLag`,
    with `keyboardWaitLimit` 0.3 s as a guard when no keyboard comes).
    `MorphSearchTabBar` waits the same way and rises and falls on its
    own `tabFocusSpring` 0.3 / 1.0 (0.2 - 0.9 pt rms over 308 pt; the
    toolbar's 0.25 / 0.9 leaves 12), 0.07 s after the keyboard
    (`tabKeyboardLag`) and 0.04 s after the close tap
    (`tabUnfocusDelay`). `MorphSearchMotion.focus` / `unfocus` take a
    `delay`, and its constructor a `spring`.
  - alerts: the lifted platter follows a dragging finger a quarter as far
    as a glass button (`MorphAlertTuning.platterPull` 0.25) and stretches
    0.6 as much (`platterStretch`): 0.06 pt rms of lean and 0.1 - 0.2 pt
    of size against 0.7 - 1.3 and 1 - 4 before, through the new
    `MorphGlassButtonMotion.pull` / `stretch`. An action sheet popover
    no longer lifts under a touch (the device holds it still).
  - page control: the platter fades in after 0.193 s on a critically
    damped 0.100 s spring and out 0.032 s after the lift (120 Hz rows,
    0.013 - 0.017 rms; the 60 Hz simulator read 0.2, 0.106 / 0.973 and
    0.02).
  - confirmed unchanged on the device: sheet detent projection 0.143 s,
    the half-sheet dismissal rule, release gain 2, flick dismissal
    0.352 / 0.79 x 0.6, the touch swell 1.00854, the grabber tap and the
    2 percent stretch below the smallest detent (identical numbers);
    alert lift; the context menu's 0.78 s hold (0.768 - 0.797 s on the
    device), preview lift min(15 percent, 26 pt) and 16 pt menu gap;
    the slider's 11 pt pickup (finger lead within 0.7 pt of the model at
    every end).
- glass audit against the dark UIKit references: only surfaces that are
  Liquid Glass in iOS 27 are handed over as glass. `MorphGlassSurface`
  gains `glass` (false for the segmented, switch and slider tracks and
  the stepper, which are plain fills) and `MorphGlassPainter` gains
  `buildFill`, which draws such a surface flat; the default `buildLayer`
  routes plain surfaces there, and the stepper calls it instead of
  `buildSurface`. The dark tab bar's resting platter is darker than the
  bar, as on the device (`0xB5000000`, was a light 14 percent white).
  In the example's liquid painter a lifted lens, knob or thumb is clear
  glass that refracts what lies under it - the tab bar lens bends the bar
  glass and the magnified labels beneath it instead of covering them -
  and only a menu fuses with its button.
- BREAKING (painters): `MorphGlassPainter.buildLayer` takes
  `contentSlots`, the boxes of the content's items (segments, tabs, bar
  items) in the layer's coordinates; an override must accept the
  parameter. A painter that magnifies content under a lens scales each
  item about its own slot, so a label under a dragged lens stays still
  and only the lens window moves, as in UIKit. The example's liquid
  painter used to scale about the lens center, so the label slid along
  with a dragged lens.
- example gallery glass: the vendored `liquid_glass_renderer` moves to
  upstream release/01-renderer-core @ ab1c2d29 (frost at the Clear end
  2 pt instead of 3.7, the regular frost curve refitted, dimmer glint on
  dark toolbar and clear glass, one render base for real and fake
  glass). A lifted lens over a tab bar now MINIFIES the bar glass beneath
  it (`backdropShrink`), as the device's tab bar lens does, while the
  items under it still grow by 16 percent about their own slots: the
  copy is pre-grown against the shrink. The glass page gains the iOS
  Liquid Glass Clear / Tinted choice beside the slider; Clear stays the
  default.
- example gallery glass, measured per control against the iPhone 16 Pro
  references (glyph scale fitted by correlation over scales, edges at
  sub-pixel crossings): the tab bar lens magnifies its items by 1.158 on
  top of the swollen bar (1.218 against the resting bar, the bar 1.052)
  - the painter keeps 16 percent; the segmented lens does NOT magnify
  its labels (0.996), so its copy now shows them at their own size (was
  16 percent). The lifted segmented lens and switch knob now minify the
  track beneath them like the tab bar lens minifies the bar: the edges
  inside show at 0.8125 (segmented) and 0.755 (switch) of the track's
  height, the tab bar's at 0.890 of the swollen bar's; the slider thumb
  shows its track unchanged and does not shrink. The lens bevel pulls
  the backdrop inward near its rim, so the renderer shrinks are 0.20,
  0.25 and 0.16 (the tab bar's was 0.14, which showed 0.932); on the
  device the gallery shows 0.815, 0.762 and 0.891. UIKit's minification
  fades toward the lens's middle (the track's end inside the segmented
  lens sits at 0.96 of its distance from the center), which a uniform
  shrink cannot follow. The copy's pre-growth follows the glass's
  visibility as the renderer does, so a label stays on its slot while
  the lens is still turning into glass.
- example gallery glass: a lifted lens minifies by depth below its rim,
  as UIKit's does, instead of by distance from its center. The vendored
  renderer gains `LiquidGlassSettings.backdropShrinkRim` (0 to 1,
  default 0 = unchanged): the backdrop shrinks about the nearest point of
  the glass's long center line, so a capsule minifies across its
  straight part and radially about the centers of its round ends. The
  segmented lens and the switch knob use the full line, the tab bar lens
  three quarters of it. On the iPhone 16 Pro the track's end inside a
  held end segment now sits at 0.960 of its distance from the lens
  center (reference 0.962; the center shrink showed 0.800 and too much
  page beyond the track), the track's end inside the switch knob at
  0.869 (reference 0.870, was 0.766), and the swollen tab bar's end
  inside the lens 10 px in (reference 11, was 19); the edges across the
  lens are unchanged. The content copy under the lens is grown against
  the same profile in three strips, each exact, so labels still sit on
  their slots through the glass.
- Navigation (owner's iPhone pass on the gallery's Navigation page):
  - `MorphNavigationStack` owns the pops of its own screens: its
    navigator sits under a `NavigatorPopHandler`, so while it can pop,
    the enclosing route reports `doNotPop` - its Cupertino edge swipe
    and predictive back stay off, and the system back, `maybePop` on the
    enclosing navigator and an Android back pop the stack's top screen;
    at the stack's root they reach the enclosing route as before. An
    edge swipe on a pushed screen used to be won by the enclosing
    `MaterialPageRoute` and left the whole stack.
  - the bar morphs on a push as it does on a pop: a pushed screen's
    configuration arrives one frame after the push, and the stack used
    to show an empty bar for that frame, so capsules died and were
    reborn and the toolbar remounted. The stack now keeps the previous
    screen's bar until the pushed one publishes (or its first frame
    passes).
  - BREAKING: a bar group without an `id` is identified by its place
    counted from the bar's edge, so the outermost trailing capsule
    morphs into the outermost one (as the device does on a push); the
    stack's back button is no longer a separate `morph.leading` group
    and morphs out of the leading capsule it replaces.
  - NEW: `MorphNavigationBarDrift` (`MorphNavigationBar.drift`,
    `MorphBarMotion.setDrift`): during an interactive edge swipe each
    capsule the destination bar also has leans
    `MorphNavigationTransition.barDrift` = 0.5 of the page's progress
    toward its place there, a pure function of the page's position (a
    cancelled swipe leans back with the returning page, a committed one
    hands the leaning capsules to the item transition without a jump).
    Refitted on four new iPhone 16 Pro swipes (0.49 at no lag, 0.50 one
    or two display ticks behind; replay 0.16 - 0.27 pt rms,
    `pop-edge-drift-*` fixtures).
- NEW: `MorphTypography` - UIKit's text for the measured controls, one
  home. Role styles carry the size and weight each control's labels use
  on iOS 27 (read from the real labels by the probe's `fonts` scene on
  the iPhone 16 Pro), and `MorphTypography.resolve` turns one into what
  CoreText does with the system font and Flutter does not: the optical
  size axis (`opsz` = the point size), UIKit's `wght` values (medium
  510, semibold 590) and SF Pro's size-dependent tracking
  (`MorphTypography.tracking`, measured 6 - 96 pt, e.g. 13 pt -0.076,
  17 pt -0.431, 34 pt +0.382). On Apple platforms only; elsewhere the
  style stays the platform font at the same size and weight (SF Pro is
  never bundled). Every control paints through it, and the measured
  weights replace the guessed ones: segments regular / selected medium
  (were medium / semibold), tab titles medium / selected semibold, glass
  button titles regular (were medium), plain bar buttons medium (were
  regular). Widths now match UIKit on the device within 0.01 pt for 25
  labels across the controls; "Unread messages" in a segment is 108.58
  pt as in UIKit (was 112.0), a large title "Settings" 132.96 (was
  143.9). Hard-coded `letterSpacing` values are gone from the widgets
  (the menu's -0.4, the large title's +0.4, the date wheel's +0.35).
- NEW: the zoom from a source (`preferredTransition = .zoom`), measured
  on the iPhone 16 Pro (iOS 27.0.1) from screen recordings - the zoom
  does not show in the presentation layers. `presentMorphSheet(from:)`
  takes the id of a `MorphTag`: the source hides, a container grows out
  of its frame into the sheet's while the source's look (stretched over
  the container) crossfades into the sheet's content (laid out at its
  own size, scaled to fit from the top leading corner), and every
  dismissal zooms back into the source, which shows again once the zoom
  rests. `MorphZoomMotion` / `MorphZoomTuning`: the container's center
  and size ride springs of their own, fitted to device presents (center
  0.349 / 0.833, size 0.472 / 0.748, 3.3 pt rms) and dismissals (center
  0.442 / 0.762, size 0.203 / 1.0, 5.2 pt rms); the crossfade is a 0.154
  s critically damped spring, 0.045 s late on the way in; the dimming
  rides `_UIZoomTransitionSpec`'s zoomIn 0.34 / 1.0 and zoomOut 0.34 /
  0.92 (device fits 0.322 / 1.0 and 0.354 / 0.919). A drag down from the
  smallest detent scrubs the sheet - it follows the finger, its top a
  little ahead (1.115 per point of travel), its sides drawing in (0.275)
  - and the release decides: past 100 pt of travel or faster than 1050
  pt/s it zooms into the source from where the finger left it, else it
  returns on a 0.196 s critically damped spring
  (`MorphZoomTuning.scrubFrame` and the scrub values; device films:
  held drags of 77 pt returned, of 126 pt and more dismissed). Some
  device drags (4 of 5 in one session, 2 of 14 in another) dismissed at
  once instead, with no trigger found; morph always scrubs.
  Replayed in sheet_zoom_test (fixtures ios27-device/zoom).
- NEW: the zoom into a pushed page. `pushMorphZoom(context, from:,
  builder:)` (or `MorphNavigationRoute(zoomSource:)`) grows the page out
  of a `MorphTag` as UIKit pushes a view controller whose
  `preferredTransition` is `.zoom`, measured from device films (iPhone
  16 Pro, iOS 27.0.1). `MorphPushZoomMotion` / `MorphPushZoomTuning`:
  center and width open on 0.317 / 1.0, height on 0.406 / 0.925 (0.98
  pt rms over four pushes); a pop rides UIKit's zoomOut 0.34 / 0.92
  (0.54 pt rms); the source's look crossfades into the page (0.156 s,
  back 0.191 s), the page underneath dims by black 0.15 and takes the
  container's shadow, the corners run from the source's to the
  display's. A finger dragging the page down, or toward the trailing
  edge, within 30 degrees, shrinks it about the touch point (measured
  rates per direction) and on release either zooms it into the source
  (past 132.5 pt or 1050 pt/s; from rest, on 0.45 / 0.81 and 0.33 /
  0.98) or returns it (0.278 / 0.927). Replayed in push_zoom_test
  (fixture ios27-device/push_zoom, five transitions and ten drags,
  outcomes exact). The gallery's Navigation page has zooming photos.
- The back button's capsule rings out after its menu closes, as UIKit's
  does (filmed): after the latch the bar draws both shapes of the menu
  motion on the capsule until they rest, the glyph riding the button
  shape, instead of snapping back to the plain capsule.
- NEW: the back button's long-press menu. `MorphBarButton.menu` gives a
  bar button the menu of `MorphMenuButton`, grown out of its capsule on
  the engine (a vessel flight from the bar's own tag); the measured
  timing is `MorphBarMenuTuning` (device holds: a release before 0.4 s
  is a tap - 0.25 and 0.35 popped, 0.45 did not - and the menu opens
  0.595 s after the touch, 0.584 - 0.609 over seven holds). A finger
  still on the button when it lifts after the opening fires the button
  and closes the menu (UIKit pops one screen, 4/4); one moved away
  leaves the menu open. `MorphNavigationStack` gives its back button
  the back stack, nearest screen first, and a row pops to that screen.
  The menu machinery behind `MorphMenuButton` is shared through an
  internal host (`MorphMenuHost`, `MorphMenuLayer`,
  `MorphMenuFlightProgress`).
- NEW: capsules of one bar fuse as UIKit's do. Every capsule of a
  navigation bar, and of a toolbar, is an element of ONE SDF layer
  whose smoothness - the glass container spacing - is 12 (read from the
  layers on the iPhone 16 Pro and the simulator, constant through item
  changes and group splits). `MorphBarMetrics.containerSpacing` (12)
  goes to the glass seam: BREAKING (painters) `MorphGlassPainter.
  buildLayer` takes `spacing`, the container spacing of the surfaces it
  hands over (0 keeps them apart). Groups rest 12 apart, where the
  merge law's reach ends, so resting groups never touch; a group that
  splits, or capsules passing during an item change, fuse while closer.
  The flat fallback traces the fused outline with the skin's law
  (cell 2) whenever two capsules are within the spacing, regardless
  of color.
  The gallery's liquid painter blends a bar's capsules at the spacing
  (it had stopped blending them because its old blend of 18 melted
  groups 12 apart).
- NEW: the tab bar's touch glow, measured on the iPhone 16 Pro (iOS
  27.0.1, dark and light, per-frame layers of the bar group plus screen
  recordings). A press lights the bar with UIKit's two flex interaction
  glows, both color matrices over the bar rather than paint: a wash that
  adds 0.05 per channel at opacity 1 (the held dark bar goes 32 -> 43)
  and a soft spot under the finger that multiplies by 4.0 (dark) / 1.667
  (light) at its center, a 93 pt disc whose screen falloff is a Gaussian
  of 0.568 x its diameter at 0.38 of the layer's strength. They peak at
  the bar's flex spec glow opacities (0.845 and 0.2845 for 62 pt), rise
  on a 0.1 s critically damped spring 0.042 s after the touch, hold
  while the finger is down, and fall on 0.5 s 0.02 s after the release
  while the spot spreads fourfold; a finger that moves 50 pt from its
  landing (bracketed by drags of 40 and 60 pt) spreads the spot to twice
  its size at half strength. `MorphTouchGlowMotion` (pure, replayed in
  tab_bar_glow_test against fixture ios27-device/tabglow; opacity rms
  at most 0.022 / 0.007) and `MorphGlassGlow` (wash, center, radius, gain) on
  the new `MorphGlassSurface.glow`; `MorphGlassPainter.buildGlow` paints
  it (additive wash and color-dodge spot, exact over gray), the default
  `buildLayer` and the flat bar call it, and so does the example's
  liquid painter.
- The tab bar's selected tint follows the lens: the tabs inside the
  lens outline wear the selected style (tint and semibold title), the
  rest the regular one, cut along the outline every frame, so the blue
  travels with the lens and a tab half under it is half blue, as in
  UIKit (a selected copy of the items masked by the lens). Colors are
  what UIKit's vibrant color matrices make of the measured bar: selected
  0xFF0397FF dark / 0xFF0082FC light (was systemBlue), unselected
  0xFFFAFAFA / 0xFF0D0D0D, resting platter 0xAF000000 / 0x13000000 (the
  platter's matrix: 0.87 x - 0.07 dark, 1.13 x - 0.2 light, over a
  2 pt blur).
- Search field and compact date picker filmed against UIKit on the
  iPhone 16 Pro (iOS 27.0.1; MorphRecorder screen recordings of the
  probe's `x3search` / `x3date` scenes and of morph's rebuilt scenes,
  both driven by the same XCUITest schedule with real touches and the
  real keyboard, light and dark, paired with the probe's layer rows).
  Search: a held touch on the field now focuses it when it lifts, as
  UIKit does (a 0.5 s hold used to win Flutter's long press and never
  focus); the tab bar's search tab takes the focus 0.16 s after the tap
  while its morph still runs (`MorphSearchTuning.tabActivationDelay`;
  focusing the field the frame it was built lost the keyboard on the
  device: the engine closed the fresh input connection); closing a
  search (toolbar and tab bar) falls straight from above the keyboard
  to rest instead of following the keyboard down and dipping 18 pt
  below the resting place; the keyboard follows the dark appearance;
  the magnifier (13.33 pt ring, 1.75 thick), clear disc (16.67 pt) and
  close cross (16.67 pt, 2.3 thick) take the screen's ink; the cursor is
  UIKit's 66/106/243 (dark 64/107/248); the resting placeholder is
  lighter than the focused one (new
  `MorphSearchFieldStyle.restingPlaceholderColor`); the field paints
  before the toolbar's fading items, so a disabled or fading item no
  longer leaves the field's glass reading an empty backdrop;
  `tabUnfocusDelay` 0.05. Date picker: the calendar keeps 16 pt from the
  sides on phones under 414 pt (`MorphDatePickerTuning.marginFor`); the
  title no longer truncates ("October 2..." - it shared the header with
  a spacer) and sits 20.33 pt in; the month chevrons are label colored,
  10 x 17.33 pt, 2.6 thick; a chosen day that is not today sits on a
  label disc (`selectedDayFillColor`, `selectedDayTextColor`); the
  overlay opens 0.14 s and closes 0.055 s after the lift
  (`openDelay`/`closeDelay`, device rows 0.010 rms against 0.27 / 0.16
  without them); its glass fades through the new
  `MorphGlassSurface.opacity` instead of an opacity layer (the open used
  to show a gray platter until it settled); tapping the other label of a
  date-and-time picker turns the open overlay into the other picker on
  a critically damped 0.25 s spring 0.088 s after the lift, contents
  cross-fading on the same progress (`switchSpring`, `switchDelay`;
  before, the tap only closed it); the time wheels sit on UIKit's
  cylinder (rows 31.3 / 56.7 pt out at 0.905 / 0.647 height, columns at
  73.5 / 148.5 pt), 21 pt rows magnified to 23.5 in the band, fading
  toward the edges, and decelerate fast (a 64 pt drag turns two rows,
  as on the device, not six); `wheelFadedColor` became
  `wheelFadedOpacity`. Not reproduced: UIKit's empty prediction bar on
  the search keyboard, and a tap on the tab circle during the tab
  morph (ignored here; the device capture could not time one).
- The search and date picker leftovers, measured on the iPhone 16 Pro.
  The tab bar's tab circle takes a tap while the morph into the search
  field still runs and turns the morph around with its velocity, as
  UIKit does (the search circle keeps ignoring taps while the morph
  back runs, as UIKit does too). The search field asks for sentence
  capitalization like UIKit's; UIKit's empty prediction bar (autocorrect
  off, spell checking on) cannot be asked for through Flutter's engine,
  which ties both to one flag, and dropping the bar would lower the
  focused field 27 points, so the bar keeps its suggestions. The date
  picker: a tap outside while the overlay opens turns it around 0.037 s
  after the lift (new `MorphDatePickerTuning.closeDelayWhileOpening`),
  a tap on the label while it closes opens a new overlay 0.072 s after
  the lift while the old one finishes (new
  `MorphDatePickerTuning.reopenDelay`; before, the closing overlay
  swallowed the tap); 12-hour time gets UIKit's AM/PM wheel, the hour
  wheel 1 - 12 with right-aligned numbers, and AM/PM flips as the hours
  pass 11 and 12; the rows beside the band fade by a table read from
  device screenshots (they showed 9 percent more contrast than UIKit's).
  Alerts and action sheet popovers fade their glass through
  `MorphGlassSurface.opacity` instead of an opacity layer: no gray
  platter while they appear and leave.
- A flight's scrim can run on springs of its own: `scrimMotion:
  MorphScrimMotion(motion:, openDelay:, closeDelay:)` on `showMorph` and
  `MorphFlight.launch` (internal), `showMorphSheet`, `showMorphDialog`,
  `showMorphRoute` and `MorphAnchor`, or through `MorphTheme.scrimMotion`.
  The scrim then follows the flight's open / close
  intent on its own spring after its own delay, retargeting with its
  velocity, and stays up past the handoff latch until it rests (the page
  takes touches again meanwhile; `landed` comes after it).
  `MorphFlight.scrimOpacity` and `scrimValue` read it. Without one the
  scrim follows the flight value as before.
- `MorphContextMenuRegion` dims like UIKit's context menu (measured on an
  iPhone 16 Pro): black at 0.2 in light and 0.48 in dark
  (`measuredDimOpacity`), alpha only, opening on 0.32 / 0.80 and closing
  on 0.35 / 0.85, 14.5 ms and 12.5 ms after the morph
  (`measuredDim`, overridable with `scrimMotion:`). BEHAVIOR: the default
  dim was 0.35 riding the flight value. Its satellites now unfold out of
  and retract into the held view's center (a menu below a 300 x 200
  view used to land 15 pt low).
- `MorphMenuButton`'s two shapes fuse as UIKit's do: the morph container
  is an SDF layer with no smoothness whose distance field is blurred by
  a Gaussian of up to 20 pt (`MorphMenuTuning.fusionRadius`, read from
  the device's `gaussianRadius` and replayed against film of a ten-row
  menu closing into a bottom button). The blur rises with every open and
  close and falls back to nothing (`fusionEnvelope`); while it lasts the
  facing edges draw to a point, the shrunk button is absorbed and a neck
  joins the shapes across the gap where a separate ball used to show.
  The motion hands the fused silhouette out (`MorphMenuMotion.silhouette`,
  `fusionRadius`), the flat glass draws it, and painters receive it
  through the glass seam. BREAKING for glass painters:
  `MorphGlassPainter.buildLayer` takes an `outline:` - a
  `MorphGlassOutline`, the silhouette a control already fused its glass
  surfaces into (its `path`, and for the package's own renderer the
  sampled distance field behind it) - and a new `buildBody` draws it
  (the default fills the path flat); an override of `buildLayer` must
  accept the new parameter.
- The glass renderer lives in the package. The owner's rule that no
  glass shader lives in morph is cancelled: whynotmake-it's
  `liquid_glass_renderer` (Apache-2.0, upstream ab1c2d29, with the
  local patches listed in `lib/src/glass/renderer/VENDORED` and a
  NOTICE) moves from `example/third_party` into
  `lib/src/glass/renderer` as morph's own renderer; its shaders are
  package assets and `hook/build.dart` builds its Flutter GPU bundle.
  BREAKING for consumers: morph now needs Flutter 3.47 (Flutter GPU)
  and depends on equatable, flutter_gpu, flutter_gpu_shaders,
  flutter_shaders and hooks. The unused logging dependency is removed. The one public entry is
  `MorphGlassRenderer`, a `MorphGlassPainter` with quality tiers
  (`MorphGlassTier.flat`, `frosted`, `liquid`) and the liquid tier's
  settings (`MorphGlassMaterial`, blur, refraction, light, tint,
  frostControls) plus the measured lens optics as constants;
  `MorphAdaptiveGlass` installs it at one tier for the session: the
  tier given, else the one the device's GPU class allows. The package
  computes every shape once and every tier shades the same outlines:
  the menu's blurred silhouette and the capsules a glass container
  fuses (`spacing`, by the skin's merge law) arrive as a
  `MorphGlassOutline` with a sampled distance field, and the liquid
  tier shades it in a new field geometry pass - the menu's neck is
  liquid glass now, not frost under clipped glass - while the
  renderer's own blend groups are gone. On the web the final-render
  shaders compile to stubs and the renderer draws frosted glass, so
  the web example builds without removing anything.
- The compact date picker's month title works (measured on an iPhone
  16 Pro, light and dark): a tap on it turns the calendar into month
  and year wheels inside the same platter, as UIKit does. The grid, the
  weekday initials and the month chevrons fade out and the wheels in on
  a 0.25 s ease in and out (new `MorphDatePickerTuning.yearPicker*`,
  starting 0.069 s after the lift, back 0.019 s after; a second tap
  restarts the fades from where they stand), the title takes the accent
  at once and its chevron turns a quarter to point down, adding up its
  turns as UIKit does (`MorphDatePickerMotion.showYearPicker`,
  `yearPicker`, `yearPickerTurn`). The wheels open on the shown month;
  one coming to rest moves the chosen day to its month and year,
  keeping the day where the month has it (the 31st turned to November
  is the 30th), and the title follows. The title is a button for
  screen readers ("Show year picker" / "Hide year picker", the month as
  its value), the wheels adjustable. The time wheels share the wheel
  code. A six-week month no longer grows the calendar: UIKit keeps it
  320 x 332 and packs the rows 38 pt apart with a 38 pt disc
  (BREAKING: `MorphDatePickerTuning.weekHeight` is gone, new
  `sixWeekRowHeight`), and the day grid sits 1 pt lower, where UIKit's
  first row is.
- Fused glass is cheaper and closer to the shapes it fuses. The menu's
  blurred silhouette samples its trace grid only near the edge and skips
  the blur wherever the kernel cannot change the field (one straight
  side) or has a closed form (one round corner); a bar's fused capsules
  sample the merge law only near the edge too. On the iPhone 16 Pro a
  ten-row menu at a 4 pt blur now costs 0.71 ms of UI thread per frame
  (was 2.02), 0.61 at 10 pt, 0.36 at 20 pt, two fused capsules 0.12 ms
  (was 0.68). A fused body's corners turn their light on the 1.5x
  optical radius the shapes alone use, the fake glass that stands in
  without Flutter GPU draws the fused outline (it drew the separate
  shapes, and threw holding Back on a pushed page), and the bar's flat
  painter fuses through the same groups and outline as every tier. The
  dark date picker's platter is the dark menu's glass, 0xF2222222 (it
  drew 44 gray where UIKit shows 32).
- Bars and navigation: BREAKING: `MorphNavigationConfig.signature` is
  removed. Configs, `MorphBarButton` and `MorphBarButtonGroup` compare by
  value, with callbacks by identity, so fresh closures update the shared
  bar. Returning ids reverse a fading item or capsule instead of creating
  duplicate keys; layout ids compare by value (`1` differs from `'1'`).
  A committed edge swipe removes its own page even if another was pushed;
  disposal ends the user gesture and bar drift. Back-menu rows for removed
  screens do nothing, and an open back menu follows entry changes. A
  scaffold in a nested navigator keeps its own bars.
- Bars gain `backLabel` on `MorphNavigationStack` and
  `MorphNavigationScaffold`; `menuStyle` and `menuOverlay` on the stack,
  `MorphNavigationBar` and `MorphToolbar`; `MorphToolbarMetrics` and
  `MorphBarMetrics.maxTextScale`, `lineHeight` and `backChevronHeight`.
  `MorphBarStyle` and `MorphBarMetrics` compare by value. Scaffold
  backgrounds resolve through `MorphScrollEdgeEffectThemeData`; reduced
  motion fades navigation pages in place. Bar menus respond to the
  accessibility long press. Animation ticks retain button contents,
  fused flat outlines are traced once per change, and label/title widths
  are cached.
- Engine lookup hygiene: BREAKING: `MorphScope.of`, `MorphTag.specOf` /
  `idOf`, `morphAnchorRect` and unknown `from:` ids throw descriptive
  FlutterErrors in every build mode. `MorphScopeState.tryTagOf` supports
  optional sources. Duplicate tag and shared-element ids are reported
  through `FlutterError.reportError`; the first tag keeps its id until
  it leaves, then the second takes over. Tags re-register when moved
  between scopes, and scope-less tags/skins degrade without crashing.
  Anchor rects, shared-element rects and flight necks follow the whole
  paint transform. Flying shared-element keys are `ValueKey<Object>(id)`.
- Engine defaults live in `MorphTheme.defaultMaxScrimOpacity`,
  `defaultScrimColor`, `defaultShadowColor` and `defaultTargetElevation`.
  `modal` is available on sheet/dialog helpers, routes and `MorphAnchor`;
  changing an open anchor's `motion` updates its live flight. Route scrims
  resolve the theme, routes accept explicit overlays and resolve the
  source page's scope. Removing a route without popping reveals its
  source and retires the flight; declined dismissals preserve history,
  and dead overlays clean up their flights. BREAKING: flight geometry is
  read-only and `MorphFlight.launch` is internal.
- `MorphFlight.geometryTicks` excludes scrim-only ticks, so the skin
  does not repaint for them; shuttle subscriptions churn less. A tag
  without `snapshotGhost` adds no RepaintBoundary or GlobalKey, skin
  repaints reuse buffers and paints, and duplicate animation status
  listeners no longer leak proxies. Oversized tracing grids coarsen
  instead of vanishing; a `cell` below 2 px asserts in debug.
- Submenu calibration: cards hand their headers back to their source
  rows, hiding those rows while shown and preventing a blink on close.
  Their platters blur and brighten the list below, with a top rim and
  outside shadow. BREAKING: `MorphMenuStyle.submenuColor` is a translucent
  tint; `submenuRimColor` and `submenuShadowColor` are new. Closing the
  whole menu shrinks an open card with the drop, centered and unblurred,
  fading near the end; selecting a card row closes 0.015 s after release.
  New `MorphMenuTuning` fields: `submenuCloseDelay`, `cardRowsFadeIn`,
  `cardRowsFadeOut`, `cardPlatterFade`, `cardHeaderBoldStart`,
  `cardHeaderBoldEnd`, `cardChevronTurn`, `cardChevronBack`,
  `cardCloseFadeEnd`, `cardCloseCenter`, `cardBlur`, `cardGone`.
  New `MorphMenuCard` fields: `contentTop`, `rowsOpacity`, `platterOpacity`,
  `headerBold`, `chevronTurn`, `closeOpacity`, `backing`, `source`.
- Renderer hygiene: runtime capability detection falls back from liquid
  to frosted glass with a cached diagnostic, remembering failed bundle
  loads. Adaptive and frosted surfaces share backdrop captures. Lifted-lens copies paint from
  one mounted subtree, preserving GlobalKeys and focus. The build hook
  writes the GPU bundle to `build/shaderbundles`, whose asset entry stays
  in the pubspec (f8b921d corrects an attempted data-asset-only package
  that fell back on Flutter 3.47.2). Unused upstream code is removed,
  field uploads and glow shader allocations reduced.
- Sheets, zoom and alerts: Escape dismisses dismissible sheets, Android
  back runs alert cancellation once, and overlapping presentations pop
  their own routes. BREAKING: sheet and navigation zoom routes take source
  ids; missing sources degrade and removed sources dissolve. RTL zoom
  radii, popover placement, text-field Return and detent notifications
  are fixed; motion routes and zoom sources share internal implementations.
- Other controls: scrolling a date label no longer opens it, rejected
  controlled values keep their semantics, and invalid page inputs are
  handled. Style resolution and capsule painting share implementations,
  glass glow is consolidated, controls accept localization callbacks,
  and date wheels follow updated bounds. Per-tick layout work is removed.
- The seven measured control hosts (segmented control, tab bar, switch,
  slider, stepper, glass button, page control) share one internal
  MorphControlHost: clock and ticker lifecycle, pointer gate, event
  stamping, focus and disable cancellation; the pure motion classes stay
  exported.
- MorphMenuButton and the bar's button/back menus share one internal menu
  host. A menu closes when its button is disposed; menu constants live in
  MorphMenuTuning; long-idle kicks skip ahead; the More label is
  localizable and menus carry their semantics; the context menu follows
  `enabled` and `tagId` changes.
- BREAKING: engine flights now overshoot in size as well as position;
  concentric corner radii follow the same raw spring value past 1.
  Context-menu satellites use the engine geometry once, and the close
  handoff and source undershoot stay unchanged.
- Remaining audit/fidelity work: scroll-edge backdrop grouping (PF9) and
  configurable bar-menu tuning (P5api). Submenu dark
  film dropped frames, so dark styling was judged from stills; the close
  drop starts from the whole menu instead of the list, row tap highlights
  differ from the films, chevron turn/bold switching is estimated and the
  header chevron remains slightly large.
- Coordinator verification of the combined audit tree before docs cleanup:
  formatting and analysis clean,
  1014 package and 11 example tests (after the control and menu host
  merges), zero dartdoc warnings, and iOS
  release, web wasm and macOS builds plus the macOS autodemo passed.

## 0.6.0 - 2026-09-03

The content decides. A target can now be sized by what it holds and
springs to every change while the flight is up, every target stays
clear of the keyboard, and the held menu's column is live - its hero
slot and satellites follow their content. Behavior shifts in two
places, called out below; the rest is additive.

- `MorphTargetSpec.measured(constraintsFor:, placeFor:)`: a target
  measured by its content. The content is laid out under the
  constraints (a tight width, a loose height up to a cap), its size is
  measured, and the placement turns the size into the rect. The first
  measurement seeds the target; every later change - a capsule growing
  on selection, a chip unfolding - springs the surface on the flight's
  open motion while the content lays out at its natural size and the
  surface reveals it as it catches up. A launch never shows a guessed
  box: the shuttle stays invisible and the source visible until the
  first measurement lands. `fitContent` on `MorphTargetSpec.sheet`,
  `dialog` and `popover`, and on `showMorphSheet`/`showMorphDialog`,
  turns the box's height into a ceiling. `MorphFlight.contentSize`
  (smoothed) and `measuredContentSize` expose it; the settled route
  page keeps measuring too. BEHAVIOR: `showMorphMenu` is measured
  unconditionally - the row height no longer follows an arithmetic of
  the text scale, the rows size the menu.
- The keyboard. BEHAVIOR: the padding every `rectFor` receives is now
  the safe area unioned edge by edge with the keyboard, so a sheet
  docks above it, a dialog centers in the room left and a popover
  clamps clear of it - by construction, in every existing factory. A
  fullscreen target, which ignores the padding, still covers the
  screen. The target content sees only the part of the keyboard its
  surface still overlaps (a Scaffold inside no longer avoids it a
  second time); the settled route page applies the same math. Fixed
  dialogs and popovers now cap both axes to that unobstructed room, and
  window insets are translated into the actual flight overlay's local
  coordinates before placement - an offset nested overlay reserves only
  the keyboard strip that intersects it.
- `MorphTargetSpec.repaint`: a `Listenable` whose notifications re-lay
  the frame (the CustomPainter idiom) for a rect that reads state of
  the owner's; `contentAlignment` is overridable, and the class may be
  extended for geometry that follows live state.
- `MorphContextMenuRegion`: the column is live. `MorphSatellite.height`
  is optional - a slot without one is sized by its content, seeded at
  launch and springing to every change - and the hero's slot follows
  the hero: a badge appearing on the bubble shows at once, the actions
  slide down on the spring, and the hero stays put while a capsule
  grows above it. The column moves out from under the keyboard with
  the hero travelling in it. A change to the child or the satellites
  while the menu is open rebuilds its content and geometry together.
  `replica:` supplies every overlay copy - source ghost, target slot and
  shared flight - while the live child remains mounted only at home, so
  a visual replica without the child's FocusNode/controller/GlobalKey
  keeps those single-owner objects safe. `opensOnSecondaryTap` leaves
  the right click to someone else.
- Example: chapter 03, Hold to menu - a reaction lands on the bubble at
  once and unfolds a note field in the capsule; the KEYBOARD toggle
  raises the phone's own keyboard (`PhoneFrame.keyboard`) and the open
  menu moves out from under it, the compose bar rising with it.
- The pill host's sympathetic chrome shift is quieter for opaque ink:
  3px instead of the glass reference's 4px. Its uniform breath remains
  unchanged.
- `MorphTag` now captures its full bounds through ancestor paint
  transforms instead of transforming only the top-left and retaining
  the layout size. Context-menu holds consequently launch from the
  exact lifted pixels, keep that press rect stable for the flight and
  release it once takeoff settles, removing the visible handoff shake.
  Context-menu landings are quiet by default (`bumpScale` and
  `bumpRecoil` default to zero): expanding satellites no longer give a
  stationary hero a false impact, and close returns to the natural
  source rect instead of replaying the press growth.

## 0.5.0 - 2026-09-02

The hold. A surface becomes its own context menu when held, and the
engine grows the four seams that recipe needed: a flight announces its
moments, survives losing its source, renders in a chosen overlay, and
can leave its content unclipped. Additive throughout: nothing existing
changes shape or default.

- `MorphContextMenuRegion` and `MorphSatellite` (widgets layer): the
  message-bubble pattern. The hero under the finger lifts on the touch
  (the Tug press; inside a scrollable it waits for the touch deadline,
  so a scroll never flashes it), and on the hold threshold it flies to
  where its satellites fit - slots of a declared height above and
  below, unfolding on the flight's own spring - as a shared element,
  never a copy fading over a copy. The flight's container is a
  transparent vessel: the hero draws its own surface and the app draws
  the rows; the vessel's content alignment is chosen so the hero slot
  coincides with the flying hero at every spring value, which makes
  the satellites ride the hero as one rigid body. The hero stays put
  unless the column would leave the safe area, then the whole column
  shifts. Three doors: the hold, a secondary click, and
  `MorphContextMenuRegion.open(context)` from inside the hero - the
  visible "more" glyph. `onHold` marks the threshold (the haptic
  moment), `onOpen` hands out the flight.
- `MorphFlight.events`: a stream of `MorphFlightEvent` - launched,
  settled, closing, latched, landed, aborted - the seam for haptics and
  app-side choreography. Moments are queued in order and delivered a
  microtask later, so a listener attached in the same synchronous run
  as showMorph hears the launch, and a handler may close the flight
  from inside itself.
- A flight survives losing its source. When the tag leaves the tree
  mid-flight (a row archived from its own menu), the source rect
  freezes where it last stood, open content stays usable, and the
  close DISSOLVES - the container fades over the first half of its
  remaining travel, a pure function of the spring value from the
  moment the dissolve begins - instead of landing on whatever took the
  row's place. `MorphFlight.isSourceLost` and `dissolveOpacity` expose
  it.
- `overlay:` on `showMorph`, `showMorphSheet`, `showMorphDialog`,
  `showMorphMenu` and `MorphAnchor`: the overlay the shuttle renders
  in, for flights that must fly above chrome layered over a nested
  navigator (a floating bar over tab navigators). `morphAnchorRect` and
  `maybeMorphAnchorRect` take the same `overlay:`, so anchors are
  measured in the flight's space. The default stays the nearest
  overlay.
- `MorphTargetSpec.clipBehavior`: `Clip.none` lets content overflow the
  flying container - the vessel case above. The default is unchanged.
- `MorphSurface.onLongPress` and `MorphTapTarget.onLongPress`, with the
  same context-under-the-tag contract as `onTap`. `MorphTapTarget` now
  carries its tap and hold on its own semantics node: the exclusion
  under it had hidden the detector's actions from assistive tech.
- `Tug.glassSpring` is public - the button-scale glass spring, one home
  for every press in the widgets layer.
- Example: chapter 03, Hold to menu - a chat inside a nested navigator
  under a floating compose bar, with the overlay toggle, the events
  trail, and delete-from-the-menu dissolving the bubble.

## 0.4.0 - 2026-09-01

Material leaves the SDK. Flutter 3.47 split Material and Cupertino out
into standalone pub packages and deprecates the in-SDK copies in the
following stable; morph moves now. Nothing in the API changes shape -
only the package its Material types come from.

- morph imports `package:material_ui/material_ui.dart` instead of
  `package:flutter/material.dart`, across 56 files (10 lib, 18 test,
  26 example, 1 benchmark). Every `.dart` change is a single import
  line; no behavior, signature, name or default moved with it.
  BREAKING for consumers all the same: the standalone package is a
  full COPY of Material, not a re-export, so `material_ui.Theme` and
  `flutter/material.Theme` are DIFFERENT types and a `MorphTheme`
  reaches `Theme.of(context).extension<MorphTheme>()` in one world
  only. An app still on the in-SDK library either migrates with
  `dart fix --apply --code=migrate_design_widgets` or wraps the morph
  subtree in `MaterialUiCompatibilityBridge` - and note the bridge
  carries colors, density, platform and legacy localizations but NOT
  `extensions`, so a bridged app must also mount its `MorphTheme` in a
  legacy `Theme` of its own.
- `material_ui` `^1.1.0` is a direct dependency. `cupertino_ui` is
  transitive only: morph uses no SDK Cupertino at all, and
  `CupertinoMotion` comes from motor. Icons still resolve through
  `uses-material-design: true` - material_ui names the bare
  `MaterialIcons` family with no font package of its own.
- The Flutter constraint rises to `>=3.44.0`, material_ui's own floor,
  from the template default `>=1.17.0` it had carried since the split
  from tem_tools.

Known debt, deliberately left for a release of its own: the engine
still reaches for Material in four places - `MorphTheme` is a
`ThemeExtension`, the shuttle and the settled route page draw their
surface as a `Material`, both read `Theme.of(context).colorScheme`,
the barrier label comes from `MaterialLocalizations`, and
`showMorphDialog`/`showMorphSheet` adopt `DialogThemeData` and
`BottomSheetThemeData`. So `foundation.dart` carries material_ui to
every consumer, and the promise that the core blesses no design system
is not yet paid. The shuttle's `Material` is the expensive one: it is
what gives consumer dialog content its ink and default text styles, so
removing it is a change in behavior rather than a rename.

## 0.3.0 - 2026-08-29

The tactile pass. The widgets layer learns how a glass surface answers
a finger, and the engine grows the two things that pass needed: a
contour on the mass and one spring family shared by button and flight.
The `Tug` rewrite breaks API; everything else is additive.

- `Tug` is rebuilt on the liquid-glass button model. ONE degree of
  freedom, the raw pull on the chase spring, and every visual is a pure
  function of its (value, velocity). Travel is
  `reach * tanh(give * d / reach)` at give 0.05, so a few percent of
  the finger transmits and the asymptote sits a whole side away
  instead of a wall ten px out; the silhouette reads the raw pull at
  `stretch` gain plus its velocity times `jiggle`, saturated and
  volume-corrected, so the flesh answers more than the body moves;
  pointer-down LIFTS by `pressGrow` px per axis on a 363ms half-bounce
  spring (negative sinks, for ink). The gesture layer is a raw
  `Listener` outside the arena, so a selector or a scrollable inside a
  Tug still wins its own drag, and `vertical` gates both the input and
  scaleY - a bar pins its height. Past a 2:1 aspect the transmission
  fades by itself.
  BREAKING: `follow`, `lean`, `TugPull`/`onPull` and
  `MorphPieceChannel.contentScaleX/Y` are gone. Ink lies on the body
  and cannot slide, so content deforms with the mass 1:1. `dead` is
  gone and `cap` is now `reach`: both changed units in the rewrite, so
  the rename breaks stale call sites loudly instead of silently losing
  20x of their travel.
- `MorphPillHost`: the selection pill's physics as a host you draw
  from. Everything is px along the track axis; the owner maps
  positions through two callbacks (`hit` for taps, `snap` for
  carries), feeds a raw pointer stream in and paints where `centerX`
  and `resolveSize` say. The grab is the native model: the DOWN lifts
  the pill in place on its own item and carries it to a held one, the
  finger then moves it by its own displacement, confined to the slot
  span by the snap grid itself, and the commit waits for the release.
  Every release walks through one door, so an interrupted journey
  cannot strand the pill between slots. Chrome sympathy comes out as
  `chromeShift` and `chromeBreath` for the bar's piece channel.
- `MorphSquash`: deformation from force. Positions in, one signed
  deviation out (`scaleX = 1 + d`, `scaleY = 1 - d`, area held), so
  gaining speed stretches, braking squashes, and constant speed leaves
  the body alone. Only positions are sampled, so it composes with any
  driver; the intended one is a `MorphPieceChannel` write on a
  selection blob.
- `MorphStroke` on `MorphSkin.stroke`: the mass carries its own
  contour. The stroke follows the same traced path as the fill, so
  necks, deformations and flight blobs are outlined for free. Inner by
  contract (clip plus double width), painted after the tints, and
  outside the trace signature - a stroke change repaints without
  re-tracing. `MorphPiece.morphable` folds it into the tag shape and
  the flight frame lerps the side through the concentric rebuild, so a
  container launches outlined and its contour dissolves as the surface
  becomes the dialog.
- `MorphMotion.glass`: the material-unification profile, close 420ms
  at bounce 0.3 with a -1.5 hint. It is a FAMILY, not an instance -
  the same character calibrated for flight mass, while Tug keeps its
  own 363ms spring for finger-scale amplitudes. Sharing the literal
  button spring was tried and rejected by hand: its undershoot past
  the handoff latch turns into a ~22px landing kick over a flight's
  hundreds of pixels.
- `MorphSkin.contentFilterQuality`: content is rasterized once in its
  own space and the channel transform only resamples it, so glyphs
  stop shuffling under a moving matrix. The filter layer is retained
  per child - the raster reuse the knob buys.

Fixes:

- `Tug` forgets its pointer at dispose. A finger still down when the
  subtree left the tree used to report its up into disposed
  controllers. `chaseStiffness` now reaches a live chase instead of
  being captured once, and a negative `volume` can no longer drive a
  NaN into the channel.
- Frames resuming after a gap (a route covering the scene, the app
  backgrounded) finish the journey instead of integrating the whole
  gap in 240Hz substeps.
- A stroked flight drew its contour twice, the shuttle's surface and
  the skin's blob over the same pixels. The blob's box is clipped out
  of the skin's stroke and the replica flies unstroked, the way it
  already flies unshadowed.

## 0.2.0 - 2026-08-16

Two additions, both driven by tools that live over content instead of
covering it.

- `showMorph(modal: false)` (and the same flag on
  `MorphFlight.launch`): a NON-MODAL flight mounts no scrim at all, so
  the page underneath stays fully interactive while the surface hovers
  over it - a search field expanding over the list it filters. Nothing
  dims and there is no tap-outside dismissal (`barrierDismissible` has
  no barrier to attach to); Esc and the local history entry still
  close the flight. Modal stays the default.
- `MorphPiece.tint`: an ink wash that is PART of the skin instead of
  an overlay approximating it. Painted over the fill from the piece's
  RESOLVED geometry, so it stays glued to the mass through channel
  displacement, deflation and the landing squash; an airborne piece
  paints none. Clipped by the traced silhouette, so the neck to a
  neighbour stays untinted - ink soaks the body, not the bond. Content
  paints above it. Toggling only the tint is paint-only: no relayout,
  no re-trace, no subscription resync - a hover wash can flip per
  frame.

## 0.1.0 - 2026-08-09

The first tagged release.

- Engine (`package:morph/foundation.dart`): identity-based
  widget-to-overlay morphs on retargetable springs. `MorphTag` +
  `showMorph`/`showMorphDialog`/`showMorphSheet`, declarative
  `MorphAnchor`, `showMorphRoute` (the destination as a real Navigator
  route: live-state reparenting at settle, predictive back, drag on
  the settled page), `MorphSharedElement` (fade-through or solo
  flight), the displacement drag channel with commit heuristics,
  `MorphReveal` cascades, `MorphMotion` profiles and `MorphTheme`
  defaults. Flights and routes resolve the NEAREST overlay/navigator,
  so nested navigators keep their morphs inside themselves.
- The liquid skin: `MorphSkin`/`MorphPiece`/`MorphLink` fuse surfaces
  into one traced vector mass (no shaders), with flight necks, launch
  fellowships, per-cluster caching, an eval budget for bounded worst
  frames, and `MorphPieceChannel` - app-driven per-frame geometry with
  no widget rebuilds.
- Widgets (`package:morph/widgets.dart`): `showMorphMenu`,
  `MorphSurface`/`MorphTapTarget`, `SpringButton`, `Tug`,
  `ChaseSpring`.
- Example: a seven-scene tour of app mockups in a phone frame plus the
  sandbox playground; live at <https://tembeon.github.io/morph/>, API
  docs at <https://tembeon.github.io/morph/docs/>.
