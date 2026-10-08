# Side-by-side beta SDK and native filter research, 2026-10-08

## Installed SDKs

`flutter-beta` is available in a new login shell at
`/opt/homebrew/bin/flutter-beta`, pointing to the official beta checkout
at `/Users/tembeon/.local/share/flutter-beta`. `dart-beta` points to that
SDK's Dart executable. Normal `flutter` and `dart` retain the stable SDK.

| SDK | Framework | Engine | Dart |
|---|---|---|---|
| Stable | 3.47.2, d3b14c8769 | a804b26164 | 3.13.2 |
| Beta | 3.49.0-0.2.pre, 38ec981bad | 774a767348 | 3.14.0-211.1.beta |

The official release manifest returned HTTP 404, so installation used a
shallow checkout of the official Flutter repository's beta branch.
Android and macOS tools were precached. Stable was not upgraded in place.
Build records now accept `--flutter flutter-beta` and retain exact SDK
revisions alongside APK hashes. Separate disposable checkouts isolate
package configuration, native hooks, shader bundles and build caches.
SDK-pinned dependency differences, including vector_math, are retained in
the input locks. This compares complete SDK configurations, not one commit
in isolation.

## A real compatibility regression, corrected

Morph already selected bilinear backdrop sampling on stable by binding
sampler zero with low quality. The old Impeller path kept its sampler
descriptor while substituting the native backdrop texture. This is a
native current-frame filter input, not a framebuffer exposed to Dart.

In beta, `ImageFilter.shader` chooses the first sampler descriptor from
its explicit `filterQuality` argument, whose default is nearest. The old
binding no longer controls it. Unmodified Morph therefore changed glass
pixels: native chrome maximum 27/255, with 7579 whole-frame pixels above
six channel steps across 28 liquid phase pairs.

`morphGlassShaderFilter` tests the factory's typed function signature and
passes low quality when the named argument exists. The legacy call and
bound first sampler support stable. This needs no dynamic invocation,
version-string parsing or higher minimum SDK. Both the renderer and its
pipeline warm-up use it.

Corrected beta versus stable: flat chrome is identical; liquid chrome
maximum is 1/255. Whole-frame maxima are 63/64 on isolated pixels, with
15/3 pixels above six steps across the respective 28 phase pairs.
Independent corrected-beta repeats also have isolated errors: flat
maximum 64, chrome 63 on three pixels in one frame; liquid maximum 56,
chrome 10. Full-frame and repeat errors remain in the evidence. This is
sampled native fidelity, not an assertion that every frame is byte-identical.
The second beta PNG set was retrieved by the subsequent Gaussian run;
that run writes different filenames and does not overwrite Navigation PNGs.

## Actual Gallery Navigation on Pixel 6a

Vulkan, DPR 2.625, 60 Hz, profile AOT, production source f3cb00a plus
the compatibility patch. Five shuffled repeats per case, actions prewarmed,
500 ms warm-up and 800 ms action windows. Native PNG readbacks follow all
timing windows. GPU work uses the app UID and streamed work-period events.
There is no phase collector or CPU profiler in these windows.

Initial beta with nearest sampling was a diagnostic launch. It was
followed by two stable launches and two corrected-beta launches, rather
than treating that changed image as a valid same-quality control.
Median per-run p95 / GPU active work per rendered frame, launch 1 / 2:

| Liquid action | Stable UI p95, ms | Beta UI p95, ms | Stable raster p95, ms | Beta raster p95, ms | Stable GPU, ms | Beta GPU, ms |
|---|---:|---:|---:|---:|---:|---:|
| Enter | 15.578 / 15.834 | 14.562 / 15.418 | 14.895 / 16.701 | 14.340 / 14.850 | 4.837 / 4.786 | 5.091 / 5.074 |
| Push | 25.191 / 27.266 | 21.641 / 19.984 | 25.611 / 27.517 | 29.419 / 26.456 | 5.938 / 5.925 | 6.228 / 6.202 |
| Pop | 29.257 / 27.763 | 20.579 / 16.320 | 24.817 / 29.853 | 25.377 / 23.569 | 5.313 / 5.296 | 5.674 / 5.611 |
| Toolbar | 8.887 / 10.295 | 8.861 / 9.577 | 15.066 / 17.126 | 15.885 / 15.464 | 4.070 / 4.078 | 4.405 / 4.426 |

Nested UI preparation is lower in these beta launches; push raster is
mixed, and liquid GPU active work rises roughly 5-9 percent. Median
over-budget frames: push stable 9/11 versus beta 9/8, pop 8/8 versus
8/8. The 16.667 ms budget is still exceeded. Raster duration is not GPU
execution time, and inferred vsync gaps are not Android presentation
measurements. No uniform FPS gain or energy saving is established.
Energy has not been measured for this SDK comparison.

## Bilinear Gaussian experiment

Two additional native launches use five shuffled repeats on small and
large rectangular regions, moving tiles, sigma 2 and the production
half-resolution sigma policy. `exact` is a normalized discrete Gaussian
reference truncated at three sigma; `paired` combines adjacent weights
and offsets and enables native linear input sampling. Both use the same
two-axis runtime-filter composition, retained shaders and CPU-prepared
weights. Neither captures a source image or reads a previous frame.

GPU active work per rendered frame, ms, launch 1 / 2:

| Region | Stock Gaussian | Discrete reference | Paired bilinear |
|---|---:|---:|---:|
| Single | 2.348 / 2.334 | 11.378 / 10.963 | 8.230 / 8.230 |
| Large | 3.171 / 3.184 | 11.687 / 11.522 | 10.441 / 9.994 |

Paired versus reference maximum native pixel error is 1/255 over six
phase pairs. Pairing works and reduces GPU work, but the complete chain
is still 3.1-3.5 times the stock filter's whole-app GPU cost. Against
stock, both custom kernels reach 20/255 and fail the few-step fidelity
gate. Their three-sigma reference is not Impeller's exact kernel:
Impeller corrects sigma, truncates support differently, downsamples and
already uses bilinear sample pairing (`LerpHackKernelSamples`). These
are kernel/API experiments, not production replacements or Dual Kawase.

The SDK source also shows a possible intermediate re-rasterization for
transformed runtime-filter inputs. GPU work alone does not establish the
exact native pass count or the cost of that branch. Avoid attributing the
whole difference to shader arithmetic or submission overhead without a
frame capture.

A separate byte-encoding probe verifies the second runtime pass's actual
input size: 1082 by 2402 pixels for both layouts, at all three phases,
on a 1080 by 2400 screen. Thus the intermediate spans the viewport plus
padding even for the small region, whose visible area is about eight
times smaller. This is direct evidence of an oversized intermediate in
this prototype, not a measurement of every pass's fragment count. It
supports prioritizing an ROI-sized intermediate before tuning the kernel.
An independent Android `exec-out screencap` of the displayed small-region
probe also decodes 1082 by 2402. That check does not invoke Flutter
`toImage` or render an alternate Flutter frame: the oversized input is
confirmed on the actual screen path. Its screenshot, source patch and
decode record are preserved separately.
`input-probe.patch` and `input-sizes.json` preserve the probe. Its first
attempt rejected an unsupported mode after a patch-application failure;
the runner restored the gallery and no failed timings entered the matrix.

## Verification and next work

Both SDKs analyze without issues and pass 1404 package tests plus 21
gallery tests with the compatibility helper. Required stable gates also
pass formatting and documentation with zero warnings/errors. The final
stable release gallery is restored in portrait; benchmark runners restore
the previous APK and owned tracing state on every exit, including failures.
The user-owned integration-test edit is untouched.

Next experiments should reduce filter topology and intermediate area while
preserving source padding, sampling phase and existing optics. Navigation
also needs less fused-field/geometry preparation and a cheaper retained
glyph/filter path; replacing background blur alone cannot remove its
nonglass raster tail. Bilinear sampling is an ingredient, and the new API
does not supply a free backdrop texture or automatic downsampling.

## Reproduce

See `tool/ios_reference/perf/2026-10-08-beta-sdk/README.md` for source
patches, exact defines, input locks, SDK provenance, raw timings/GPU
streams and pixel metrics. No experimental Gaussian is enabled in the
production package. The SDK stays installed after temporary checkouts
and APKs are cleaned.
