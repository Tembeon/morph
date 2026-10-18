# Viewport comment review

Reviewed the working diff from `3095d2fe` in `example/lib/proto/menu_route_probe.dart` and `example/test/proto/menu_source_geometry_test.dart`. Surrounding source was read for context. Owner bar changes were excluded. Application and test files were not edited. No tests, device jobs, or nested agents were run by this reviewer.

## Findings

No actionable redundant or misleading comment findings were found in the scoped change. No comment exposes an avoidable invariant that needs an architectural replacement. The added viewport helper carries no narrative comments or historical explanations.

The changed constructor dartdoc at `example/lib/proto/menu_route_probe.dart:67` is retained as a public consumer contract. It states the supported transform shape, the presentation View as the source of system edges, and retirement on observed active placement changes. These statements match `_UniformMap.read`, `_availableMenuRect`, `_MenuGeometry.agrees`, and `_MenuSession.checkGeometry`. The word “Observed” matters because this change adds no metrics observer or active relayout mechanism. The code does not promise immediate keyboard following.

The physical metric semantics were checked in the installed Flutter 3.47.7 SDK source at `/Volumes/Dev/tools/mise/installs/flutter/3.47.7-stable/bin/cache/pkg/sky_engine/lib/ui/window.dart:58`. Both view metrics describe physical edge distances. The SDK describes keyboard insets consuming overlapping view padding. The helper uses the larger edge distance and converts it by devicePixelRatio before projecting into the actual overlay. No added comment claims separately additive insets.

## Suppression audit

There are three existing suppression directives across the two files. The scoped diff adds or broadens none.

- `example/test/proto/menu_source_geometry_test.dart:8` suppresses `implementation_imports` for the independent flat contour reference. The reference imports the existing private outline implementation. Publishing that helper solely for a test would expand the library API.
- `example/test/proto/menu_source_geometry_test.dart:228` suppresses `invalid_use_of_internal_member` at the reference call to `morphGlassContainerOutline`. Its `@internal` declaration was verified in `lib/src/widgets/glass_outline.dart:1094`. The test deliberately compares the root contour against the carried source contour, including the inset variant. It does not suppress a safety or correctness diagnostic.
- `example/lib/proto/menu_route_probe.dart:2077` retains its pre-existing file directive for `implementation_imports`, `invalid_use_of_internal_member`, and `deprecated_member_use`. The first two cover the prototype’s outline and close-admission seams. Their private imports and the `@internal` declaration of `morphMenuSetCloseAdmission` were inspected. The deprecated route-policy members remain called in the unchanged async dismissal implementation. This directive existed at the base revision and the viewport change introduces no additional deprecated calls. Narrowing the older file-wide directive belongs to a separate scoped change.

An exact grep found no `IMPORTANT`, `do not remove`, `do not change wording`, or `talk to` constraint wording in the two scoped files. Therefore no interactive constraint encoding decision is required.

## Counts and limits

- Actionable findings, including MUST KILL findings, 0.
- Comments deleted, restored, or rewritten by this reviewer, 0.
- Changed public contract blocks retained, 1.
- Existing suppression directives audited, 3, containing 5 diagnostic names in total.
- New or broadened suppression directives, 0.
- Review reruns, architect sketches requested, and source fixes proposed, 0.
- Constraint encoding offers, encodings, and unenforced constraints introduced by this change, 0.
- Open comment work in this scope, 0.

This is a source and comment review. Test results and viewport behavior measurements remain the parent’s verification responsibility.
