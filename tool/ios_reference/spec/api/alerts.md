# Alerts - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIAlertController` (`.alert` / `.actionSheet`), `UIAlertAction`, `UIAlertController.Severity`,
`UIPopoverPresentationController` (action sheet with a source), `UIPopoverArrowDirection`; SwiftUI
`alert(...)`, `alert(isPresented:error:)`, `alert(error:)` (iOS 27), `confirmationDialog(...)`,
`dialogSeverity`, `dialogIcon`, `dialogSuppressionToggle`, `ButtonRole`, `TextField` / `SecureField`
in an alert, `popover(isPresented:attachmentAnchor:arrowEdge:)`. morph: `showMorphAlert`,
`showMorphActionSheet`, `MorphAlertRoute`, `MorphAlertAction`, `MorphAlertActionStyle`,
`MorphAlertTextField`, `MorphAlertStyle`, `MorphAlertMotion`, `MorphAlertTuning`,
`MorphPopoverMotion`, `MorphPopoverTuning`, `MorphPopoverPlacement`, `MorphPopoverArrowEdge`,
`morphPlacePopover`; engine `MorphTargetSpec.popover`. Passport: [../alerts.md](../alerts.md).

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UIAlertController(title:message:preferredStyle:)` (iOS 8) | create | `showMorphAlert(title:message:)` / `showMorphActionSheet(...)` | style chosen by function, not enum | keep (two functions read better in Dart) |
| `preferredStyle .alert` | centered alert | `showMorphAlert` | none | keep |
| `preferredStyle .actionSheet` | action list; popover with a source, alert-like on iPhone without one | `showMorphActionSheet` (anchor -> popover, none -> alert, cancel last) | none | keep |
| `title`, `message` (settable, iOS 8) | header text | `title`, `message` (String?) | not changeable while shown | keep (rebuild not needed in practice) |
| `addAction(_:)` / `actions` (iOS 8) | buttons | `actions: List<MorphAlertAction>` | none | keep |
| `UIAlertAction(title:style:handler:)` (iOS 8) | button | `MorphAlertAction(title:, style:, onPressed:)`; future completes with the chosen action | handler runs after the dismissal, as UIKit | keep |
| `UIAlertAction.Style .default / .cancel / .destructive` (iOS 8) | role | `MorphAlertActionStyle.normal / .cancel / .destructive` | `default` is a Dart keyword, hence `normal` | keep |
| `UIAlertAction.isEnabled` (iOS 8, settable live) | disabled button, can be toggled while shown (OK enabled after typing) | `MorphAlertAction.enabled` (const, fixed at show time) | can not enable an action live from a text field | add `MorphAlertAction.enabledListenable: ValueListenable<bool>?` (or let `enabled` take one) |
| `preferredAction` (iOS 9) | bold / accent action, Return key | `MorphAlertAction.isPreferred` | per action instead of per controller; several may be set | keep shape, assert at most one; see rename below |
| `addTextField(configurationHandler:)` / `textFields` (iOS 8) | input fields, `.alert` only | `textFields: List<MorphAlertTextField>` (`placeholder`, `controller`, `obscureText`, `keyboardType`) | missing `onChanged`, `autofocus`, `textInputAction`, `autocorrect`, `textCapitalization`, `autofillHints`, `onSubmitted`, Semantics label | add those fields (thin pass-through to the field) |
| `severity .default / .critical` (iOS 16) | critical styling (mainly macOS/Catalyst appearance) | none | | skip until an iPhone difference is measured (low) |
| `UIAlertAction` image | - | - | verified absent from the iOS 27 public header (no image on actions) | none |
| `popoverPresentationController.sourceView/sourceRect` (iOS 8) | action sheet source | `showMorphActionSheet(anchor: BuildContext)` / `anchorRect: Rect` | none | keep (see naming below) |
| `popoverPresentationController.sourceItem` (iOS 16) | bar item source | `anchor` = the item's context | none | keep |
| `permittedArrowDirections` (iOS 8) | allowed sides | none (`morphPlacePopover` tries all four) | can not force "below only" | add `permittedArrowEdges: Set<...>` to `showMorphActionSheet` and `morphPlacePopover` |
| `arrowDirection` (read, iOS 8) | side chosen | `MorphPopoverPlacement.edge` | naming differs (see breaking) | rename (see breaking) |
| `canOverlapSourceViewRect` (iOS 9) | may cover the source | none (measured 3 pt overlap rule only) | | skip (low) |
| `passthroughViews` (iOS 8) | views that stay interactive under the popover | none | | skip (low; a non-modal popover covers it) |
| `popoverLayoutMargins` (iOS 8) | screen margins | `MorphPopoverTuning.margin` (10, const) | not per call | skip (measured constant) |
| `popoverPresentationController.backgroundColor` (iOS 8) | popover fill | `MorphAlertStyle.platterColor` | | keep |
| `UIModalPresentationStyle.popover` with arbitrary content (iOS 8) | any view controller in an arrowed popover | none in the widget layer; engine `MorphTargetSpec.popover` (no arrow, not glass-measured) | general popover missing | add `showMorphPopover(context, anchor:, builder:)` reusing `MorphPopoverMotion` + `morphPlacePopover` |
| `presentationControllerDidDismiss` (iOS 13) | dismissed | `Future<MorphAlertAction?>` completes (null when popped otherwise) | | keep |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `alert(_:isPresented:actions:message:)`, `alert(_:isPresented:presenting:)`, `alert(_:item:)` (iOS 15+) | declarative alert | `showMorphAlert` | same as UIKit row 1 | keep |
| `alert(isPresented:error:actions:)` (iOS 15) / `alert(error: Binding<E?>)` (iOS 27, NEW) | title and message from an error | none | | skip (Dart: pass `title`/`message` from the error) |
| `confirmationDialog(_:isPresented:titleVisibility:actions:message:)` (iOS 15) | action sheet | `showMorphActionSheet` | `titleVisibility` (SwiftUI hides the title by default on iPhone) | keep (`title: null` hides it) |
| `ButtonRole .cancel / .destructive` (iOS 15) | role | `MorphAlertActionStyle.cancel / .destructive` | none | keep |
| `ButtonRole .confirm` (iOS 26, NEW) | the confirming action (accent fill in an alert) | `MorphAlertAction.isPreferred` | concept equal, different spelling | keep (document the mapping) |
| `ButtonRole .close` (iOS 26, NEW) | close (x) button role | none | not a row role in alerts | skip |
| `TextField` / `SecureField` in `alert` actions (iOS 16) | inputs | `MorphAlertTextField(obscureText:)` | see UIKit text field row | add fields |
| `dialogSeverity(.automatic/.critical)` (iOS 17) | severity | none | | skip (same as `severity`) |
| `dialogIcon(_:)` (iOS 17) | icon in the dialog | none | iPhone alert shows no icon in the measured layout | skip (low) |
| `dialogSuppressionToggle` (iOS 17) | "Do not ask again" checkbox | none | macOS-style control | skip (low) |
| `popover(isPresented:attachmentAnchor:arrowEdge:content:)` (iOS 13; `arrowEdge` optional) | general popover | none (see UIKit row) | | add `showMorphPopover` |
| `presentationCompactAdaptation(.popover)` (iOS 16.4) | keep a popover on iPhone instead of a sheet | n/a (morph popovers are always popovers) | | keep |

## Not relevant for Flutter
- `UIPopoverBackgroundView` / `popoverBackgroundViewClass`: custom chrome classes; style colors cover it.
- `UIPopoverPresentationControllerDelegate.willRepositionPopoverTo`: rotation repositioning, Flutter relayouts.
- Deprecated `UIAlertView` / `UIActionSheet` / `barButtonItem` / `popoverPresentationControllerShouldDismissPopover`.
- `LocalizedStringKey` / `LocalizedStringResource` overloads: Dart strings are already localized by the app.
- Scene-level `dialogIcon` / `dialogSeverity` / `dialogSuppressionToggle` overloads (macOS scenes).

## morph-only API
- `MorphAlertRoute` public constructor: lets an app push the alert itself - keep.
- `useRootNavigator` - keep (Flutter routing), see breaking for the default.
- `MorphAlertStyle` color table (`platterColor`, `preferredColor`, `disabledLabelColor`, ...) - keep.
- `MorphAlertMotion` / `MorphAlertTuning` / `MorphPopoverMotion` / `MorphPopoverTuning` / `morphPlacePopover` / `MorphPopoverPlacement`: measured motion and placement as pure code - keep; `morphPlacePopover` is the basis for a general popover.
- Escape = cancel, Return = preferred: keyboard behaviour from UIKit - keep.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | Live `isEnabled` (enable OK when the field is valid) | high | S | `MorphAlertAction.enabledListenable` (or `enabled` as `ValueListenable<bool>`), rebuild only the button |
| 2 | Text field configuration (`onChanged`, `autofocus`, `textInputAction`, `onSubmitted`, `autocorrect`, `textCapitalization`, `autofillHints`) | high (login / rename prompts) | S | add the fields to `MorphAlertTextField` |
| 3 | General popover with arbitrary content (`.popover`, SwiftUI `popover`) | med | M | `showMorphPopover(context, anchor:/anchorRect:, builder:, permittedArrowEdges:)` on `MorphPopoverMotion` + `morphPlacePopover` |
| 4 | `permittedArrowDirections` | low-med | S | `permittedArrowEdges` on `showMorphActionSheet` / `morphPlacePopover` |
| 5 | `severity .critical` / `dialogSeverity` | low | S | skip until a measured iPhone difference |
| 6 | `passthroughViews`, `canOverlapSourceViewRect` | low | S | skip |
| 7 | `dialogIcon`, `dialogSuppressionToggle` | low | S | skip |

## Breaking changes before 1.0
- `MorphPopoverArrowEdge` (`bottom/top/left/right`) names the POPOVER edge that carries the arrow; UIKit `UIPopoverArrowDirection` names the arrow's direction (`up/down/left/right`) and SwiftUI `arrowEdge: Edge` names an edge again. Proposal: `MorphPopoverArrowEdge` -> `MorphPopoverArrowDirection { up, down, left, right }` (`top` -> `up`, `bottom` -> `down`) and `MorphPopoverPlacement.edge` -> `arrowDirection`, mirroring UIKit's `arrowDirection`; unambiguous and matches `permittedArrowDirections`.
- `MorphAlertAction.isPreferred` -> `preferred` (sits next to `enabled`; UIKit `preferredAction`). Optional, low value.
- `showMorphAlert` / `showMorphActionSheet` `useRootNavigator: bool = true` -> `bool?` defaulting to `morphPresentationNavigatorOf`, as `presentMorphSheet` does.
- `showMorphActionSheet(anchor: BuildContext?, anchorRect: Rect?)` vs `presentMorphSheet(from: Object?)` (MorphTag id): consider accepting `from:` (MorphTag id) too, so every presenter names its source the same way; keep `anchor`/`anchorRect` (Flutter `MenuAnchor` vocabulary). Additive, not breaking.
