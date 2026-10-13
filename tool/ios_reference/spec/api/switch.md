# Switch - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UISwitch` (UIControl), SwiftUI `Toggle` + `.toggleStyle(.switch)`. morph: `MorphSwitch`,
`MorphSwitchStyle`, `MorphSwitchMotion` (`MorphWidgetsTheme.switchStyle`). Passport: [../switch.md](../switch.md).

SDK 27.0 adds NOTHING to `UISwitch.h` after iOS 14 (no iOS 26/27 API). SwiftUI `Toggle` has no iOS 26/27
additions either; `.checkbox` toggle style is `iOS unavailable`.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `isOn` (iOS 2+) | state | `MorphSwitch.value` | name (Flutter uses `value`) | keep |
| `setOn(_:animated:)` (iOS 2+), does not send action | programmatic change, animated or not | a new `value` from the parent: knob and color run their springs (always animated) | no non-animated path | skip (state restore jumps are rare; reconsider if asked) |
| `.valueChanged` event | user toggled | `MorphSwitch.onChanged` (`ValueChanged<bool>?`) | - | keep |
| `isEnabled` (UIControl) | disabled | `onChanged: null` -> `MorphSwitchStyle.disabledOpacity` 0.5 | - | keep |
| `onTintColor` (iOS 5) | track color when on | `MorphSwitch.activeColor`, `MorphSwitchStyle.activeColor` | Flutter renamed this concept to `activeTrackColor` (CupertinoSwitch `activeColor` deprecated after 3.24) | rename -> `activeTrackColor` |
| (no UIKit property; off track is a system fill) | track color when off | `MorphSwitch.trackColor`, `MorphSwitchStyle.trackColor` | Flutter's current name is `inactiveTrackColor` (`trackColor` deprecated) | rename -> `inactiveTrackColor` |
| `thumbTintColor` (iOS 6) | knob color | `MorphSwitchStyle.knobColor` only | no widget-level override; "knob" vs UIKit/Flutter "thumb" | rename -> `thumbColor` (style) and add `MorphSwitch.thumbColor` |
| `onImage` / `offImage` (iOS 6) | track images (Apple docs: no effect since iOS 7; header silent) | none | - | skip (not drawn by the modern switch; confirm on device if ever asked) |
| `title` (iOS 14) | label next to a checkbox-style switch (Mac idiom only) | none (`semanticLabel` for screen readers) | - | skip (iOS sliding style draws no title; row label is the app's) |
| `style` / `preferredStyle`, `UISwitch.Style` `.automatic` / `.checkbox` / `.sliding` (iOS 14) | visual variant; `.checkbox` only for Catalyst Mac idiom | none (always sliding) | - | skip (`.checkbox` unavailable on iOS) |
| `accessibilityLabel` / `accessibilityValue` | VoiceOver | `MorphSwitch.semanticLabel`, toggled semantics | - | keep |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `Toggle(_:isOn:)`, `Toggle(isOn:label:)` (iOS 13) | switch + leading label row | `MorphSwitch` (control only) | no built-in label row | skip (labels are layout; `MorphListRow` hosts the row) |
| `Toggle(sources:isOn:label:)` (iOS 16), `ToggleStyleConfiguration.isMixed` | mixed state for several bindings | none (bool only) | no mixed state; native mixed look unmeasured | skip (rare on iOS); low |
| `.toggleStyle(.switch)` / `.button` (iOS 15) / `.checkbox` (macOS only) | variant | none | `.button` toggle = a glass button with selected state | skip here (belongs to glass-button family) |
| `.tint(_:)` (iOS 15; `SwitchToggleStyle(tint:)` deprecated) | on color | `activeColor` | same as `onTintColor` row | rename -> `activeTrackColor` |
| `.labelsHidden()` | hide the label | n/a (no label) | - | skip |
| `.disabled(_:)` | disable | `onChanged: null` | - | keep |
| `.controlSize(_:)` | size variant (effect on the iOS 27 switch not checked) | `MorphSwitchMotion.trackSize` fixed 63 x 28 | only one measured size | keep; measure if a size differs |

## Not relevant for Flutter
- `init(frame:)` frame size is ignored by UIKit; `NSCoding`; `UIAppearance` proxies.
- `UIBehavioralStyle` (Mac idiom), `UISwitch.Style.checkbox`, `title` (Mac checkbox only).
- target-action plumbing, accessibility selectors (Semantics covers them).

## morph-only API
- `MorphSwitchStyle.disabledOpacity` - keep (measured 0.5 layer).
- `MorphSwitchMotion` (pure motion; `trackSize`, `knobSize`, `liftedKnobSize`, `travel`, `deadZone`,
  `deadZoneWindow`, `colorDelay`) - keep; consider `knob*` -> `thumb*` with the style rename for one vocabulary.

## Flutter convention
- `CupertinoSwitch` (cupertino_ui 1.1.2): `value`, `onChanged` (null disables), `activeTrackColor`,
  `inactiveTrackColor`, `thumbColor`, `inactiveThumbColor`, `focusNode`, `autofocus`, `onFocusChange`,
  `thumbIcon`, `onLabelColor`/`offLabelColor`; `activeColor` and `trackColor` are deprecated (since 3.24).
- morph `value` / `onChanged` / null-to-disable match. morph's `activeColor` / `trackColor` are exactly the
  names Flutter deprecated - a Flutter dev migrating from CupertinoSwitch will hit them; rename.
- morph has no `focusNode` / `autofocus` (controls own their node; see docs/widgets.md) - low, add if asked.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | color names diverge from current Flutter (`activeColor`/`trackColor` deprecated there) | high (first thing devs type) | S | `activeTrackColor`, `inactiveTrackColor` |
| 2 | no widget-level thumb color (`thumbTintColor`) | med | S | `MorphSwitch.thumbColor`, style `knobColor` -> `thumbColor` |
| 3 | no `focusNode` / `autofocus` | low | S | add if requested |
| 4 | mixed state (`isMixed`) | low | M (unmeasured look) | skip until needed |
| 5 | non-animated `setOn(_:animated: false)` | low | S | skip |

## Breaking changes before 1.0
- `MorphSwitch.activeColor` -> `activeTrackColor`; `MorphSwitchStyle.activeColor` -> `activeTrackColor`
  (CupertinoSwitch / Material Switch name; UIKit `onTintColor`).
- `MorphSwitch.trackColor` -> `inactiveTrackColor`; `MorphSwitchStyle.trackColor` -> `inactiveTrackColor`.
- `MorphSwitchStyle.knobColor` -> `thumbColor` (UIKit `thumbTintColor`, Flutter `thumbColor`).
