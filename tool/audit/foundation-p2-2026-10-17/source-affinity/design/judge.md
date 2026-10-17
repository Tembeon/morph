# Source affinity synthesis

Fresh read-only judge, 2026-10-17, against `d9973893a0cd91c7eff6c68efe6571594033c81c`. Read both complete candidates, task/ground/how/checklist, architect and arena instructions, actual source and corrected three-failure baseline. This is an independent run of the inherited model, not multi-model evidence. No source edit, test run, device or GUI work was performed.

## Caller contract first

The public GlobalKey State survives a source move. Its observations always describe its current attachment, and `open(): ProbeMenuRoute` remains synchronous. A caller does not coordinate retirement or wait for an old popup:

```dart
final oldPopup = source.currentState!.open();
moveSameGlobalKeyToOtherRoot();
await nextFrame();
final newPopup = source.currentState!.open();
```

The old popup stays in root A with its content, SDK policy, route clock and model. The new popup is a separate lifetime in root B. Closing or disposing A never hands its model to B or resets B. Returning B → A later creates another fresh lifetime; the first A popup never reacquires the source. Moving between nested Navigators under one unchanged root/View preserves the session, model and route. Page currentness remains a separate input policy.

A source whose own View differs from the selected root overlay View cannot present in this fixed-space experiment. Explicit `open()` throws a descriptive StateError before any push; raw and semantic acquisition decline without creating a popup. No implicit cross-View conversion or app-managed cleanup API is introduced.

## Comparison and decision

Scores are 0–3 per rubric item and assess the candidate shape before the grafts below.

| Criterion | A: rotate session | B: keyed host + handle |
| --- | ---: | ---: |
| Correct affinity boundary | 3 | 3 |
| Public SDK mechanisms | 3 | 3 |
| Model/time/lease continuity | 3 | 3 |
| Reentrant lifetime/input safety | 2 | 3 |
| Minimal caller/internal surface | 3 | 2 |
| Total | 14 | 14 |

Choose **A as the base**, using the tie-break of the smaller sufficient ownership boundary. Both hide attachment changes from the caller. A session is already the complete attachment lifetime, so adding B's handle plus keyed source host duplicates a lifecycle owner without reducing the facade's vsync or synchronous-command duties. B's stronger treatment of deactivation and source-owned retirement is required as a graft, not optional prose. A is acceptable only with those explicit amendments.

The corrected baseline reproduces all three concrete faults: the moved source still exposes the old root's route; old-root closing hands back to the moved source; old popup accepts the new View's input. Geometry transforms are outside these failures and remain a documented boundary.

## Required private shape

Keep one immutable affinity value and use session object identity as the callback generation token:

```dart
final class _MenuAffinity {
  final NavigatorState navigator;
  final FlutterView sourceView;
  final FlutterView presentationView;
  bool get canPresent;
  bool sameSpace(_MenuAffinity other);
}

class ProbeMenuSourceState extends State<ProbeMenuSource>
    with TickerProviderStateMixin {
  _MenuSession? _session;
  bool _elementActive = true;
  _MenuAffinity _readAffinity();
  void _refreshAttachment();
  _MenuSession _sessionForCommand();
  bool _isAttached(_MenuSession token);
  bool _sourceCanAcquire(_MenuSession token, {
    ModalRoute<Object?>? coveredRoot,
  });
  ProbeMenuRoute _prepare(_MenuSession token, {bool reserve = false});
  void _semanticOpen(_MenuSession token);
}

class _MenuSession {
  final _MenuAffinity affinity;
  bool Function()? sourceAttached;
  bool Function({ModalRoute<Object?>? coveredRoot})? sourceEligible;
  VoidCallback? present;
  ProbeMotionClock? sourceClock;
  bool land(ProbeMenuRoute route, double localTime);
  void detachSource();
}
```

These are contract signatures, not a requirement to duplicate existing declarations. Do not add a mount/host/controller layer or a second mutable current root/View. `canPresent` derives from `identical(sourceView, presentationView)`; equality compares all three object identities. Read the actual overlay context's View, not a guessed Navigator viewId. The session's pointer filter is pinned to `presentationView.viewId` for its whole lifetime; remove mutable `updateSourceView` state.

Construct the initial session after dependencies are available. A different root, source View or overlay View seals the previous session and creates a fresh one. Theme/MediaQuery changes do not rotate. TickerProviderStateMixin permits sequential source tickers over one public State lifetime; dispose the old source clock before creating the new one, with at most one live source clock. Old route clocks remain provided by their original Navigators.

## Accepted grafts and lifetime resolution

1. **From B: explicit active-element boundary.** `deactivate` marks ancestor reads unavailable; `activate` restores availability. Same-frame deactivation alone does not permanently detach or cancel a valid same-root session. Recompute affinity on dependency refresh and command boundaries. Live source authority checks fail closed while inactive without ancestor lookups. This is a framework element-validity fact, not another synchronized attachment identity.

2. **From B: source-owned tail abandonment is explicit.** If the old source already owns the model when its physical attachment changes, stop its source clock and abandon that model lifetime. Do not migrate, copy, reset, force sample to rest, or start an invisible retirement ticker. It may remain numerically unsettled. Any retained old closing route finishes its existing SDK projection without reacquiring the model. The report and test must call this abandoned, not settled. A same-root nested relocation does not trigger this rule. This resolves the candidates' open question without a human checkpoint because there is no old compatible physical source to render that tail.

3. **From both, made mandatory: immediate seal and safe retirement.** Clear source context callbacks and source clock synchronously, revoke the captured sequence's authority, and defer observable cancellation/route retirement beyond the dependency-change/build stack. Sealing must not emit observations, notify frames, change route stage/projection, or mutate Navigator history. Preserve pending cancellation through command unwind until the deferred safe seam; `_drainPointerCancel` must not bypass this seam just because model depth reaches zero. Retirement captures only the old session and is idempotent. Avoid disposing frame notifiers while an old painter/notification still holds them.

4. **From both: captured callback tokens.** A build captures `final session = ...` for its painter, raw Listener, GestureDetector and Semantics closure. Installed `present`, sourceEligible and sourceAttached closures capture that same token. Stale callbacks validate token identity and live affinity; none resolves a mutable State field to perform a new session's work. Public open can refresh at a safe command boundary; a stale source callback must simply decline. Detaching the old session releases all source context closures, while route-owned content callbacks remain because its popup is still alive.

An old **shown route-owned popup** remains independently shown and dismissible under its original SDK policy after source loss. Its original-View raw menu input remains enabled; only stale held source input is canceled. A new View cannot mutate it. Do not remove the old global pointer router until that old session is unused. Normal old closing completes all model channels on its old route clock, with no landing because source authority was permanently cut.

An old **hidden preparation** has no independently shown content. Cancellation must clear pending hold/open and drive that route-owned model to genuine rest, then remove/complete the exact old route through the existing finite closing path. A covered preparation must not pop the cover. An old held-reopen reservation is retired exactly once and cannot be promoted after attachment loss; close already committed work on its existing route owner under source-loss rules. A source-owned reserved model follows the abandoned-source-owned rule instead of inventing a driver. No old reservation may push or pop the new root.

`land` validates attached current-token authority and actual pinned presentation immediately before resuming/transferring. Recheck after user/model callbacks before publishing hand-back or notifier updates. A failed guard leaves owner/time unchanged; it does not transfer and then merely suppress evidence. Reentrancy must never choose a newer session via an old route. A constructor-injected factory reentering open during unpublished session creation may receive an explicit transition StateError; never return the detached old session or an incompletely constructed one.

## Verification gates

The parent owns implementation and serial test runs. Required cases are:

- Retained GlobalKey State moves between two real independent root Navigators; old/new popup lifetimes overlap and neither disposal resets the other model.
- A → B → A is sticky source loss; same-root nested relocation retains the original model/session while nested currentness still gates acquisition.
- A real second View/render tree, actual source and overlay identities, old/new view pointer dispatch, and pre-push rejection of a foreign source/overlay View configuration. A fabricated viewId alone is insufficient.
- Old shown route retains content/policy/focus lifetime and original-View input, closes at continuous model time, and never hands back to the new source.
- Hidden press preparation and held-reopen reservation detach finitely; covers remain intact; no duplicate model cancellation or late promotion.
- Move after source hand-back: old source-owned samples stop, its unsettled model is honestly abandoned, no old source scheduling remains, fresh source opens independently.
- Stale semantic/Listener callbacks and reentrant sample/cancel/model factory callbacks cannot operate on the new session or perform a locked-tree publication.
- Existing replay, async-time and scene records stay identical, with the old full prototype/example suite and analyzer still passing.

No full affine source link, active geometry retargeting, scroll/rotation behavior, transformed root correctness, native multiwindow behavior or device accessibility claim is made. Production model/clock/timeline/transfer, measured tolerances, dependencies and exports remain unchanged.

## Scrap gates

Reopen the design rather than patching around it if two unrelated callback paths require redirecting old tokens to the new session; if old model ownership requires a second hidden retirement ticker; if the keyed host/handle layer is added solely to repair stale closure reads; or if a generic lifecycle lock starts coordinating both sessions' models. A small session-local deferred retirement barrier is acceptable because tree-locked notification safety is one invariant; it must not become an independent motion state machine.

Proceed with A plus the listed grafts. There is no requested human checkpoint. Keep the current geometry contract fixed and prove this attachment boundary before designing live root-space geometry.
