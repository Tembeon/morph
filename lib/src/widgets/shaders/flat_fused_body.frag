// Fills a flat glass container body of up to four merged rounded boxes
// (MorphFlatBodyShader in flat_body_shader.dart) by evaluating the
// container's merge law per pixel (fused_law.glsl), instead of filling a
// silhouette traced on the CPU. Coverage is the signed distance's
// one-device-pixel ramp; an optional rim strokes the edge centered on it,
// as a stroked path does, and is composited over the fill.
#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

#define FUSED_MAX_BOXES 4

// Per box, in the canvas's local units: (center, half extents), then
// (corner radius clamped to the half extents, 0, 0, 0).
uniform vec4 uFusedBoxes[FUSED_MAX_BOXES * 2];
// x: the box count, y: the merge spacing, z: the narrowest merge width
// that blends, both local units, w: device pixels per local unit.
uniform vec4 uLaw;
// The fill color, unpremultiplied.
uniform vec4 uFill;
// The rim color, unpremultiplied; alpha 0 for no rim.
uniform vec4 uRim;
// The rim's width in local units.
uniform float uRimWidth;

#include "../../glass/renderer/shaders/fused_law.glsl"

out vec4 fragColor;

void main() {
    vec2 p = FlutterFragCoord().xy;
    // Device pixels outside the edge.
    float x = fusedFold(p, int(uLaw.x), uLaw.y, uLaw.z) * uLaw.w;
    float fill = clamp(0.5 - x, 0.0, 1.0);
    vec4 color = vec4(uFill.rgb * uFill.a, uFill.a) * fill;
    if (uRim.a > 0.0) {
        // The share of the pixel's box the centered band covers.
        float halfWidth = 0.5 * uRimWidth * uLaw.w;
        float rim = max(min(halfWidth, x + 0.5) - max(-halfWidth, x - 0.5), 0.0);
        float a = uRim.a * rim;
        color = vec4(uRim.rgb * a, a) + color * (1.0 - a);
    }
    fragColor = color;
}
