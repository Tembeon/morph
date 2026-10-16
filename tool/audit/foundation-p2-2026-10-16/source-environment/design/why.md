# P2 inherited context: source-control rationale

Scope: read-only investigation at `65b080d3a0ff178d57509f2f5fc9613ef88fafce`. This is a local source/history/doc investigation, synthesized by one investigator; no further delegation, tests, network or private Apple material. Only this evidence file was written.

## The question

Why does the old theme carrier exist, and which behavior should the new root menu preserve using public Flutter mechanisms without carrying the old flight engine into the prototype?

## The code in question

- `lib/src/themes.dart:9-159`: `morphCaptureThemes`, `morphDependOnThemes`, `MorphThemeCarrier`, `_CarriedThemes`.
- `lib/src/flight.dart:95-97,184-207`: initial capture/dependencies and post-frame refresh while source is active.
- `example/lib/proto/menu_route_probe.dart:140-146,891-923`: selected root Navigator and route content, without inherited-theme capture at the base revision. Confirmed by `/usr/bin/grep -n -E 'InheritedTheme|CapturedThemes|MorphThemeCarrier|morphCaptureThemes' ...` returning no matches.
- Complete history of `themes.dart` contains two commits: `43fe4d6df0e96d4f8fb416c3b5c0edb49c4ab2be`, `390a444d1dfd1b890851b218f17d6721e6c98514`. No PR or ticket identifiers occur in their full messages.

## What we found

- **[Direct]** The carrier exists to preserve the launching source's glass and inherited themes when the ghost/shuttle or settled route is built elsewhere. Commit `43fe4d6d` explicitly uses the popup-route precedent and says the source tag is the launching context. It also explicitly requires source theme changes to reach open content, fixed captured kinds, and last capture retention after source loss. This is recorded behavior rather than a guessed reason for a helper.
- **[Direct]** Its replacement of `MorphGlassCarrier` covered alerts, sheets, date picker and zoom replica, while context menu relied on its flight (`43fe4d6d` full commit message). Current callers remain in `flight.dart:95`, `widgets/sheet.dart:202`, `widgets/date_picker.dart:614`, `widgets/alert.dart:372,425`, `widgets/zoom_source.dart:15`. Thus the behavior is still used in the old product; unused prototype import would not make it globally dead.
- **[Direct]** The later text-specific branch exists because the shuttle's Material supplied a different body text style. `390a444d` says to restore source `DefaultTextStyle` below shuttle Material for ghosts/shared layers/context-menu previews, keep target styling independent, follow live source changes and retain after removal. `test/flight_source_text_style_test.dart` explicitly checks all these cases and tightly fitting text during opening/closing.
- **[Direct]** Fixed theme kinds were chosen to keep subtree shape and State (`themes.dart:47-52`; also `43fe4d6d`). Current `recapture` rejects changed list lengths or runtime-type order (`themes.dart:91-96`). This is a deliberate continuity tradeoff, not evidence that every possible inherited-topology change works.
- **[Direct]** The architecture plans replace carrier-at-route with SDK capture plus source dependency updates: `docs/architecture/foundation-review.md:72`. `foundation-sketch.md:414` schedules `MorphThemeCarrier` removal with the final vessel/flight removal, while `standalone-library-plan.md` unit 5.2 removes it from routes. Existing behavior is to be replaced, not removed without an equivalent.
- **[Direct]** The planned normal app puts `MorphTheme` above root Navigator (`foundation-review.md:34`; `foundation-sketch.md:29`). That makes the normal global theme available to every route, but the source-link design still explicitly includes captured themes (`foundation-review.md:50`). These statements are compatible: source-local overrides need transport, shared ancestors do not.

## What we can reasonably infer

- **[Inferred]** Given the explicit flight-specific Material reason in `390a444d` and a new widgets-only popup without that Material wrapper, copying `wrapText` as a separate universal channel appears unnecessary. `DefaultTextStyle` is itself an `InheritedTheme` in the installed public SDK (`widgets/text.dart:55`) and participates in ordinary SDK capture. Prove source-local default text style survives at the final builder location before deleting the old behavior in product code.
- **[Inferred]** Given the planned `MorphTheme` above root and the source-local override tests, the smallest useful boundary appears to be capture from the actual source to the selected root Navigator context. Capturing unrelated ancestors above that boundary would likely freeze otherwise-live app-wide state needlessly. The installed SDK requires `to` to be a real ancestor; the old helper's permissive walk-to-root fallback should not become a silent production contract.
- **[Inferred]** Given the explicit live-theme promise and SDK capture's frozen snapshot semantics, merely calling `InheritedTheme.capture` once at open appears insufficient. A source-lifetime dependency/invalidation bridge is still needed if the existing live behavior is preserved. This does not justify moving every inherited value or keeping the old carrier class.
- **[Inferred]** Given last-capture retention, source teardown should detach observation while retaining immutable captured widgets/data. A new route should not keep querying an inactive source context after removal. Reopening and concurrent routes need session/route-specific capture ownership, not a shared mutable capture overwritten by the newest source.

## SDK boundary and constraints

**Preserve**

- Source-local theme identity/value reaches root popup content, including nested Navigator launching sources.
- Live updates for an existing theme kind reach mounted content without remounting editor State, FocusNode or IME-owning subtree; theme invalidation is not a motion tick or a per-frame ancestor walk.
- Source loss retains the last valid capture while open content remains independently owned by the route.
- The source/target text distinction remains meaningful where source replicas and target content coexist; do not force target text to a source-only override beneath target styling.

**Change**

- Use public `InheritedTheme.capture(from: ..., to: selectedNavigator.context)` / `CapturedThemes.wrap`; prove the destination is an ancestor in actual nested/root cases. Avoid another custom nearest-type capture implementation without a demonstrated SDK gap.
- Add only the small source-lifetime observation mechanism needed to refresh capture on dependency changes. `capture` walks ancestors but does not subscribe to them (`widgets/inherited_theme.dart:87-129`); capture refresh must be scheduled safely relative to source dependency/build and route teardown.
- Let context already above the destination Navigator keep its normal inherited behavior. Treat non-theme channels as explicit requirements, not an implication of theme capture.

**Avoid**

- Do not import Material, Cupertino, old flight/shuttle/carrier or a new application-level registry into P2 to transport themes.
- Do not claim generic inherited-context cloning. SDK `MediaQuery` is an `InheritedModel`, `Directionality` an inherited widget, and `Localizations` a StatefulWidget/private scope: these are not `InheritedTheme` (`widgets/media_query.dart:1276`, `widgets/basic.dart:171`, `widgets/localizations.dart:479`). Arbitrary provider/inherited application services likewise are not transported by capture.
- Do not freeze root MediaQuery/settings automatically to source values: view size, insets, platform accessibility settings and route layout may need live root behavior. Test explicit policy separately.
- Do not recapture from a disposed/deactivated source; do not let stale post-frame refresh mutate a disposed/replaced route.
- Do not conflate zero rebuilds on motion frames with zero rebuilds for real inherited changes. Meaningful theme changes should update consumers.

**Risk**

- Changing the captured theme-kind structure can remount content in SDK wrappers. The old fixed-kind rule intentionally rejects such a structural change; no product decision/test in the examined record proves dynamic insertion/removal/reordering is supported. Preserve a bounded rule or characterize and document the stronger behavior before claiming it.
- Local source locale/RTL overrides do not follow automatically. Public `Localizations.override(context: source, child: ...)` can explicitly copy locale/delegates (`widgets/localizations.dart:523-544`), but it has a different lifetime/update/loading contract and adds Directionality from localized resources. This mechanism must not be silently sold as arbitrary inherited propagation.
- Existing source-theme tests exercise the flight engine and Material test app; they are rationale evidence, not coverage for the new root popup. Need WidgetsApp-only regressions on the new boundary.
- Theme capture, accessibility semantics, reduced-motion behavior and source geometry are separate claims. Success here does not close all P2 or certify device fidelity.

## Competing hypotheses

- **Hypothesis: this is all obsolete because the new MorphTheme is above root Navigator.** Evidence for: planned normal app topology. Counter-evidence: planned source-link captured themes, explicit source-local overrides and live update/retention behavior. Only the shared global portion becomes naturally inherited; local overrides remain a real use case.
- **Hypothesis: retain the entire old carrier unchanged because it solved theme continuity.** Evidence for: current product callers and tests. Counter-evidence: architecture explicitly selects SDK capture and deletion, and `wrapText` fixes a Material shuttle problem absent from the reduced route. Preserving behavior does not require retaining the implementation.

## What we do not know

- No historical test/decision in this scoped investigation resolves dynamic theme-kind insertion/removal while preserving editor State. Fixed-kind policy is recorded, general support is not.
- The record does not decide whether source-local locale/Directionality/MediaQuery overrides should cross the root popup boundary, nor what to retain after source removal for these non-theme values. Specify before asserting parity.
- No device/native accessibility or font behavior was inspected here; no new tests were run. This file is grounding for the parent's experiment.
- No PR IDs/ticket links occur in the two theme-file commits; no external discussion was searched. Human discussion preceding these commits is unknown.

## Sources consulted

- **Source control:** full `git log --follow -p`, recent log, blame for `lib/src/themes.dart`, two full commit messages/stats; current callers; `test/flight_theme_carry_test.dart`, `test/flight_source_text_style_test.dart`. No PR IDs to follow. No network in delegated scope.
- **Issue tracker:** not searched; no project ticket anchor and parent restricted this investigation to local git/source/docs. Product forcing-function discussion remains a gap.
- **Long-form documents:** local `foundation-review.md`, `foundation-sketch.md`, `standalone-library-plan.md` and current route protocols; no connected external document searched because scoped task is local.
- **Real-time chat:** not searched; no matching project chat source available in the task. Conversation rationale beyond visible user direction remains a gap.
- **Infrastructure observability:** not searched; this target is a local Flutter inherited-context transport prototype, no infrastructure dependency or incident anchor.
- **Error tracking:** not searched; no connected project error source or crash anchor. Current regressions are local widget tests, not a sourced incident history.
- **Product analytics:** not searched; no connected project warehouse/experiment anchor for theme transport. Cannot infer usage frequency from code.
- **SDK primary source:** installed Flutter `packages/flutter/lib/src/widgets/{inherited_theme,text,localizations,media_query,basic}.dart` read locally; no external citation/recollection substituted for actual SDK behavior.

## Confidence summary

The historical glass/theme continuity and Material-specific text rationale are direct and high confidence from two commit messages plus matching tests. The proposed narrow SDK boundary and separation from non-theme inherited values are well grounded in installed SDK source; exact refresh scheduling and changing theme topology still require prototype evidence. This investigation does not establish full context, accessibility or source geometry behavior.
