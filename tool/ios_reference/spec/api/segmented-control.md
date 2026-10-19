# Segmented control - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UISegmentedControl` (UIControl), SwiftUI `Picker` + `.pickerStyle(.segmented)` (and iOS 27
`.pickerStyle(.tabs)`). morph: `MorphSegmentedControl`, `MorphSegment`, `MorphSegmentedControlAppearance`
(explicit, or from `MorphThemeData.appearances`). The lens motion (`MorphLensMotion`, `MorphLensTuning.segmented`)
is internal and shared with the tab bar. Passport: [../segmented-control.md](../segmented-control.md),
[../lens-and-flex.md](../lens-and-flex.md).

SDK 27.1 (iPhoneOS27.1.sdk): `UISegmentedControl.h` declares nothing after iOS 14; the lens is behaviour only.
The one iOS 27 item is SwiftUI `TabsPickerStyle` (`.tabs`, iOS 27.0). 27.1 changes nothing here.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `init(items:)` with titles (iOS 2) | title segments | `segments: List<MorphSegment>` | - | done |
| `init(items:)` with images, `insertSegment(with:image)`, `setImage` / `imageForSegment` (iOS 2) | image segments | none | missing | `MorphSegment.icon` (Widget) + `semanticLabel` |
| `insertSegment(...animated:)`, `removeSegment(at:animated:)`, `removeAllSegments()` (iOS 2) | animated mutation | rebuild with a new list (jumps) | native animation unmeasured | measure first |
| `setTitle(_:forSegmentAt:)`, `titleForSegment(at:)`, `numberOfSegments` | titles, count | `MorphSegment.title`, `segments.length` | - | keep |
| `selectedSegmentIndex`, `noSegment` (iOS 2) | selection or none | `selectedIndex: int?` (null hides the lens) | first selection from none appears at rest (native unmeasured) | done; measure the first selection |
| `isMomentary` (iOS 2) | highlight only while tracking | none | missing; native look unmeasured | `momentary` after a capture |
| `apportionsSegmentWidthsByContent` (iOS 5) | widths by content | `proportionalWidth` | distribution differs from the device (fidelity table) | fix the rule |
| `setWidth(_:forSegmentAt:)` (iOS 2; 0 = auto) | fixed width | `MorphSegment.width` | - | done |
| `setContentOffset(_:forSegmentAt:)` (iOS 2) | nudge content | none | - | skip (low) |
| `setEnabled(_:forSegmentAt:)` (iOS 2) | disable one segment | `MorphSegment.enabled` | label dims to `disabledOpacity`; UIKit's disabled color rule read, not ported | port after a device check |
| `isEnabled` (UIControl) | whole control | `onChanged: null`, `disabledOpacity` 0.5 | - | keep |
| `selectedSegmentTintColor` (iOS 13) | resting lens fill | `MorphSegmentedControlAppearance.lensColor` | no widget-level override | low |
| `backgroundColor` (UIView) | track | `appearance.trackColor` | no widget-level override | low |
| `setTitleTextAttributes(_:for:)` (iOS 5) | label style per state | `textStyle`, `selectedTextStyle` | no highlighted / disabled styles | keep |
| `setBackgroundImage(...)` (iOS 5) | track skin | `trackColor` only | images vs colors | skip |
| `setDividerImage(...)`, `setContentPositionAdjustment(...)` (iOS 5) | legacy skinning | none | - | skip |
| `.valueChanged` (on touch-up) | selection changed | `onChanged` | - | keep |
| per-segment accessibility (from title / image) | VoiceOver | one selectable button per segment | icon segments will need a label | with `icon` |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `Picker(_:selection:content:)` + `.segmented` (iOS 13) | picker over a `Hashable` tag | index-based `selectedIndex` | tag vs index | skip (index is UIKit's model) |
| `Picker(sources:selection:...)` (iOS 16) | mixed selection | none | - | skip (rare) |
| `Label(title, systemImage:)` content (iOS 14) | icon segment | none | as the image row | `MorphSegment.icon` |
| `.disabled(_:)` | disable | `onChanged: null` | - | keep |
| `.tint(_:)` | accent (effect on iOS 27 not checked) | `MorphThemeData.tint` not read | - | check on a device |
| `.controlSize(_:)` | height / text size | `appearance.height` 32 | one size measured | measure first |
| `TabsPickerStyle` / `.pickerStyle(.tabs)` (iOS 27) | tabs-looking picker | none | look and motion unknown | measure first |

## Not relevant for Flutter
- `segmentedControlStyle` (deprecated iOS 7), `NSCoding`, `UIAppearance` proxies, `UIBarMetrics`.
- `UIAction` segments (`init(frame:actions:)`, `insertSegment(action:)`, `setAction`, `segmentIndex(identifier:)`):
  target-action plumbing; one `onChanged(index)` covers it.
- `isSpringLoaded` (drag-and-drop hover), Mac idiom, per-segment accessibility selectors.

## morph-only API
- `MorphSegmentedControl.releaseSlop` (70, measured release bound), `maxTextScale` (1.4, no source).
- `MorphSegmentedControlAppearance.inset`, `.contentPadding`, `.height` ([layout]); `.liftedLensColor`,
  `.lensBorderColor`, `.shadowColor` (no-painter look, no source); contrast tables (read, unrendered).

## Flutter convention
- `CupertinoSlidingSegmentedControl<T>`: `children: Map<T, Widget>`, `groupValue: T?`, `onValueChanged`,
  `disabledChildren`, `proportionalWidth`, `isMomentary`, `thumbColor`, `backgroundColor`, `padding`.
- morph: `segments: List<MorphSegment>`, `selectedIndex: int?`, `onChanged` (null disables),
  `proportionalWidth`, per-segment `enabled`. Missing against Cupertino: Widget content (icons),
  `isMomentary`, widget-level colors.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | icon (image) segments | H | M | `MorphSegment.icon` + `semanticLabel` |
| 2 | `proportionalWidth` widths differ from the device by up to about 20 pt | M | S | fixed padding, spare room by label width; replay `segContent` |
| 3 | drag of the selected lens not replayed (fixtures exist) | M | S | replay seg5 drag / rubber band / overrun files |
| 4 | momentary mode | L-M | M meas. | `momentary` |
| 5 | text scale cap 1.4 has no source (UIKit may keep 13 pt and offer the large content viewer) | M | S meas. | measure Dynamic Type |
| 6 | first selection from none, animated insert / remove | L | M meas. | measure first |
| 7 | `.tabs` picker style (iOS 27) | L | L meas. | measure, then decide |
| 8 | widget-level lens / track colors | L | S | add if asked |

## Breaking changes before 1.0
- Done: `segments: List<String>` -> `List<MorphSegment>`, `selected` -> `selectedIndex` (`int?`), `sizeByContent`
  -> `proportionalWidth`, `MorphSegmentedStyle` -> `MorphSegmentedControlAppearance`, lens types internal.
- Open: `MorphSegment.icon` is additive; reserve it before 1.0 so `title` can become optional.

## Behaviour fidelity
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | missing | this page, SDK 27.1 | image segments, momentary, animated mutation |
| layout | unbacked | equal slots, height 32, inset 2, padding 16 [layout] (segmented-control.md); test/segmented_api_test.dart checks a fixed width | `proportionalWidth` (segmented_control.dart:381-392) scales the padding; device `segContent` (All / Unread messages / VIP) rests in slots of 60 / 231 / 70 pt, morph's rule gives about 71 / 212 / 78 with CoreText 13 pt widths (inferred); `maxTextScale` 1.4 (segmented_control.dart:67) no source |
| states | approx | lift replayed (test/lens_test.dart), disabled control replayed (test/disabled_test.dart, disabled.json) | disabled segment and no-selection appearance declared not measured (segmented_control.dart:48-51, 96-99) |
| transitions | approx | tap travel / lift / land replayed sim 60 Hz and device 120 Hz (lens_test: ios27{,-device}/lens segmented-seg2/seg3/seg5seg4/narrow-content files; center < 1.6 pt, sx < 0.012); title dim read (highlight_motion_test) | first selection from none jumps (declared); animated insert / remove missing |
| boundaries | measured | rubber band (12, 0.55) [device]; release bound 70 pt replayed (test/release_bounds_test.dart, tracking/release-outside.jsonl) | rubber band not replayed (drag fixtures unused) |
| configuration | missing | equal / proportional / fixed widths | momentary, image segments |
| events | replayed | selection on touch-up, release-outside outcomes replayed (release_bounds_test); no haptics on iPhone (read) | - |
| input | measured | tap on the selected segment replayed (test/lens_scrub_test.dart, segmented-seg3-tap-selected); controls_scroll_test | press-and-drag of the selected lens (pressDelay 40 ms, follow 0.225 / 1.0, release to the finger's slot) [device] not replayed: segmented-seg5-dragslow-from-selected, -release-choice-rubberband, -scrub-offset-overrun-back, -seg2-hold1200 are loaded by no test |
| mutation | missing | segments rebuilt in place, selection reconciled | animated insert / remove; a list change mid-drag unrecorded |
| accessibility | unbacked | Reduce Motion read (selection appears on the new segment), test/accessibility_test.dart; contrast tables read | text scale cap 1.4 no source; large content viewer not offered; per-segment Reduce Motion fade unrecorded |
| optics | unbacked | glass path measured: resting platter, lifted clear glass shrink 0.20, label 0.996 (glass-optics.md); refs `references/dark/segmented-*.png` | no-painter shadow blur 3 + 5 lift, 0.5 pt border and lifted fill (segmented_control.dart:126-128, 734-746) have no source; GRAD axis not reproduced |
| platform | unbacked | controls_platform_test (RTL first segment right, arrows), segmented_api_test (arrows skip a disabled segment) | RTL and keyboard not measured on iOS |
| performance | measured | Pixel 6a segmented scene, tool/bench/baseline.json 2026-10-12: liquid UI / raster p95 5.5 / 13.7 ms, 541 mW; flat 3.0 / 6.9 ms, 453 mW; iPhone 16 Pro (docs/performance.md) | baseline predates 2026-10-19 API changes |
