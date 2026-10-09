# Stable pass lifecycle compatibility check

Read ../../../../../audit/codex-gpu-pass-lifecycle-report.md.
This is crash/compatibility evidence on 2026-10-09, not a performance cohort.
Pixel 6a / Mali G78 / Vulkan, Flutter stable 3.47.2, release arm64.

native/ contains two completed separate-submission reports and two failing
batched launches, with SDK/build identities and timestamp-scoped native
crash logs. summary.json checks optical paints and exact pass/submission
counts for completed controls. Both failures reach the same end_renderpass
frame through InternalFlutterGpu_CommandBuffer_Submit.

sources.tar.gz and sources.json freeze 247 build inputs. Relative to the
211-input owned-optics-batch snapshot, only example/pubspec.lock changes
under stable dependency resolution. This older producer publishes from its
parent painter and is not qualified for dynamic image parity or FPS admission.
The primary working copy remains on beta and its current safe producer is
unchanged. Both diagnostic APKs remain under /tmp/morph-architecture/
stable-batch-check; their hashes are in native/*.build.json.

engine/ contains installed stable source evidence. Dart evidence uses .dart.txt
to avoid standalone analyzer errors. Relevant wrapper and Vulkan source hashes
match the installed beta except lib/gpu/render_pass.cc; its Begin lifecycle
still matches. Metal evidence was inspected, not executed in this check.

protocol/run_android.py substitutes the original repository HEAD in metadata
because this diagnostic copy has no Git checkout. It does not override Git
environment variables when invoking the SDK. Build with --flutter flutter
--mode release and the exact --define selections in native/*.build.json.
Compile the example bundle with compile_mip_bundle.py --sdk pointing at
stable first. Run with --trace none --schema stage --leave-installed.
The final installed device APK is the working separate-submission control.

No native engine patch, validation-layer run, new pixel checks, GPU trace or
Metal runtime test is part of this experiment. Failed setup logs are preserved
separately from the successful final build logs. The architecture directory's
global SHA256SUMS covers this evidence.
