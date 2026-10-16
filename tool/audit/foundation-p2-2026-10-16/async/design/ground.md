# P2 async dismissal grounding

Repository: /Users/tembeon/IdeaProjects/morph. Base 9fcf9d19; branch wip/measured-liquid-glass. Main must stay unchanged. User authorizes continuing the redesign plan; no compatibility with old API. Prototype hosts/routes/scenes stay in example/lib/proto; unit 0 already permits one internal model admission seam, to be replaced in unit 2.4. No new dependencies, no measured tuning/fixture/tolerance changes. No device or heavy test jobs from agents.

## Checklist

- [ ] Ground: how and historical why; constraints
- [ ] Sketch: frame rubric; two independent candidates; fresh cross-judge
- [ ] Agree: synthesize caller-first protocol, no human checkpoint requested
- [ ] Implement and verify model/real binding/SDK lifecycle/replays
- [ ] Scrap if the old callback shape keeps requiring exceptions

Arena phases: frame, fan out, cross-judge, pick, graft, verify. Deliverables for candidate A/B are read-only design artifacts in their own directories, not repository edits. Same inherited model independent runs, not multiple model families.

## Existing flow

MorphMenuMotion schedules _requestClose at measured deadlines. morphMenuSetCloseAdmission installs a bool Function(double canonicalTime). Callback runs before closing channels mutate, must not mutate model. Prototype records (route,admitted,time); true directly closes motion at original deadline, false leaves it opening. After advance/input returns, host invokes SDK pop or refusal callback. willHandlePopInternally refuses motion closing while permitting SDK pop to consume local history. Programmatic model.close bypasses admission.

ProbeMenuTransfer owns one complete model, unique lease identity, canonical offset = modelTime-ownerLocalTime. Source and PopupRoute have separate ProbeMotionClock objects. Old lease cannot sample/command; hand-back at first progress<=0; route disposes while source runs tail. Source may unmount independently. Forced route removal creates a new idle model. Async completion must never close a replacement or a covering route.

MorphMenuMotion.advance refuses t<now, but close(t) calls _close(t) even if advance refused. _sample does not rewind integrated kicks. Retargeting a close in the past after letting open motion advance cannot restore the earlier physical state. A late approval with original deadline would skip visible frames or mismatch driven state. The plan's 'preserve original reaction time' needs an explicit causal interpretation, not a silent retroactive close.

Current model source: lib/src/widgets/menu_motion.dart (constructor~1200; admission hook top; _requestClose~3046; close~2460; advance~2756; _sample~2902). Timeline: lib/src/widgets/timeline.dart. Transfer: example/lib/proto/menu_transfer_probe.dart. Route: example/lib/proto/menu_route_probe.dart. Clock: example/lib/proto/motion_clock_probe.dart. Tests: example/test/proto/menu_route_input_test.dart, menu_route_replay_test.dart, menu_route_scene_test.dart; test/menu_close_admission_test.dart.

SDK is local /opt/homebrew/Caskroom/flutter/3.19.1/flutter/packages/flutter/lib/src/widgets/{navigator,routes}.dart, Flutter 3.47.2. Navigator.maybePop awaits deprecated willPop, rechecks mounted/current history entry, then popDisposition. Programmatic Navigator.pop bypasses PopScope. Public local history may consume pop without closing route. PopScope is synchronous modern policy. WillPopScope/scoped callback is a real async SDK boundary available to prove permission without inventing product API; it is deprecated and must be labelled as such.

## Evidence and historical intent

9fcf9d19 created sync admission and documented async as OPEN; report tool/audit/foundation-p2-2026-10-16/admission/report.md. 5bad38c8 reproduced auto-close bypassing PopScope; report input/report.md. 7d0968a7 integrated real PopupRoute. Commit messages have no PR/ticket IDs. No external records are needed to establish motivation of this fresh local prototype, explicitly stated in committed design/report and current conversation. Available Todoist is not used: the specific hook and contradiction were created in these local commits, with no issue link. No matching project chat/observability/error/analytics connector. Connected generic document control is not a repository design record; repo docs supply direct evidence. Don't search unrelated accounts.

## Design task

Produce a small caller-first async dismissal protocol, implementable as a P2 proof, with a path to typed E/drainEvents. Consider distinct whole shapes, not point guards on bool callback. Preserve sync measured replays with original deadline; refuse before phase changes; leave opening/interaction live while awaiting if possible; define exact meaning of requestedAt versus acceptedAt/closeStartedAt. Await owner lifetime, replacement, cover/uncover, coalescing, permission throws, repeated callbacks, explicit programmatic pop, local history, source loss and first-build registration. Minimize state and mutable owners; no snapshot/clone/replay model, backdated kicks, global binding hacks or app setup burden. Call out impossible/conflicting requirements honestly and name any plan refinement. Do not implement before synthesis.

Rubric (0-3 each): causal time/unchanged sync fidelity; refusal and single-writer safety; SDK lifecycle/async race handling; small API and removable provisional seams; concrete falsifiable tests and implementation feasibility. Read architect references/runner-prompt.md and design-red-flags.md.
