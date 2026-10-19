# Alerts, action sheets and popovers - API parity (UIKit / SwiftUI iOS 27.1 vs morph)

Native: `UIAlertController` (`.alert` / `.actionSheet`), `UIAlertAction`, `UIAlertController.Severity`,
`UIPopoverPresentationController`, `UIPopoverArrowDirection`; SwiftUI `alert(...)`,
`confirmationDialog(...)`, `dialogIcon`, `dialogSuppressionToggle`, `ButtonRole`, `TextField` /
`SecureField` in an alert, `popover(isPresented:attachmentAnchor:arrowEdge:)`,
`presentationCompactAdaptation`. Catalog families: `alert`, `action-sheet`, `popover`.

morph (public, `lib/morph.dart`): `showMorphAlert`, `showMorphActionSheet`, `MorphAlertAction`,
`MorphAlertActionStyle`, `MorphAlertTextField`, `MorphAlertAppearance`. Internal (tests and example
only): `MorphAlertRoute`, `MorphAlertMotion`, `MorphAlertTuning`, `MorphPopoverMotion`,
`MorphPopoverTuning`, `MorphPopoverPlacement`, `MorphPopoverArrowDirection`, `morphPlacePopover`.
Passport: [../alerts.md](../alerts.md).

SDK 27.1 adds nothing to `UIAlertController.h`, `UIPopoverPresentationController.h` or the SwiftUI
dialog and popover modifiers. The 27.1 SwiftUI interface marks `dialogSeverity` and
`dismissalConfirmationDialog` unavailable on iOS.

API count. alert: 15 applicable, 10 covered, 2 partial, 3 gaps. action-sheet: 12 applicable, 6
covered, 1 partial, 5 gaps. popover: 14 applicable, 0 covered, 3 partial, 11 gaps.

## UIKit - alert
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UIAlertController(title:message:preferredStyle:)` (iOS 8) | create | `showMorphAlert` / `showMorphActionSheet` | none; the function picks the style | keep |
| `preferredStyle .alert` | centered alert | `showMorphAlert` | none | keep |
| `title`, `message` (settable while shown) | header text | `title`, `message` (`String?`, fixed at show) | partial: no change while shown | low |
| `addAction(_:)` / `actions` | buttons | `actions: List<MorphAlertAction>` | none | keep |
| `UIAlertAction(title:style:handler:)` | button | `MorphAlertAction(title:, style:, onPressed:)`; the Future completes with the chosen action | none; the handler runs after the dismissal, as UIKit | keep |
| `UIAlertAction.Style .default/.cancel/.destructive` | role | `MorphAlertActionStyle.normal/.cancel/.destructive` | none (`default` is a Dart keyword) | keep |
| `UIAlertAction.isEnabled` (settable live) | disabled button, toggled while shown | `enabled`, `enabledListenable` | none | keep |
| `preferredAction` (9) | accent action, Return key | `MorphAlertAction.isPreferred` | none; set per action, not per controller | rename (see breaking) |
| `addTextField(configurationHandler:)` / `textFields` (8, alert only) | inputs | `textFields: List<MorphAlertTextField>` (placeholder, controller, obscureText, keyboardType, onChanged, autofocus, autocorrect, enableSuggestions, textCapitalization, inputFormatters, semanticLabel) | partial: no `textInputAction` (return key type), `onSubmitted`, `autofillHints` (textContentType), clear button | add the four |
| `severity .default/.critical` (16) | critical styling | none | gap: the iPhone difference is unmeasured | measure first |
| `UIAlertAction` image | - | - | absent from the 27.1 public header | none |

## UIKit - action sheet
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `preferredStyle .actionSheet` | action list: a popover with a source, an alert on iPhone without one | `showMorphActionSheet` (anchor: popover; none: alert, cancel last) | none | keep |
| `popoverPresentationController.sourceView` / `sourceRect` (8) | source | `anchor: BuildContext` / `anchorRect: Rect` (global coordinates) | none | keep (see breaking) |
| `popoverPresentationController.sourceItem` (16) | bar item source | `anchor` = the item's context | none | keep |
| `UIAlertAction.Style.cancel` in a popover | not shown; a tap outside runs it | same (device capture) | none | keep |
| `popoverPresentationController.backgroundColor` (8) | popover fill | `MorphAlertAppearance.platterColor` | none | keep |
| `permittedArrowDirections` (8) | allowed arrow sides | none (`morphPlacePopover` tries all four) | gap | `permittedArrowDirections` on `showMorphActionSheet` |
| `arrowDirection` (read, 8) | the side chosen | none public (internal `MorphPopoverPlacement.arrowDirection`) | gap | expose with a general popover |
| `canOverlapSourceViewRect` (9) | may cover the source | none (the measured 3 pt overlap rule) | gap | skip (low) |
| `passthroughViews` (8) | views live under the popover | none | gap | skip (low) |
| `popoverLayoutMargins` (8) | screen margins | none (10 pt, measured) | gap | skip |

## Popover (UIKit and SwiftUI)
| API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `modalPresentationStyle .popover` with any view controller (8) | arbitrary content in an arrowed popover | none (the action sheet is the only popover) | gap | `showMorphPopover(context, anchor:/anchorRect:, builder:)` over the measured motion and placement |
| `sourceView` / `sourceRect` (8) | source | action sheet only | partial | with `showMorphPopover` |
| `sourceItem` (16) | bar item source | action sheet only | partial | same |
| `backgroundColor` (8) | fill | action sheet only (`platterColor`) | partial | same |
| `permittedArrowDirections` (8) | allowed sides | none | gap | with `showMorphPopover` |
| `arrowDirection` (8) | side chosen | none public | gap | same |
| `canOverlapSourceViewRect` (9) | may cover the source | none | gap | skip (low) |
| `passthroughViews` (8) | views live under the popover | none | gap | a non-modal flag (low) |
| `popoverLayoutMargins` (8) | screen margins | none | gap | skip |
| `adaptiveSheetPresentationController` (15) | the sheet a popover adapts to in compact width | none | gap | with the popover |
| delegate `adaptivePresentationStyle` -> `.none`; SwiftUI `presentationCompactAdaptation` (16.4) | keep a popover on iPhone, or adapt to a sheet | none | gap: UIKit adapts a general popover to a sheet on iPhone by default | choose the default when the popover lands |
| SwiftUI `popover(isPresented:/item:attachmentAnchor:arrowEdge:content:)` (13) | declarative popover | none | gap | `showMorphPopover` |
| `PopoverAttachmentAnchor .rect / .point` (13) | where on the source it attaches | none | gap | `anchorRect` covers `.rect` |
| `arrowEdge: Edge?` (13) | preferred arrow edge, nil for any | none | gap | with `permittedArrowDirections` |

## SwiftUI - alert and confirmation dialog
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `alert(_:isPresented:actions:)`, `(..., message:)`, `(..., presenting:)`, `alert(_:item:)` (15+) | declarative alert | `showMorphAlert` | none | keep |
| `confirmationDialog(_:isPresented:titleVisibility:actions:message:)`, `presenting:`, `item:` (15+) | action sheet | `showMorphActionSheet` | none | keep |
| `titleVisibility` (15) | show or hide the title | `title: null` hides it | partial: no `automatic` | keep |
| `ButtonRole .cancel / .destructive` (15) | role | `MorphAlertActionStyle.cancel / .destructive` | none | keep |
| `ButtonRole .confirm` (26) | the confirming action | `isPreferred` | none (different spelling) | keep (document) |
| `TextField` / `SecureField` in `alert` actions (16) | inputs | `MorphAlertTextField(obscureText:)` | counted with `addTextField` | as UIKit |
| `dialogIcon(_:)` (17) | icon in the dialog | none | gap: no iPhone capture with an icon | measure first |
| `dialogSuppressionToggle` (17) | "do not ask again" | none | gap | skip (low) |

## Not relevant for Flutter
- `alert(isPresented:error:)`, `alert(error:)` (27.0): Dart has no `LocalizedError`; pass `title` and `message`.
- `ButtonRole .close` (26): not an alert row role.
- `dialogSeverity`, `dismissalConfirmationDialog`: unavailable on iOS (27.1 interface).
- `UIPopoverBackgroundView` / `popoverBackgroundViewClass`, `prepareForPopoverPresentation`, `willRepositionPopoverTo`: custom chrome and rotation hooks; appearance colors and relayout cover them.
- Deprecated `UIAlertView`, `UIActionSheet`, `barButtonItem`, `popoverPresentationControllerShouldDismissPopover`.
- `LocalizedStringKey` / `LocalizedStringResource` overloads and scene-level dialog modifiers (macOS).

## morph-only API
- `useRootNavigator` (null: the root navigator, as UIKit presents an alert above everything).
- `MorphAlertAppearance` color tables, with `lightHighContrast` / `darkHighContrast`.
- Escape chooses cancel and Return the preferred action, also from the last text field (UIKit keyboard behaviour).
- A finger slides between buttons with a selection haptic (read from UIKit, notes private).

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | General popover with arbitrary content (`.popover`, SwiftUI `popover`) | med | M | `showMorphPopover` over `MorphPopoverMotion` + `morphPlacePopover` |
| 2 | Text field: return key type, `onSubmitted`, `autofillHints`, clear button | med | S | add to `MorphAlertTextField` |
| 3 | Popover arrow drawn by the glass painter; source tint dims while the popover is up | med (look) | M, measure first | renderer arrow, tint dim |
| 4 | `permittedArrowDirections` / `arrowEdge` | low-med | S | on `showMorphActionSheet` and the popover |
| 5 | A popover follows a moving source (UIKit repositions; morph keeps the rect taken at show) | low-med | S-M | re-measure the anchor each layout |
| 6 | Live `title` / `message` | low | S | listenable or rebuild |
| 7 | `severity .critical`, `dialogIcon`, `dialogSuppressionToggle` | low | S, measure first | skip until an iPhone capture |
| 8 | `canOverlapSourceViewRect`, `passthroughViews`, `popoverLayoutMargins` | low | S | skip |

Done: live enablement (`enabledListenable`); text field `onChanged`, `autofocus`, `autocorrect`,
`enableSuggestions`, `textCapitalization`, `inputFormatters`, `semanticLabel`; `useRootNavigator:
bool?`; the arrow names follow UIKit (`MorphPopoverArrowDirection { up, down, left, right }`,
`MorphPopoverPlacement.arrowDirection`), internal until the popover is public.

## Breaking changes before 1.0
- `MorphAlertAction.isPreferred` -> `preferred` (sits next to `enabled`; UIKit `preferredAction`).
  Optional, low value.
- `showMorphActionSheet(anchor:, anchorRect:)` vs `showMorphSheet(from: MorphSourceLink)`: accept
  `from:` too, so every presenter can name its source the same way. Additive.

## Behaviour fidelity

### alert
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | read | this page, 27.1 headers | 3 low gaps |
| layout | replayed | test/alert_layout_replay_test.dart: the three-action alert's platter and buttons rest on the recorded frames of 5 device and 3 simulator captures (0.5 pt; platter 264.0 = UIKit, header labels 20.33 / 18 as UILabel); test/alert_test.dart (order, 56 pt pitch, RTL); header gaps and `fieldTop` read from the device view dumps (passport) | `singleHeaderBottom` 3.67 has no capture; a row alert with a text field lays out 212 pt vs UIKit's 216 (buttons 4 pt high, passport); `fieldBottom` 4 is the dumps' collection view below the field cell, its use not replayed |
| states | replayed | test/disabled_test.dart (`ios27-device/disabled/disabled.json`); passport "Disabled actions" | pressed fill 0.4 measured, not replayed |
| transitions | replayed | test/alert_test.dart "alert motion replays" (sim + device `alert-present-dismiss.jsonl`: scale < 0.0015, dimming < 0.012 rms) | Reduce Motion present (accessibility) |
| boundaries | unbacked | test/alert_test.dart (overflowing alert scrolls and cancels the press) | `screenMargin` 20 (alert_motion.dart:47) is an engineering default; the scroll rule is the menu's (declared); the row-to-column switch for long titles is unmeasured |
| configuration | measured | passport "Spec - alert" (two actions in a row, cancel first; else a column, cancel last; a lone title regular) | widget tests assert morph's rules, not captures |
| events | measured | passport (handlers ~0.45 s after the touch-up); test/alert_test.dart (handler after the alert is gone, Escape, Return); test/alert_return_test.dart | the handler delay is not compared with a recording |
| input | replayed | test/alert_test.dart (device `alert-press`, `alert-tap`, `alert-lean`, `alert-slide`: lift < 0.35, lean < 0.06 pt rms) | - |
| mutation | approx | test/alert_api_test.dart (`enabledListenable`); test/alert_test.dart (keyboard) | enablement changes in one frame, UIKit animation unmeasured (declared in the passport); keyboard motion unmeasured |
| accessibility | unbacked | test/alert_test.dart (named route, large text); test/accessibility_test.dart | `maxTextScale` 2 (alert_motion.dart:50) is an engineering default; Increase Contrast title and message darkening not ported; Reduce Motion scale 1 read from UIKit, not recorded |
| optics | unbacked | passport; tool/ios_reference/references/alert-video (film, by eye); test/disabled_test.dart | the dark flat platter 0xCC282828 (alert.dart:205, 233) and the flat shadow colors (alert.dart:145, 212, 240) have no source; flat shadow sigma and offset are engineering defaults (alert_motion.dart:53, 56) |
| platform | measured | test/alert_test.dart (RTL, keyboard, 440 x 956) | phones only |
| performance | measured | tool/ios_reference/spec/lifecycle.md row 12; test/lifecycle_counts_test.dart; test/glyph_strikes_test.dart; passport performance trade (NEAR, declared) | 18-25 paints a frame of show and dismiss |

### action-sheet
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | read | this page | `permittedArrowDirections` |
| layout | replayed | test/alert_test.dart "placement matches UIKit" (`ios27/alert/placements.json`, 15 cases, 0.5 pt); test/alert_layout_replay_test.dart popover content on 5 device and simulator captures (0.5 pt) | the content rests 0.37 pt low and short of UIKit's 208.33 (207.96): the header is UIKit's 72, UIKit adds 0.33 below it (source unread) and the popover rests at scale 0.9998 |
| states | measured | passport "Spec - action sheet popover" | disabled actions are replayed for the alert only |
| transitions | replayed | test/alert_test.dart "popover motion replays" (sim + device `actionsheet-present-dismiss.jsonl`, < 0.007) | - |
| boundaries | replayed | `placements.json` corner-clearance and margin cases | no device placements |
| configuration | measured | passport (no source: an alert, cancel last) | - |
| events | replayed | test/alert_test.dart "a tap outside dismisses on the dismiss spring" (sim + device `ash-tap-out`) | - |
| input | replayed | test/alert_test.dart (device `ash-press`: no lift under a touch) | - |
| mutation | missing | - | the source rect is taken once (`showMorphActionSheet`); UIKit repositions the popover when its source moves |
| accessibility | read | alert_motion.dart (`MorphPopoverMotion` Reduce Motion: no shrink, read from UIKit) | not recorded |
| optics | unbacked | tool/ios_reference/references/alert-video | arrow outline hand-drawn (alert.dart:1192-1196), drawn flat outside the glass painter; source tint dimming missing |
| platform | measured | test/alert_test.dart (440 x 956 placements, 402 x 874 device motion) | phones only |
| performance | measured | test/lifecycle_counts_test.dart (`alert/flat action-sheet-dismiss`); lifecycle.md row 12 | - |

### popover
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | missing | this page | no general popover |
| layout | replayed | shared `morphPlacePopover`, `placements.json` | arbitrary content sizes unmeasured |
| states | missing | - | non-modal (passthrough) popover |
| transitions | replayed | shared `MorphPopoverMotion` (action-sheet rows) | - |
| boundaries | replayed | `placements.json` | - |
| configuration | missing | - | permitted directions, margins, overlap |
| events | missing | - | no general popover to dismiss |
| input | replayed | `ash-press`, `ash-tap-out` | - |
| mutation | missing | - | source tracking |
| accessibility | read | Reduce Motion read from UIKit | - |
| optics | unbacked | as action-sheet | arrow |
| platform | missing | - | compact adaptation to a sheet, UIKit's iPhone default for a general popover |
| performance | measured | action sheet only | - |
