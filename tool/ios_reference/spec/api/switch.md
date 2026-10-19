# Switch - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UISwitch` (UIControl), SwiftUI `Toggle` + `.toggleStyle(.switch)`. morph: `MorphSwitch`,
`MorphSwitchAppearance` (explicit, or from `MorphThemeData.appearances`). The motion class
`MorphSwitchMotion` is internal. Passport: [../switch.md](../switch.md).

SDK 27.1 (iPhoneOS27.1.sdk): `UISwitch.h` declares nothing after iOS 14. SwiftUI `Toggle` adds nothing
after iOS 17 (`Toggle(_:systemImage:isOn:)`). `.checkbox` is unavailable on iOS. 27.1 changes nothing here.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `isOn` (iOS 2) | state | `MorphSwitch.value` | - | keep |
| `setOn(_:animated:)` (iOS 2), sends no action | programmatic change | a new `value` from the parent; knob and color run the tap springs | always animated; the native programmatic path is not recorded | keep; record `setOn(_:animated:)` |
| `.valueChanged` | user toggled | `onChanged` | - | keep |
| `isEnabled` (UIControl) | disabled | `onChanged: null`, `disabledOpacity` 0.5 | - | keep |
| `onTintColor` (iOS 5) | on track | `MorphSwitch.activeTrackColor`, `MorphSwitchAppearance.activeTrackColor` | - | done |
| (no property; a system fill) | off track | `inactiveTrackColor` (widget and appearance) | - | done |
| `thumbTintColor` (iOS 6) | knob | `MorphSwitchAppearance.thumbColor` | no widget-level override | add `MorphSwitch.thumbColor` |
| `onImage` / `offImage` (iOS 6) | no effect since iOS 7 | none | - | skip |
| `title`, `style`, `preferredStyle`, `UISwitch.Style` (iOS 14) | Mac checkbox | none (always sliding) | - | n/a |
| `accessibilityLabel` | VoiceOver label | `semanticLabel` | - | keep |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `Toggle(_:isOn:)`, `Toggle(isOn:label:)` (iOS 13), `Toggle(_:systemImage:isOn:)` (iOS 17) | switch with a label row | `MorphSwitch` (control only) | no label row | skip (row layout is `MorphListRow` or the app's) |
| `Toggle(sources:isOn:label:)` (iOS 16), `isMixed` | mixed state | none | missing; look unmeasured | skip until asked |
| `.toggleStyle(.switch)` / `.button` (iOS 15) | variant | switch only | `.button` belongs to glass buttons | skip |
| `.tint(_:)` (iOS 15) | on color, inherited | `activeTrackColor` per widget | `MorphThemeData.tint` does not reach the switch (UIKit keeps systemGreen, SwiftUI `.tint` recolors it) | decide before 1.0; low |
| `.disabled(_:)` | disable | `onChanged: null` | - | keep |
| `.controlSize(_:)` | size | fixed 63 x 28 | effect on the iOS 27 switch not measured | measure first |

## Not relevant for Flutter
- `init(frame:)` (frame size ignored), `NSCoding`, `UIAppearance` proxies.
- `UIBehavioralStyle` and the Mac checkbox (`title`, `.checkbox`).
- Target-action plumbing and accessibility selectors (Semantics covers them).

## morph-only API
- `MorphSwitchAppearance.disabledOpacity` (measured 0.5 layer), `light` / `dark` /
  `lightHighContrast` / `darkHighContrast` tables (contrast tables read from UIKit, unrendered).

## Flutter convention
- `CupertinoSwitch` (cupertino_ui 1.1.2): `value`, `onChanged`, `activeTrackColor`, `inactiveTrackColor`,
  `thumbColor`, `inactiveThumbColor`, `focusNode`, `autofocus`, `onFocusChange`, `thumbIcon`,
  `onLabelColor` / `offLabelColor` (drawn when `MediaQuery.onOffSwitchLabelsOf` is true).
- morph matches `value`, `onChanged`, null-to-disable, `activeTrackColor`, `inactiveTrackColor`. It lacks a
  widget `thumbColor`, `focusNode` / `autofocus`, and the On/Off Labels glyphs.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | On/Off Labels setting ignored (iOS draws on/off glyphs; Flutter exposes `MediaQuery.onOffSwitchLabelsOf`) | M | S-M meas. | capture the glyphs, then draw them on the flag |
| 2 | track color springs fitted but not replayed | M | S | replay the simulator `switch-*-tap` bg rows |
| 3 | `setOn(_:animated:)` never recorded | M | S meas. | record, then replay or fix the springs |
| 4 | widget-level `thumbColor` | L | S | add |
| 5 | `focusNode` / `autofocus` | L | S | add if asked |
| 6 | mixed state, `controlSize` | L | M meas. | skip until measured |

## Breaking changes before 1.0
- Done: `activeColor` -> `activeTrackColor`, `trackColor` -> `inactiveTrackColor`, `knobColor` -> `thumbColor`,
  `MorphSwitchStyle` -> `MorphSwitchAppearance`, motion class internal.
- Open: none. `MorphSwitch.thumbColor` is additive.

## Behaviour fidelity
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | missing | this page, SDK 27.1 headers | mixed state, controlSize, widget thumb color |
| layout | replayed | switch.md Spec (track 63 x 28, knob 37 x 24, travel 22 [layout]); test/switch_test.dart settled knob within 0.5 pt, lifted width rms < 0.3 / 0.8 | RTL mirroring unmeasured |
| states | replayed | test/disabled_test.dart (ios27-device/disabled/disabled.json, one 0.5 layer); lift in switch_test | contrast tables under accessibility |
| transitions | measured | knob tap and drag replayed (switch_test: ios27/controls switch-*-tap, ios27-device/controls switch-tb-*); small lens in test/flex_law_test.dart | track color springs 0.68 / 0.40 and `colorDelay` 0.09 not compared (rows exist in ios27/controls/switch-off-tap.jsonl); `setOn(_:animated:)` unrecorded, reuses the tap springs |
| boundaries | replayed | rubber band (12, 0.54), dead zone 5 pt / 0.1 s in switch-tb-a..e and left50 replays; test/release_bounds_test.dart (no release bound, 128.7 pt) | - |
| configuration | measured | default colors (switch.md Spec) | custom `thumbColor` under a lift (fades to a fifth on the flat path) unbacked |
| events | replayed | switch_test compares the final value with the recorded state of every device capture; test/haptics_test.dart | haptic moment read from UIKit, feel not checked |
| input | replayed | drag there-and-back, release outside (release_bounds_test); controls_scroll_test (no native compare) | second finger, scroll competition not recorded |
| mutation | unbacked | value from the parent mid-press reconciles after the frame (switch.dart) | no native recording |
| accessibility | missing | Reduce Motion read from UIKit (states.md), accessibility_test; contrast tables read, unrendered | On/Off Labels glyphs missing; device Reduce Motion pass pending |
| optics | unbacked | glass path measured: glass-optics.md lifted knob shrink 0.25, rim; refs `references/dark/switch-*.png` | no-painter knob shadow (switch.dart:360-362) and flat lifted rim (small_lens.dart:42-47) have no source |
| platform | unbacked | controls_platform_test (Space toggles, RTL) | RTL mirroring and keyboard not measured on iOS |
| performance | measured | Pixel 6a controls scene, tool/bench/baseline.json 2026-10-12: liquid UI / raster p95 10.2 / 12.0 ms, 589 mW; flat 8.7 / 7.0 ms, 441 mW | baseline predates 2026-10-19 API changes |
