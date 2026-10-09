# Flutter GPU pass lifecycle: stable verification, 2026-10-09

## Result

Flutter stable 3.47.2 does not unlock the rejected multi-pass command-buffer
experiment. On Pixel 6a / Mali G78 / Impeller Vulkan, two release launches
of the archived batching implementation both died with SIGSEGV in
`vulkan::command_buffer::end_renderpass`, through
`InternalFlutterGpu_CommandBuffer_Submit`. The same source with batching
disabled completed twice, before and after the failing launches.

This is a compatibility/crash check, not a stable-versus-beta performance
comparison. No GPU trace, native image parity, Metal execution, Vulkan
validation-layer messages or VUID were collected for this check.

## Meaning of the upstream examples

The example in [Flutter #193804](https://github.com/flutter/flutter/issues/193804)
creates a new command buffer inside each `renderPass()` invocation, records
one pass, and submits it. Its two passes therefore use two command buffers.
The `clear` then `load` example diagnoses a separate attachment-cache issue;
it does not demonstrate multiple render passes in one command buffer.

[Flutter #193867](https://github.com/flutter/flutter/issues/193867) explicitly
describes the current workaround as one command buffer per render pass. It
proposes ending the previous pass when the next command is recorded, plus
an explicit `RenderPass.end()`. This is an open capability proposal when
checked on 2026-10-09, rather than an API in either installed SDK.
[The compute tracker](https://github.com/flutter/flutter/issues/188474)
also describes this lifecycle constraint.

The earlier batching attempt assumed support that the installed Flutter GPU
implementation does not provide. Its native crash is observed; it should
not be presented as a beta regression or evidence that several supported
sequential passes intrinsically cost more than separate submissions.

## Installed source evidence

Stable framework: `d3b14c876900e553bc736ca19295fc09e3853e8e`.
Stable engine: `a804b261645ef8c13eb3d5c44a5c2fb0340c5539`.
Beta framework: `38ec981bad973156ad05bdef0aa8e82d1a58905b`.
Beta engine: `774a76734848e38c908681d752e465b2a1595adb`.

For stable's engine sources:

- `lib/gpu/render_pass.cc:77`: `Begin` creates the backend render pass and
  registers it with the public wrapper's command buffer.
- `lib/gpu/command_buffer.cc:42`: `AddRenderPass` retains the encodable.
- `lib/gpu/command_buffer.cc:175`: Vulkan submission encodes the retained
  passes before submitting the backend command buffer.
- `impeller/renderer/backend/vulkan/render_pass_vk.cc:241`: construction
  records `beginRenderPass`.
- `impeller/renderer/backend/vulkan/render_pass_vk.cc:709`: deferred
  `OnEncodeCommands` records `endRenderPass`.
- `impeller/renderer/backend/metal/render_pass_mtl.mm:152`: construction
  creates the Metal encoder; line 190 ends it during encoding. This is
  source evidence only; the failing probe was not executed on Metal.

Stable and installed beta have byte-identical `lib/gpu/command_buffer.cc`
and `render_pass_vk.cc`. Their `lib/gpu/render_pass.cc` files differ, but
both retain this begin/register lifecycle. Neither installed Dart render
pass API has `end()`.

Creating pass B before submission therefore leaves pass A's backend scope
open. The source ordering explains the crash consistently with upstream's
lifecycle analysis; no validation-layer proof or local engine fix is claimed.

## Reproduction and controls

An isolated copy under `/tmp/morph-architecture/stable-batch-check` combines
the archived `owned-optics-batch` source with the Android build scaffolding.
The 211 archived source inputs match except `example/pubspec.lock`: stable
resolution changes test_api and removes listen. The renderer, shaders and
producer Dart code match the archived failed beta input. The example GPU
bundle was recompiled with stable's impellerc. The local runner substitutes
the original repository HEAD in metadata because the copy has no Git checkout.
Neither the primary package configuration nor its SDK selection was changed.

Both APKs use `MIP_OPTICS=true`, N=4, tent and collapsed-tent kernels,
fresh/reuse, one repeat, 200 ms warm-up and 600 ms samples. Their selection
differs only in `MIP_BATCH=false` versus `true`.

| Launch | Submission mode | Outcome |
| --- | --- | --- |
| stable-separate-1 | One command buffer per producer pass | All four cases complete |
| stable-batched-1 | One command buffer per producer update | Native SIGSEGV, no report |
| stable-batched-2 | One command buffer per producer update | Same native SIGSEGV, no report |
| stable-separate-2 | One command buffer per producer pass | All four cases complete |

Both controls report `liquid_available=true` and nonzero owned optical paints
in every case. Fresh tent records one source and five reduction passes per
update; collapsed tent records one source and three reduction passes.
Submission counts equal pass counts. Reuse windows submit no producer work.
These diagnostics use the older archived publication order and are not
admitted as current dynamic image-quality or cadence results.

Every device run uses `--leave-installed`; the final installed APK is the
working stable separate-submission diagnostic. Logs, source snapshot,
SDK/build/APK identities, native stacks, runner and compiled bundle are in
`tool/ios_reference/perf/2026-10-08-architecture/owned-optics/stable-batch-check`.

## Consequences for optimization

Keep the current separate-submission baseline for dependent reductions.
Several draws in one render pass can still share an attachment when they
do not require a preceding draw's output as a sampled intermediate. That is
different from the pyramid's dependent passes through different targets.
Algebraic kernel fusion, resource reuse and avoiding unnecessary producer
updates remain package-level candidates; their end-to-end costs need measurement.

The producer overwrites its output with `LoadAction.dontCare` consistently;
it does not exercise the `clear` then `load` sequence from #193804. That
reported bug has not been independently reproduced here and is not assigned
as the cause of these crashes. Submission also does not synchronously wait
for GPU completion; the existing retirement/completion contract remains
necessary. No per-submit CPU wait or `waitIdle` was added.

Reducing these dependent passes to one command buffer requires a supported
pass-lifecycle implementation or a separately qualified engine experiment.
Simply switching between the two installed SDKs does not provide it.
