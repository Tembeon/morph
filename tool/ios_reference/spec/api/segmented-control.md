# Segmented control - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UISegmentedControl` (UIControl), SwiftUI `Picker` + `.pickerStyle(.segmented)` (and the new `.tabs` picker style).
morph: `MorphSegmentedControl`, `MorphSegmentedStyle`, `MorphLensMotion`, `MorphLensSlot`, `MorphLensTuning`
(`MorphWidgetsTheme.segmented`). Passport: [../segmented-control.md](../segmented-control.md),
[../lens-and-flex.md](../lens-and-flex.md).

SDK 27.0 adds NOTHING to `UISegmentedControl.h` after iOS 14 (no iOS 26/27 API; the Liquid Glass lens is
behaviour only). The only iOS 27 item in this family is SwiftUI `TabsPickerStyle` (`.tabs`).

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `init(items:)` (iOS 2+) | segments from `[String or UIImage]` | `MorphSegmentedControl.segments` (`List<String>`) | titles only, no images | reshape -> `List<MorphSegment>` (see breaking) |
| `init(frame:actions:)`, `insertSegment(action:at:animated:)`, `setAction(_:forSegmentAt:)`, `actionForSegment(at:)`, `segmentIndex(identifier:)` (iOS 14) | a `UIAction` per segment (title + image + handler) | none | per-segment handler | skip (Flutter idiom: one `onChanged(index)`; title/image covered by `MorphSegment`) |
| `insertSegment(withTitle:at:animated:)` / `with image:` / `removeSegment(at:animated:)` / `removeAllSegments()` (iOS 2+) | mutate segment list, optionally animated | rebuild with a new `segments` list | no animated insert/remove; native animation unmeasured | skip until measured (declarative list is the Flutter way); low |
| `setTitle(_:forSegmentAt:)` / `titleForSegment(at:)` (iOS 2+) | title per segment | `segments[i]` | - | keep |
| `setImage(_:forSegmentAt:)` / `imageForSegment(at:)` (iOS 2+) | image segment (image OR title) | none | no icon segments | add `MorphSegment.icon` (Widget) |
| `numberOfSegments` (iOS 2+) | count | `segments.length` | - | keep |
| `selectedSegmentIndex` (iOS 2+) | selected index, settable | `MorphSegmentedControl.selected` (int, clamped) | name differs | rename -> `selectedIndex` |
| `UISegmentedControl.noSegment` (-1) (iOS 2+) | nothing selected | none (index clamped into range) | cannot show "no selection"; Cupertino `groupValue` is nullable too | add: `selectedIndex` becomes `int?`, null = no lens |
| `isMomentary` (iOS 2+) | segment highlights only while tracking, fires action, no persistent selection | none | missing; lens behaviour in momentary mode unmeasured | add `isMomentary` (needs a capture) |
| `apportionsSegmentWidthsByContent` (iOS 5) | widths proportional to content | `MorphSegmentedControl.sizeByContent` | name differs from UIKit and Cupertino (`proportionalWidth`) | rename -> `proportionalWidth` |
| `setWidth(_:forSegmentAt:)` / `widthForSegment(at:)` (iOS 2+; 0 = auto) | fixed width for one segment | none | missing | add `MorphSegment.width` (double?, null = auto); low |
| `setContentOffset(_:forSegmentAt:)` (iOS 2+) | nudge content inside a segment | none | - | skip (wrap the segment content in `Padding`/`Transform`) |
| `setEnabled(_:forSegmentAt:)` / `isEnabledForSegment(at:)` (iOS 2+) | disable one segment | none (only whole control via `onChanged: null`) | missing; disabled-segment look unmeasured (states.md) | add `MorphSegment.enabled` (needs a capture) |
| `isEnabled` (UIControl) | disable whole control | `onChanged: null` -> `MorphSegmentedStyle.disabledOpacity` 0.5 | - | keep |
| `selectedSegmentTintColor` (iOS 13) | resting lens fill | `MorphSegmentedStyle.lensColor` | name | keep in style; add widget-level `selectedColor` override? low (switch/slider have widget-level color overrides, segmented has none) |
| `backgroundColor` (UIView) | track fill | `MorphSegmentedStyle.trackColor` | - | keep |
| `setTitleTextAttributes(_:for:)` (iOS 5) | label attributes per control state (.normal/.selected/.highlighted/.disabled) | `MorphSegmentedStyle.textStyle`, `.selectedTextStyle` | no highlighted/disabled variants | keep (normal + selected cover the native look; disabled is the 0.5 layer) |
| `setBackgroundImage(_:for:barMetrics:)`, `setDividerImage(...)`, `setContentPositionAdjustment(...)`, `UISegmentedControl.Segment` (iOS 5) | legacy skinning by images | none | - | skip (pre-iOS 7 skinning; draws nothing like the Liquid Glass lens) |
| `.valueChanged` event (UIControl) | selection changed (on touch-up) | `MorphSegmentedControl.onChanged` (`ValueChanged<int>?`) | - | keep |
| `isSpringLoaded` (UISpringLoadedInteractionSupporting, iOS 11) | drag-and-drop hover selects a segment | none | - | skip (drag-and-drop spring loading is iPad-centric; low) |
| `accessibilityLabel` per segment (via title/image) | VoiceOver label | `Semantics(label: segments[i])` | icon segments will need a label | add `MorphSegment.semanticLabel` with `icon` |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `Picker(_:selection:content:)` + `.pickerStyle(.segmented)` (iOS 13) | segmented picker over any `Hashable` tag | `MorphSegmentedControl` (int index) | value-typed selection (`.tag(_:)`) vs index | skip (index matches UIKit; `List<T>` lookups are a one-liner for the app); low |
| `Picker(sources:selection:...)` (iOS 16) | mixed selection across several bindings | none | - | skip (rare) |
| `Label(title, systemImage:)` as picker content (iOS 14) | icon + title segment | none | same as UIKit image row | add `MorphSegment(title, icon:)` |
| `.disabled(_:)` | disables the picker | `onChanged: null` | - | keep |
| `.controlSize(_:)` (`.mini ... .extraLarge`) | segmented height/text size | `MorphSegmentedStyle.height` (32) | only one measured size | skip until other sizes are measured; low |
| `.tint(_:)` | accent tint (effect on the iOS 27 segmented picker not checked) | `lensColor` | - | keep; verify on device before mapping |
| `TabsPickerStyle` / `.pickerStyle(.tabs)` (iOS 27, NEW) | iOS 27 tabs-looking picker | none | look and motion unknown | measure first (likely shares the tab bar lens: `MorphLensTuning.tabBar`) |

## Not relevant for Flutter
- `segmentedControlStyle` / `UISegmentedControl.Style` (deprecated iOS 7).
- `NSCoding` / `init(coder:)`, `UIAppearance` proxies, `UIBarMetrics` variants.
- `UIBehavioralStyle` / Mac idiom, `UIAction` identifiers, target-action plumbing.
- Per-segment `accessibility*` selectors (Semantics covers them).

## morph-only API
- `MorphSegmentedControl.releaseSlop` (70, measured release bound) - keep, it documents a measurement.
- `MorphSegmentedControl.maxTextScale` (1.4) - keep.
- `MorphSegmentedStyle.inset`, `.contentPadding`, `.liftedLensColor`, `.lensBorderColor`, `.shadowColor`,
  `.disabledOpacity`, `.height` - keep (look tables; `UIView` has no equivalents).
- `MorphLensMotion`, `MorphLensSlot`, `MorphLensTuning` (`.segmented`, `.tabBar`) - keep (pure motion API,
  shared with the tab bar; no native public counterpart).

## Flutter convention
- `CupertinoSlidingSegmentedControl<T>`: `children: Map<T, Widget>`, `groupValue: T?`,
  `onValueChanged: ValueChanged<T?>`, `disabledChildren: Set<T>`, `proportionalWidth`, `isMomentary`,
  `thumbColor`, `backgroundColor`, `padding`.
- morph: `segments: List<String>`, `selected: int`, `onChanged: ValueChanged<int>?` (null disables).
  `onChanged` + null-to-disable matches morph's other controls and Material; Cupertino's `onValueChanged` is
  required (no whole-control disable). Index-based selection is UIKit's model; keep it, but allow null (no
  selection) like `groupValue`, and take per-segment `enabled` (Cupertino `disabledChildren`), `isMomentary`
  and `proportionalWidth` names a Flutter dev already knows.
- Missing vs Cupertino: Widget segment content (icons), `thumbColor` / `backgroundColor` widget-level overrides.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | icon (and icon + title) segments | high | M (layout + label width cache must take a Widget; lens unaffected) | `MorphSegment(title, {icon, semanticLabel})` |
| 2 | no-selection state (`noSegment`) | med | S (lens hidden / rest) - lens appearance from none unmeasured | `selectedIndex: int?` |
| 3 | per-segment enabled | med | M (disabled segment look needs a device capture) | `MorphSegment.enabled` |
| 4 | momentary mode | low-med | M (capture native momentary highlight first) | `isMomentary` |
| 5 | per-segment fixed width | low | S | `MorphSegment.width` |
| 6 | `.tabs` picker style (iOS 27) | low (new, unknown adoption) | L (measure) | measure, then decide |
| 7 | widget-level color override (`selectedSegmentTintColor`) | low | S | `selectedColor` / `trackColor` overrides like switch/slider |

## Breaking changes before 1.0
- `segments: List<String>` -> `segments: List<MorphSegment>` (const `MorphSegment(String title)` keeps the simple
  case short); needed for icons, per-segment enabled/width/semantics without parallel lists.
- `selected` -> `selectedIndex` (`int?`, null = UIKit `noSegment`); mirrors `selectedSegmentIndex`.
- `sizeByContent` -> `proportionalWidth` (Cupertino name; UIKit `apportionsSegmentWidthsByContent`).
