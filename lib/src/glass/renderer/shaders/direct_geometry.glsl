// Experimental single primitive, using the existing geometry pass equations.
// Snapping and RGBA8 companding intentionally retain the old matte response;
// this experiment isolates removal of its render target and GPU submission.
uniform vec3 uDirectOptics; // refraction height, amount, fits shape
#define MAX_SHAPES 1
uniform vec4 uShapeData[3];
uniform vec4 uRseData[3];
// A single shape never needs the scene bounds helpers.
vec4 uShapeBounds[1];
#include "gpu/sdf.glsl"

vec4 directGeometryData(vec2 matteCoord) {
    vec2 p = floor(matteCoord - uGeometryOffset) + 0.5 + uGeometryOffset;
    SceneSample scene = getShapeSampleFromArray(0, p, false);
    float sd = scene.distance;
    float extent = contourExtent();
    float fade = 0.5 * max(length(scene.opticalNormal), 1e-4);
    float materialAlpha = 1.0 - smoothstep(-fade, fade, sd);
    float contourSupport = 1.0 - smoothstep(max(extent - fade, 0.0), extent, sd);
    if (max(materialAlpha, contourSupport) < 0.01) return vec4(0.0);
    float normalLength = length(scene.opticalNormal);
    vec2 normal = normalLength > 0.0001
        ? scene.opticalNormal / normalLength : vec2(0.0);
    float bevel;
    float amount;
    if (uDirectOptics.z > 0.5) {
        bevel = min(uDirectOptics.x, 0.5 * scene.halfMinor);
        amount = min(uDirectOptics.y, scene.halfMinor);
    } else {
        float lensScale = min(1.0, scene.halfMinor / max(uDirectOptics.x, 0.001));
        bevel = uDirectOptics.x * lensScale;
        amount = uDirectOptics.y * lensScale;
    }
    float x = 1.0 - clamp(max(-sd, 0.0) / max(bevel, 0.001), 0.0, 1.0);
    float displacement = bevel > 0.001
        ? -amount * (1.0 - sqrt(1.0 - x * x)) : 0.0;
    vec4 data = encodeDisplacementData(
        normal, displacement, max(uDirectOptics.y, 0.001), -sd,
        4.0 * uThickness, extent
    );
    return floor(data * 255.0 + 0.5) / 255.0;
}
