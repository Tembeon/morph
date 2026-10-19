// Geometry pass for a glass container's fused body of up to four rounded
// boxes (GlassBoxField): the same matte as geometry_fragment.glsl, but the
// signed distance, the optical normal and the half thickness come from the
// container's merge law evaluated per pixel (fused_law.glsl and
// fused_optics.glsl), the law the analytic final pass shades
// (analytic_geometry.glsl). A resting matte therefore holds the moving
// frames' body up to the matte's 12-bit and companded quantization, where
// a field sampled on a grid would bend its necks into straight steps.

// The matte packs 12-bit integer codes; fp16 cannot represent them exactly.
precision highp float;

#define FUSED_MAX_BOXES 4

layout(std140) uniform FusedUniforms {
    vec2 uOffset;
    vec2 uTextureSize;
    vec4 uOpticalProps;
    vec4 uContourProps;
    // x: the box count, y: the merge spacing, z: the narrowest merge width
    // that blends, both in matte pixels.
    vec4 uFusedLaw;
    // Per box, in matte pixels: (center, half extents), then (corner
    // radius clamped to the half extents, 0, 0, 0).
    vec4 uFusedBoxes[FUSED_MAX_BOXES * 2];
    // Matte texels per device pixel of the layer along x and y: a matte
    // under a scale of its pass is encoded at the pass's pixels, while
    // every position and distance stays in the layer's device pixels.
    vec2 uMatteDensity;
} fusedUniforms;

#define uOffset fusedUniforms.uOffset
#define uTextureSize fusedUniforms.uTextureSize
#define uOpticalProps fusedUniforms.uOpticalProps
#define uContourProps fusedUniforms.uContourProps
#define uFusedLaw fusedUniforms.uFusedLaw
#define uFusedBoxes fusedUniforms.uFusedBoxes
#define uMatteDensity fusedUniforms.uMatteDensity

// sdf.glsl's, which this pass does not include: it reads the shape rows.
const float kOpticalCornerRadiusScale = 1.5;

#include "displacement_encoding.glsl"
#include "../fused_law.glsl"
#include "../fused_optics.glsl"

out vec4 fragColor;

void main() {
    vec2 p = gl_FragCoord.xy / uMatteDensity + uOffset;
    int count = int(uFusedLaw.x);
    float k = uFusedLaw.y;
    float minWidth = uFusedLaw.z;
    float uContourExtent = uContourProps.x;

    float sd = fusedFold(p, count, k, minWidth);
    // Past the contour extent neither the body nor its contour reaches.
    if (sd >= uContourExtent) {
        fragColor = vec4(0.0);
        return;
    }
    vec2 gradient = fusedGradient(p, count, k, minWidth);
    vec3 optics = fusedOptics(p, count, k);
    float halfMinor = optics.x;
    gradient = fusedTurned(gradient, optics.yz);

    float uRefractionHeight = uOpticalProps.x;
    float uEdgeDistanceRange = uOpticalProps.z;
    float uRefractionAmount = uTextureSize.y;
    float uRefractionFitsShape = uTextureSize.x;

    float pixelSize = length(gradient);
    float fade = clamp(uOpticalProps.y, 0.0, 1.0) * max(pixelSize, 1e-4);
    float materialAlpha = 1.0 - smoothstep(-fade, fade, sd);
    float contourSupport = 1.0 - smoothstep(
        max(uContourExtent - fade, 0.0),
        uContourExtent,
        sd
    );
    float effectSupport = max(materialAlpha, contourSupport);
    if (effectSupport < 0.01) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 surfaceNormal = pixelSize > 0.0001 ? gradient / pixelSize : vec2(0.0);

    float bevel;
    float amount;
    if (uRefractionFitsShape > 0.5) {
        bevel = min(uRefractionHeight, 0.5 * halfMinor);
        amount = min(uRefractionAmount, halfMinor);
    } else {
        float lensScale = min(
            1.0,
            halfMinor / max(uRefractionHeight, 0.001)
        );
        bevel = uRefractionHeight * lensScale;
        amount = uRefractionAmount * lensScale;
    }
    float bevelX = 1.0 - clamp(max(-sd, 0.0) / max(bevel, 0.001), 0.0, 1.0);
    float displacementMagnitude = bevel > 0.001
        ? -amount * (1.0 - sqrt(1.0 - bevelX * bevelX))
        : 0.0;

    fragColor = encodeDisplacementData(
        surfaceNormal,
        displacementMagnitude,
        max(uRefractionAmount, 0.001),
        -sd,
        4.0 * uEdgeDistanceRange,
        uContourExtent
    );
}
