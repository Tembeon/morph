# Current-frame background input: SDK and engine audit

2026-10-07. Verified against the installed Flutter 3.47.2 SDK and a
clean source checkout at the same framework revision
`d3b14c876900e553bc736ca19295fc09e3853e8e`, engine `a804b26164`.
The goal is one current-frame source, with no CPU readback or duplicate
widget rasterization. A fast blur kernel alone does not supply that source.

## What is available

| Input | Existing GPU pixels reusable? | Additional source render? | Current-frame limitation |
|---|---|---|---|
| Owned gpu.Texture | Yes; bindTexture directly | None beyond its producer | Queue ordering and in-flight ownership must be correct |
| Ready GPU-backed ui.Image | Yes; Texture.fromImage shares storage | No copy in wrapping | It must already exist and be rasterized |
| Picture/RepaintBoundary capture | The resulting image can be wrapped | Yes, rasterizes the recorded scene into another image | Async completion must be awaited; delayed reuse changes frame fidelity |
| BackdropFilter shader sampler 0 | Yes, supplied natively by Impeller | No duplicate widget painting; engine may still flip/copy the pass | Available to the filter on the raster thread, not as a Dart gpu.Texture |
| Main onscreen render target | No public Flutter GPU accessor | N/A | Public context only creates offscreen targets |

`Texture.fromImage` is present locally. Native
`InternalFlutterGpu_Texture_InitializeFromImage` obtains the image's
Impeller texture and puts the same shared pointer into the Flutter GPU
wrapper. This removes a readback/upload pair; it does not turn a layer
or the onscreen framebuffer into an image. Its descriptor may permit
sampling but not attachment writes. Deferred toImageSync output may not
have a backing texture when the UI thread attempts to wrap it.

`Picture.toImageSync` calls `RasterizeToImageSync`, which creates a
deferred image from a DisplayList and the raster task runner. It schedules
another rasterized image, not a borrowed reference to the already drawn
backdrop. There is no CPU pixel readback in the prototype, but there is
extra raster work and image allocation. Consequently the prototype's
cost is not the lower bound for a direct-texture Dual Kawase renderer.

## Morph's actual source ownership

`FlutterGpuGeometryRenderer` produces matte and material maps through
Flutter GPU. Those textures describe shape/optics; they do not contain
the widget background. The final filter obtains that background from
Impeller's BackdropFilter path. In `Canvas::SaveLayer`, `FlipBackdrop`
returns the current pass input texture, with optional reuse by backdrop
key, then `WrapInput` passes it into the filter graph.

`RuntimeEffectFilterContents::RenderFilter` obtains the input snapshot,
assigns its texture to sampler 0 and writes its actual size into the first
vec2 uniform. These operations occur natively while rendering the filter.
The Dart FragmentShader's `getImageSampler` returns a binding object, not
the engine-supplied texture; it is not a route to read this native input.

The useful texture already exists inside Impeller. The missing bridge is
public access to that particular current-frame input from Flutter GPU.
Replacing one shader with several Dart-created GPU passes does not
provide that bridge. GpuImageSurface manages targets we produce and
present; it does not capture arbitrary widget content automatically.

## Routes worth testing

1. Keep the input in Impeller and compose native image filters. Matrix
   filters alter snapshot transforms; runtime-effect filters can rasterize
   transformed snapshots into smaller intermediate textures. A native
   probe must verify real texture dimensions, clips, origins and output,
   not infer reduction from the Dart filter list. It may add an extra
   resample per level compared with a fused downsample-and-kernel pass.
2. For an already owned image/texture source, use a genuine Flutter GPU
   pyramid with persistent intermediate targets and no image capture in
   measured frames. This measures the kernel and resource reuse separately;
   it does not prove arbitrary-widget backdrop integration.
3. If public composition cannot preserve the required graph/fidelity,
   add an engine-native filter accepting the existing FilterInput texture.
   Native passes can then run the pyramid before the final glass filter,
   sharing the renderer context and command ordering. This requires a
   tested custom engine; a normal Dart plugin cannot simply borrow the
   private backdrop handle and synchronization state.

## Primary sources

- [Texture.fromImage addition and constraints](https://github.com/flutter/flutter/pull/188605).
- [Texture API](https://api.flutter.dev/flutter/flutter_gpu/Texture-class.html).
- [Offscreen target limitation](https://api.flutter.dev/flutter/flutter_gpu/GpuContext/doesSupportOffscreenMSAA.html).
- [ImageFilter shader input contract](https://api.flutter.dev/flutter/dart-ui/ImageFilter/ImageFilter.shader.html).
- [Engine source at the installed revision](https://github.com/flutter/flutter/tree/d3b14c876900e553bc736ca19295fc09e3853e8e/engine/src/flutter).

A separate resource opportunity is presentable output ownership: the SDK's
GpuImageSurface refuses to reuse a texture still current, pending producer
work or referenced by Flutter. That may replace our frame-count ring
heuristic for matte/material outputs, but it neither supplies the backdrop
nor proves lower RSS. It needs its own native lifetime, memory and energy
experiment before changing production geometry allocation.

No custom engine or SDK file was modified. The matrix/runtime-effect native probe confirms quarter and sixteenth
input dimensions (about 270 x 600 and 68 x 150) without per-frame scene
capture. Its current kernel/output differs visibly from stock Gaussian
and has extra resamples, so this is source-path feasibility, not an
optimization ready for adoption. The dimensions track the full viewport
at each scale, despite a smaller final output clip. A future minimal
filter must bound the input ROI and sampling reach as well as reduce
resolution; the existing graph still processes more background than
that output rectangle requires. Native results are recorded in
codex-round5-optimization.md and its evidence directory.
