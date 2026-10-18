# Candidate A: one admission containing a validated endpoint

## Problem

The prototype's `_MenuGeometry` mixes source facts with placement admission. Native selection/reopen supports per-opening placement but does not establish optical landing. Separate knowledge while preserving every rejection, active retirement and paint fence. A null complete admission still includes unsupported root transforms, invalid viewport, minimum-fit failure and covered source. Scope: one prototype file, unchanged measured constructor and library API.

## Usage (caller's view)

App usage remains `ProbeMenuSource.measured(button: localButton, menuBuilder: buildMenu)`.

The state reader obtains a validated endpoint, then asks placement admission to accept it:

```dart
final endpoint = _SourceEndpoint.read(context, overlay, widget);
return endpoint == null ? null : _MenuAdmission.read(endpoint, view, minimum);
```

Session relayout reads `current.endpoint` for source model inputs and `current.padding` for placement. Input reads `geometry!.endpoint.position(event.position)`; source paint reads `geometry!.endpoint.map` after the existing complete-admission fence. No caller receives an endpoint-valid boolean that could bypass placement policy.

## Shape

Keep the session's `geometry`, `readGeometry`, `admitGeometry` and `checkGeometry` as the single live path. Replace the flat value with two private immutable types in the same file:

- `_SourceEndpoint` owns source/overlay RenderBox identities, source-to-overlay uniform map, mapped button, overlay bounds and scaled source shape. Its factory validates attachment/layout, Offstage ancestry, source transform and finite positive shape. It owns source agreement and current overlay-to-global input conversion.
- `_MenuAdmission` contains one endpoint and one available rectangle. Its factory reads the current root transform and physical viewport, applies existing max(safe, IME)/DPR projection, rejects minimum-fit and source containment failures, and derives padding. Its `agrees` combines endpoint agreement and available-rectangle equality.

`_availableMenuRect` remains the sole viewport projection implementation. Admission uses endpoint bounds rather than copying them. There is one stored aggregate, one model and no extra mutable state. Whole-root movement remains allowed exactly as today: root-global transform is read during admission and input conversion, never added to endpoint agreement.

Per boundary-discipline, factories guard their own facts; valid values hide predicates. Per single-source-of-truth, padding and model inputs derive from the aggregate. The types earn their structure by moving validation, comparison and input conversion beside their data. The state shell retains attachment/tuning access; session retains lifecycle. No generic presentation abstraction.

Every observation still compares complete admission. Idle mismatches await admission; active mismatch or null admission irreversibly detaches. Readiness runs after installation, then existing model/attachment/fresh-admission checks run. Frame and handback retain their call order. Shown popup sampling and later input continue after detach. Painter retains its pre-owner check and extra fresh read during idle mismatch, protecting same-frame handback/layout suppression. Model reset clears the single admission.

## Synthesis decision

Independent candidate A; selection and grafts belong to the parent comparison. No multi-model agreement is claimed.

## Tradeoffs accepted

- We accept one extra private value type and explicit `.endpoint` access for isolated source knowledge without split ownership.
- We accept conservative availability-triggered retirement while optical landing remains unmeasured.
- We accept passing the existing widget to the private source factory to avoid a duplicate configuration wrapper.

## Alternatives considered

Independently stored endpoint and placement snapshots expose synchronization rules and two lifetimes; a caller could validate only the endpoint and resurrect it after invalid active admission. A flat value with extracted comparison helpers hides less: source validation remains mixed with fit/containment, so future policy edits still cross knowledge domains.

## Open questions and risks

Can all 62 geometry cases, the full example suite and both contour oracles demonstrate structural equivalence, especially null-admission and post-readiness sticky retirement? Optical landing is deliberately unresolved.

## Next implementation step

Move endpoint predicates and methods into `_SourceEndpoint`, derive `_MenuAdmission` from it, and preserve session control flow while changing only fact access paths.
