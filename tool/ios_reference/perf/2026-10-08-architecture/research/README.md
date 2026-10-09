# Shared mip source research

These are API/quality probes, not performance or live-backdrop benchmarks.
Both native launches use beta 3.49.0-0.2.pre release arm64 on Pixel 6a Vulkan.
Four distinct uploaded mip colors survive GPU texture/image wrapping.
Runtime medium quality selects/interpolates all levels; none/low return base.
All 21 center-color checks agree on both launches within one byte per channel.

mip-api-1 records the initial source; mip-api-2 records the analyzed cleanup.
The latter's source ZIP exactly matches the checked source. Build manifests
retain APK, framework, engine and entrypoint hashes. APKs remain in /tmp.
The first report incorrectly names its pixel-format field backend; actual
Vulkan identity is retained in the device logs. The second corrects the name.

Reproduction from the repository root:

```sh
python3 tool/ios_reference/perf/stage_bench/run_android.py build \
  --flutter flutter-beta --mode release --target lib/perf/mip_api_probe.dart \
  --apk /tmp/morph-mip-api.apk
python3 tool/ios_reference/perf/stage_bench/run_android.py run \
  --apk /tmp/morph-mip-api.apk --out /tmp/morph-mip-results \
  --name mip-api --trace none --schema mip --leave-installed
```

The shader compiles to runtime Vulkan, Metal and GLES3. The build's SkSL
warning is expected: Skia runtime effects do not support this explicit LOD.
No native Metal/GLES execution result is asserted here. Installed impellerc
can reproduce the Vulkan compiler check (adjust SDK location as needed):

```sh
/Users/tembeon/.local/share/flutter-beta/bin/cache/artifacts/engine/darwin-x64/impellerc \
  --runtime-stage-vulkan --input=example/lib/perf/shaders/mip_lod.frag \
  --input-type=frag --sl=/tmp/morph-mip-vulkan.iplr \
  --spirv=/tmp/morph-mip-vulkan.spv --iplr \
  --include=/Users/tembeon/.local/share/flutter-beta/engine/src/flutter/impeller/compiler/shader_lib \
  --verbose
```

mip-psf.json comes from the archived mip_psf.py with NumPy 2.4.2. It models
separable box/tent4 downsampling and bilinear/trilinear reconstruction, with
LOD fit to a phase-averaged discrete Gaussian. Phase dependence and centroid
are numerical diagnostics; GPU generation cost, image quality and actual
shimmer require a separate native producer/consumer experiment.

Interpretation, H01-H20 reconciliation and next protocol:
../../../../audit/codex-gpu-research-reconciliation.md.
